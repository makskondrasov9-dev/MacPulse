import Foundation
import IOKit
import Metal

/// Inventory and counters are matched by registry identity, never by model name or a fixed VRAM profile.
struct GPUService {
    private struct MetalGPU {
        let id: UInt64
        let name: String
        let unified: Bool
        let workingSet: UInt64
    }
    private var metalDevices: [MetalGPU] = []
    private var inventoryDate: TimeInterval = -.infinity

    mutating func sampleAll() -> [GPUMetrics] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - inventoryDate >= 30 {
            metalDevices = MTLCopyAllDevices().map {
                MetalGPU(id: $0.registryID, name: $0.name, unified: $0.hasUnifiedMemory,
                         workingSet: $0.recommendedMaxWorkingSetSize)
            }
            inventoryDate = now
        }
        var results: [GPUMetrics] = []
        var seenEntries = Set<UInt64>()
        var coveredIDs = Set<UInt64>()
        // IOAccelerator covers Intel/AMD/legacy NVIDIA; IOGPU covers newer driver families.
        for family in ["IOAccelerator", "IOGPU", "IOPCIDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(family), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                let entryID = Self.registryID(entry)
                guard seenEntries.insert(entryID).inserted else { continue }
                if family == "IOPCIDevice" {
                    guard let code = Self.unsigned(Self.property(entry, "class-code")), (code >> 16) & 0xff == 3 else { continue }
                }
                let context = Self.context(entry)
                guard coveredIDs.isDisjoint(with: context.ids) else { continue }
                let metal = metalDevices.first { context.ids.contains($0.id) }
                let stats = Self.property(entry, "PerformanceStatistics") as? [String: Any] ?? [:]
                let vendor = Self.unsigned(context.properties["vendor-id"])
                let unified = metal?.unified ?? (vendor == 0x8086)
                let total = unified ? nil : Self.totalVRAM(context.properties)
                let used = unified ? nil : Self.activeVRAM(stats, total: total)
                let load = Self.utilization(stats)
                let name = Self.modelName(context.properties["model"]) ?? metal?.name ?? Self.vendorName(vendor)
                results.append(GPUMetrics(isUnified: unified, workingSetLimit: metal?.workingSet,
                    registryID: metal?.id ?? context.deviceID, sharedMemoryTotal: unified ? ProcessInfo.processInfo.physicalMemory : nil,
                    temperature: Self.temperature(stats), name: name, utilization: load, usedVRAM: used, totalVRAM: total,
                    issue: load == nil || (!unified && (total == nil || used == nil)) ? "Драйвер не публикует часть счётчиков" : nil))
                // Only GPU/PCI identities are covered, not common bridge/root ancestors.
                coveredIDs.formUnion([entryID, context.deviceID])
                if let metal { coveredIDs.insert(metal.id) }
            }
        }
        for metal in metalDevices where !coveredIDs.contains(metal.id) {
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(metal.id))
            guard entry != 0 else { continue } // Do not retain a disconnected eGPU until the next Metal refresh.
            IOObjectRelease(entry)
            results.append(GPUMetrics(isUnified: metal.unified, workingSetLimit: metal.workingSet,
                registryID: metal.id, sharedMemoryTotal: metal.unified ? ProcessInfo.processInfo.physicalMemory : nil,
                name: metal.name, utilization: nil, usedVRAM: nil, totalVRAM: nil,
                issue: "Драйвер не публикует часть счётчиков"))
        }
        // Preserve one stable primary GPU for the existing menu bar and history; show every device in the dashboard.
        return results.sorted {
            if $0.isUnified != $1.isUnified { return !$0.isUnified }
            return $0.registryID < $1.registryID
        }
    }

    static var unavailable: GPUMetrics {
        GPUMetrics(name: "GPU", utilization: nil, usedVRAM: nil, totalVRAM: nil,
                   issue: "Драйвер не публикует часть счётчиков")
    }

    /// Confirmed active device-local allocations. Never substitute a cached pool or system RAM.
    static func activeVRAM(_ stats: [String: Any], total: UInt64?) -> UInt64? {
        guard let used = unsigned(stats["inUseVidMemoryBytes"]), total.map({ used <= $0 }) ?? true else { return nil }
        return used
    }

    static func totalVRAM(_ properties: [String: Any]) -> UInt64? {
        if let bytes = unsigned(properties["VRAM,totalsize"]), bytes > 0, bytes < 1 << 50 { return bytes }
        if let mb = unsigned(properties["VRAM,totalMB"]), mb > 0 {
            let (bytes, overflow) = mb.multipliedReportingOverflow(by: 1_048_576)
            if !overflow && bytes < 1 << 50 { return bytes }
        }
        return nil
    }

    static func utilization(_ stats: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            if let number = stats[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                let value = number.doubleValue
                if value.isFinite && (0...100).contains(value) { return value }
            }
        }
        return nil
    }

    static func temperature(_ stats: [String: Any]) -> Double? {
        guard let value = (stats["Temperature(C)"] as? NSNumber)?.doubleValue,
              value.isFinite, (10...150).contains(value) else { return nil }
        return value
    }

    static func modelName(_ value: Any?) -> String? {
        let text: String?
        if let data = value as? Data { text = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8) }
        else { text = value as? String }
        return text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func unsigned(_ value: Any?) -> UInt64? {
        if let data = value as? Data, data.count == 4 || data.count == 8 {
            return data.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue < Double(UInt64.max) else { return nil }
        return number.uint64Value
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    private static func registryID(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }
    private static func vendorName(_ id: UInt64?) -> String {
        switch id { case 0x1002: "AMD GPU"; case 0x8086: "Intel GPU"; case 0x10de: "NVIDIA GPU"; default: "GPU" }
    }
    static func mergedProperties(accelerator: [String: Any], device: [String: Any]) -> [String: Any] {
        var result = accelerator
        if totalVRAM(device) != nil {
            result.removeValue(forKey: "VRAM,totalMB")
            result.removeValue(forKey: "VRAM,totalsize")
            for key in ["VRAM,totalMB", "VRAM,totalsize"] { if let value = device[key] { result[key] = value } }
        }
        for key in ["model", "vendor-id"] { if let value = device[key] { result[key] = value } }
        return result
    }

    private static func context(_ entry: io_registry_entry_t) -> (ids: Set<UInt64>, deviceID: UInt64, properties: [String: Any]) {
        var ids: Set<UInt64> = [registryID(entry)]
        var deviceID = registryID(entry)
        let keys = ["model", "vendor-id", "VRAM,totalMB", "VRAM,totalsize"]
        var properties = Dictionary(uniqueKeysWithValues: keys.compactMap { key in property(entry, key).map { (key, $0) } })
        var current = entry
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<8 {
            let id = registryID(current)
            ids.insert(id)
            if IOObjectConformsTo(current, "IOPCIDevice") != 0 {
                deviceID = id
                // Prefer physical device capacity over a driver-local budget.
                let physical = Dictionary(uniqueKeysWithValues: keys.compactMap { key in property(current, key).map { (key, $0) } })
                properties = mergedProperties(accelerator: properties, device: physical)
                break
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current); current = parent
        }
        return (ids, deviceID, properties)
    }
}
