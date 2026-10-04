import Foundation
import IOKit
import IOKit.ps

public struct BatteryMetrics: Sendable {
    public let hasBattery: Bool
    public let charge: Double?
    public let isCharging: Bool
    public let powerSource: String
    public let condition: String?
    public let health: Double?
    public let cycles: Int?
    static let absent = BatteryMetrics(hasBattery: false, charge: nil, isCharging: false,
                                      powerSource: "AC", condition: nil, health: nil, cycles: nil)
}

struct BatteryService {
    func sample() -> BatteryMetrics {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return .absent }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }
            return Self.decode(description, registry: smartBattery())
        }
        return .absent // UPS and Bluetooth accessories are not laptop batteries.
    }

    static func decode(_ data: [String: Any], registry: [String: Any]) -> BatteryMetrics {
        let current = (data[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let max = (data[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let charge = percentage(current, max)
        let design = (registry["DesignCapacity"] as? NSNumber)?.doubleValue
        let capacity = (registry["NominalChargeCapacity"] as? NSNumber)?.doubleValue
            ?? (registry["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        let cycle = (registry["CycleCount"] as? NSNumber)?.intValue
        return BatteryMetrics(hasBattery: true, charge: charge,
            isCharging: data[kIOPSIsChargingKey] as? Bool ?? false,
            powerSource: data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue ? "AC" : "Battery",
            condition: data[kIOPSBatteryHealthKey] as? String,
            health: percentage(capacity, design), cycles: cycle.flatMap { $0 >= 0 ? $0 : nil })
    }

    private static func percentage(_ current: Double?, _ maximum: Double?) -> Double? {
        guard let current, let maximum, current.isFinite, maximum.isFinite, current >= 0, maximum > 0 else { return nil }
        return min(current / maximum * 100, 100)
    }

    private func smartBattery() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return properties?.takeRetainedValue() as? [String: Any] ?? [:]
    }
}
