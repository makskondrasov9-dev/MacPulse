import Foundation

public struct CPUMetrics: Sendable {
    public let usage: Double?
    public let cores: [Double]
}

public struct MemoryMetrics: Sendable {
    public let total: UInt64
    public let wired: UInt64
    public let active: UInt64
    public let compressed: UInt64
    public let freeAndInactive: UInt64
    public var used: UInt64 { wired + active + compressed }
}

public struct GPUMetrics: Sendable {
    public var isUnified: Bool = false
    public var workingSetLimit: UInt64? = nil
    public let name: String
    public let utilization: Double?
    public let usedVRAM: UInt64?
    public let totalVRAM: UInt64
    public let issue: String?
}

public struct StorageMetrics: Sendable {
    public let total: UInt64
    public let free: UInt64
    public var used: UInt64 { total - min(free, total) }
}

public struct ProcessMetrics: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    /// 100% means one fully occupied logical core.
    public let cpu: Double?
    public let residentBytes: UInt64
}

public struct MonitorSnapshot: Sendable {
    public let battery: BatteryMetrics
    public let hardware: HardwareProfile
    public let thermalState: String
    public let date: Date
    public let cpu: CPUMetrics?
    public let memory: MemoryMetrics?
    public let gpu: GPUMetrics
    public let storage: StorageMetrics?
    public let uptime: TimeInterval?
    public let temperatures: [TemperatureReading]
    public let processes: [ProcessMetrics]

    public func temperature(keys: [String]) -> Double? {
        for key in keys {
            if let value = temperatures.first(where: { $0.key == key })?.celsius { return value }
        }
        return nil
    }
    public var cpuTemperature: Double? { temperature(keys: ["TC0D", "TC0P", "TC0E", "TC0F"]) }
    public var gpuTemperature: Double? { temperature(keys: ["TG0D", "TG0P"]) }
}
