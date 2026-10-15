import Testing
@testable import MonitorCore

struct DesktopWidgetPolicyTests {
    @Test func legacySelectionsAndOptionalSummary() {
        #expect(DesktopWidgetPolicy.enabled(master: false, choices: [:]).isEmpty)
        #expect(DesktopWidgetPolicy.enabled(master: true, choices: [:]) == [.compute, .memory, .network])
        #expect(DesktopWidgetPolicy.enabled(master: true, choices: [.compute: false, .memory: false, .network: false, .summary: true]) == [.summary])
    }
    @Test func individuallyDisabledAndEmptySelection() {
        #expect(DesktopWidgetPolicy.enabled(master: true, choices: [.compute: false, .memory: false]) == [.network])
        #expect(DesktopWidgetPolicy.enabled(master: true, choices: [.compute: false, .memory: false, .network: false]).isEmpty)
    }
    @Test func themesNeverLeakOtherSensors() {
        #expect(DesktopWidgetKind.compute.metrics == [.cpu, .gpu, .temperature])
        #expect(DesktopWidgetKind.memory.metrics == [.memory, .storage])
        #expect(DesktopWidgetKind.network.metrics == [.network])
        #expect(!DesktopWidgetKind.summary.metrics.contains(.processes))
    }
    @Test func summaryCannotBecomeSmall() {
        #expect(!DesktopWidgetKind.summary.supportsSmall)
        #expect(DesktopWidgetKind.summary.normalizedSize("small") == "medium")
        #expect(DesktopWidgetKind.summary.normalizedSize("large") == "large")
        #expect(DesktopWidgetKind.network.normalizedSize("small") == "small")
    }
    @Test func sharedChartColorModes() {
        for network in [false, true] {
            #expect(MenuChartPolicy.color(mode: "accent", network: network, load: 99) == .accent)
            #expect(MenuChartPolicy.color(mode: "mono", network: network, load: 99) == .primary)
            #expect(MenuChartPolicy.color(mode: "load", network: network, load: 20) == .green)
            #expect(MenuChartPolicy.color(mode: "load", network: network, load: 70) == .orange)
            #expect(MenuChartPolicy.color(mode: "load", network: network, load: 95) == .red)
        }
        #expect(MenuChartPolicy.color(mode: "category", network: false, load: nil) == .cyan)
        #expect(MenuChartPolicy.color(mode: "category", network: true, load: nil) == .green)
    }
    @Test func trafficIntensityIgnoresIdleNoiseAndInvalidSamples() {
        #expect(MenuChartPolicy.networkIntensity([nil]) == nil)
        #expect(MenuChartPolicy.networkIntensity([.nan]) == nil)
        #expect(MenuChartPolicy.networkIntensity([-.infinity]) == nil)
        #expect(MenuChartPolicy.networkIntensity([0]) == 0)
        #expect((MenuChartPolicy.networkIntensity([1024]) ?? 100) < 1)
        #expect(MenuChartPolicy.networkIntensity([10_485_760, 5_242_880]) == 50)
        #expect(MenuChartPolicy.networkIntensity([10_485_760]) == 100)
    }
}
