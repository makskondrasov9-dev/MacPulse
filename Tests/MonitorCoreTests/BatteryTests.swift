import IOKit.ps
import Testing
@testable import MonitorCore

struct BatteryTests {
    @Test func batteryCapacityAndHealthUseDifferentDenominators() {
        let result = BatteryService.decode([kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 80,
                                            kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue],
                                           registry: ["DesignCapacity": 6000, "NominalChargeCapacity": 4800, "CycleCount": 123])
        #expect(result.hasBattery && result.isCharging)
        #expect(result.charge == 50 && result.health == 80 && result.cycles == 123)
        #expect(result.powerSource == "AC")
    }
    @Test func missingAndInvalidBatteryReadingsStayUnknown() {
        let result = BatteryService.decode([kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 0], registry: [:])
        #expect(result.charge == nil && result.health == nil && result.cycles == nil)
        #expect(!BatteryMetrics.absent.hasBattery)
    }
}
