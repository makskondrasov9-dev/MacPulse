import Foundation
import Testing
@testable import MonitorCore

struct MonitoringPolicyTests {
    @Test func widgetDimensions() {
        #expect(PresentationPolicy.widgetSize("small").width == 160)
        #expect(PresentationPolicy.widgetSize("small").height == 160)
        #expect(PresentationPolicy.widgetSize("medium").width == 340)
        #expect(PresentationPolicy.widgetSize("medium").height == 160)
        #expect(PresentationPolicy.widgetSize("large").height == 340)
        #expect(PresentationPolicy.widgetSize("obsolete").width == 340)
    }
    @Test func loadColorBoundaries() {
        #expect(PresentationPolicy.loadBand(49.9) == 0)
        #expect(PresentationPolicy.loadBand(50) == 1)
        #expect(PresentationPolicy.loadBand(80) == 1)
        #expect(PresentationPolicy.loadBand(80.1) == 2)
        #expect(PresentationPolicy.loadBand(nil) == nil)
        #expect(PresentationPolicy.loadBand(.nan) == nil)
    }
    @Test func noMetricsSkipsHeavyServices() async {
        let service = MetricCollector()
        let snapshot = await service.sample(selection: [])
        #expect(snapshot.cpu == nil && snapshot.memory == nil)
        #expect(snapshot.gpus.isEmpty && snapshot.temperatures.isEmpty && snapshot.processes.isEmpty)
        #expect(snapshot.storage == nil && snapshot.storageHealth == nil && !snapshot.battery.hasBattery)
        #expect(!snapshot.network.isAvailable)
        await service.close()
    }
    @Test func cpuOnlyHasNoUnrequestedMetrics() async {
        let service = MetricCollector()
        _ = await service.sample(selection: .cpu)
        let snapshot = await service.sample(selection: .cpu)
        #expect(snapshot.cpu != nil)
        #expect(snapshot.memory == nil && snapshot.gpus.isEmpty && snapshot.processes.isEmpty)
        #expect(snapshot.temperatures.isEmpty && snapshot.storage == nil && !snapshot.network.isAvailable)
        await service.close()
    }
}
