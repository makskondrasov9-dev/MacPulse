import CSystem
import DiskArbitration
import Foundation
import IOKit

public struct StorageHealth: Sendable, Equatable {
    public enum Status: Sendable { case passed, warning }
    public let model: String
    public let status: Status?
    public let lifeRemaining: Double?
    public let terabytesWritten: Double?
}

/// Slow-changing disk health is sampled at most once per five minutes on a
/// utility task, never in the main actor or the regular metrics sampling path.
public actor StorageHealthService {
    private var cached: StorageHealth?
    private var lastPoll = -Double.infinity
    private var refreshing = false
    public init() {}
    public func sample() -> StorageHealth? {
        let now = ProcessInfo.processInfo.systemUptime
        if !refreshing && now - lastPoll >= 300 {
            refreshing = true; lastPoll = now
            Task {
                let result = await Task.detached(priority: .utility) { Self.readBootVolume() }.value
                cached = result
                refreshing = false
            }
        }
        return cached
    }

    /// Follow only ancestors of the displayed boot volume. Never attach another
    /// disk's SMART result to Storage /. Multiple physical stores are ambiguous.
    static func readBootVolume() -> StorageHealth? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: "/") as CFURL) else { return nil }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { return nil }
        var pending = [media], visited = Set<UInt64>(), candidates: [StorageHealth] = []
        var physicalDevices = Set<UInt64>()
        while !pending.isEmpty {
            let entry = pending.removeLast()
            defer { IOObjectRelease(entry) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &id)
            guard visited.insert(id).inserted else { continue }
            if IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0 { physicalDevices.insert(id) }
            let nvme = property(entry, "NVMe SMART Capable") as? Bool == true
            let ata = property(entry, "SMART Capable") as? Bool == true
            if nvme || ata {
                let characteristics = property(entry, "Device Characteristics") as? [String: Any] ?? [:]
                let model = (characteristics["Product Name"] as? String) ?? (property(entry, "Model Number") as? String) ?? "SSD"
                var bytes = [UInt8](repeating: 0, count: 512)
                var condition: Int32 = -1
                let result = MonitorReadSMART(entry, nvme ? 1 : 0, &bytes, &condition)
                if result == KERN_SUCCESS || condition >= 0 {
                    if let health = decode(bytes: result == KERN_SUCCESS ? bytes : [], nvme: nvme, condition: condition, model: model) {
                        candidates.append(health)
                        // Don't read a second interface belonging to the same drive.
                        continue
                    }
                }
            }
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetParentIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS {
                while case let parent = IOIteratorNext(iterator), parent != 0 { pending.append(parent) }
                IOObjectRelease(iterator)
            }
        }
        return physicalDevices.count == 1 && candidates.count == 1 ? candidates.first : nil
    }
    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func decode(bytes: [UInt8], nvme: Bool, condition: Int32, model: String) -> StorageHealth? {
        let status: StorageHealth.Status? = condition == 0 ? .passed : (condition == 1 ? .warning : nil)
        var life: Double?, written: Double?
        if bytes.count == 512 {
            if nvme {
                // NVMe health log: percentage used at byte 5; data units written
                // at byte 48 are a 128-bit LE count of 1000 * 512 bytes.
                life = Double(max(0, 100 - Int(bytes[5])))
                var units = 0.0
                for byte in bytes[48..<64].reversed() { units = units * 256 + Double(byte) }
                let tb = units * 512_000 / 1_000_000_000_000
                if tb.isFinite { written = tb }
            } else if model.trimmingCharacters(in: .whitespaces).hasPrefix("Samsung SSD 860 EVO") ||
                        model.trimmingCharacters(in: .whitespaces).hasPrefix("Samsung SSD 870 EVO") {
                // Samsung's model-specific attributes: 177 normalized wear life,
                // 241 Total LBAs Written (512-byte units). Never apply to other ATA vendors.
                for offset in stride(from: 2, to: 362, by: 12) {
                    if bytes[offset] == 177, bytes[offset + 3] <= 100 { life = Double(bytes[offset + 3]) }
                    if bytes[offset] == 241 {
                        var lbas: UInt64 = 0
                        for i in 0..<6 { lbas |= UInt64(bytes[offset + 5 + i]) << (8 * i) }
                        written = Double(lbas) * 512 / 1_000_000_000_000
                    }
                }
            }
        }
        guard status != nil || life != nil || written != nil else { return nil }
        return StorageHealth(model: model, status: status, lifeRemaining: life, terabytesWritten: written)
    }
}
