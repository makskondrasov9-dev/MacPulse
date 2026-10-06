import Foundation

/// Runs off the main actor. One sequential sampling loop prevents overlapping polls.
public actor MetricCollector {
    private let smc = SMCService()
    private var cpu = CPUService()
    private let memory = MemoryService()
    private var gpu = GPUService()
    private let battery = BatteryService()
    private let storage = StorageService()
    private var network = NetworkMonitorService()
    private var processes = ProcessService()

    public init() {}

    public func sample() async -> MonitorSnapshot {
        #if arch(x86_64)
        let temperatures = await smc.sample()
        #else
        let temperatures: [TemperatureReading] = []
        #endif
        let graphics = gpu.sampleAll()
        return MonitorSnapshot(battery: battery.sample(), hardware: .current, thermalState: HardwareProfile.thermalState, date: Date(), cpu: cpu.sample(), memory: memory.sample(), gpu: graphics.first ?? GPUService.unavailable, gpus: graphics,
                               network: network.sample(), storage: storage.sample(), uptime: CPUService.uptime(), temperatures: temperatures,
                               processes: processes.sample())
    }

    public func close() async { await smc.close() }
}
