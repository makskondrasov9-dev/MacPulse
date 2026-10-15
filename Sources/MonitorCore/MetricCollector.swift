import Foundation
import IOKit.pwr_mgt

/// Runs off the main actor. One sequential sampling loop prevents overlapping polls.
public actor MetricCollector {
    private let smc = SMCService()
    private var cpu = CPUService()
    private let memory = MemoryService()
    private var gpu = GPUService()
    private let battery = BatteryService()
    private let storage = StorageService()
    private let storageHealth = StorageHealthService()
    private var network = NetworkMonitorService()
    private var processes = ProcessService()

    public init() {}

    public func sample(selection: MetricSelection = .all) async -> MonitorSnapshot {
        #if arch(x86_64)
            let temperatures =
                selection.contains(.temperature)
                ? await smc.sample(keys: selection == .all ? SMCService.keys : (["TC0D", "TC0P", "TC0E", "TC0F"] + (selection.contains(.gpu) ? ["TG0D", "TG0P"] : []))) : []
        #else
            let temperatures: [TemperatureReading] = []
        #endif
        let graphics = selection.contains(.gpu) ? gpu.sampleAll() : []
        var speedLimit: Double?
        if selection.contains(.cpuDetails) {
            var status: Unmanaged<CFDictionary>?
            if IOPMCopyCPUPowerStatus(&status) == kIOReturnSuccess,
               let values = status?.takeRetainedValue() as? [String: Any] {
                speedLimit = (values[kIOPMCPUPowerLimitProcessorSpeedKey] as? NSNumber)?.doubleValue
            }
        }
        return MonitorSnapshot(
            battery: selection.contains(.battery) ? battery.sample() : BatteryMetrics.absent, hardware: .current,
            thermalState: HardwareProfile.thermalState, date: Date(),
            cpu: selection.contains(.cpu) ? cpu.sample() : nil,
            memory: selection.contains(.memory) ? memory.sample() : nil, gpu: graphics.first ?? GPUService.unavailable,
            gpus: graphics,
            network: selection.contains(.network) ? network.sample() : NetworkMetrics(),
            cpuSpeedLimit: speedLimit,
            storageHealth: selection.contains(.storage) ? await storageHealth.sample() : nil,
            storage: selection.contains(.storage) ? storage.sample() : nil,
            uptime: selection == .all ? CPUService.uptime() : nil, temperatures: temperatures,
            processes: selection.contains(.processes) ? processes.sample() : [])
    }

    public func close() async { await smc.close() }
}
