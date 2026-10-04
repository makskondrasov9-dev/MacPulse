import Foundation
import IOKit
#if arch(arm64)
import Metal
#endif

struct GPUService {
    // Profile fallback for iMac18,3 / Radeon Pro 570, never a fabricated usage value.
    private let profileVRAM: UInt64 = 4 * 1_024 * 1_024 * 1_024

    #if arch(arm64)
    private let device = MTLCreateSystemDefaultDevice()
    #endif

    func sample() -> GPUMetrics {
        #if arch(arm64)
        // currentAllocatedSize describes THIS process's Metal resources, not
        // system-wide GPU usage. Never report it as the machine's used VRAM.
        return GPUMetrics(isUnified: true, workingSetLimit: device?.recommendedMaxWorkingSetSize,
                          name: "Unified VRAM", utilization: nil, usedVRAM: nil,
                          totalVRAM: ProcessInfo.processInfo.physicalMemory,
                          issue: "Общая память CPU/GPU. Системная загрузка GPU недоступна через публичный Metal API.")
        #else
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return unavailable()
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            // Intel iMacs can expose both integrated and discrete accelerators.
            let klass = IOObjectCopyClass(entry)?.takeRetainedValue() as String? ?? ""
            guard klass.localizedCaseInsensitiveContains("AMD") || klass.localizedCaseInsensitiveContains("Radeon") else { continue }
            guard let raw = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = raw as? [String: Any] else { continue }
            let total = profileVRAM
            let used = Self.activeVRAM(stats, total: total)
            let rawLoad = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
            let load = rawLoad.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
            return GPUMetrics(name: "AMD Radeon Pro", utilization: load,
                              usedVRAM: used.flatMap { $0 <= total ? $0 : nil }, totalVRAM: total,
                              issue: used == nil || load == nil ? "Драйвер не публикует часть счётчиков" : nil)
        }
        return unavailable()
        #endif
    }

    /// Active device-local allocations only. Driver pools and system RAM are not VRAM in use.
    static func activeVRAM(_ stats: [String: Any], total: UInt64) -> UInt64? {
        guard let used = unsigned(stats["inUseVidMemoryBytes"]), used <= total else { return nil }
        return used
    }

    private static func unsigned(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite,
              number.doubleValue >= 0, number.doubleValue < Double(UInt64.max) else { return nil }
        return number.uint64Value
    }

    private func unavailable() -> GPUMetrics {
        GPUMetrics(name: "AMD Radeon Pro 570 (профиль)", utilization: nil, usedVRAM: nil,
                   totalVRAM: profileVRAM, issue: "Счётчики AMD IOAccelerator недоступны")
    }
}
