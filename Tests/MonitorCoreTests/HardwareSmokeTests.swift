import Foundation
import Testing
@testable import MonitorCore

struct HardwareSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IMACMONITOR_HARDWARE_TEST"] == "1"))
    func liveCollectors() async throws {
        let collector = MetricCollector()
        let first = await collector.sample()
        try await Task.sleep(for: .seconds(2))
        let started = ContinuousClock.now
        let second = await collector.sample()
        let elapsed = started.duration(to: .now)
        await collector.close()
        #expect(first.cpu?.usage == nil)
        let usage = try #require(second.cpu?.usage)
        #expect((0...100).contains(usage))
        #expect(try #require(second.memory?.total) > 0)
        #expect(try #require(second.storage?.total) > 0)
        #expect(!second.processes.isEmpty)
        #expect(second.temperatures.count == (second.hardware.isAppleSilicon ? 0 : SMCService.keys.count))
        print("Battery present: \(second.battery.hasBattery); hardware: \(second.hardware)")
        #expect(second.temperatures.allSatisfy { $0.celsius.map { (10...150).contains($0) } ?? true })
        #expect(second.processes.allSatisfy { $0.cpu.map { $0.isFinite && $0 >= 0 } ?? true })
        print("Sampling duration: \(elapsed)")
        print("Live CPU: \(usage)%; processes read: \(second.processes.count)")
        print("GPU: \(second.gpu); memory: \(String(describing: second.memory))")
        for reading in second.temperatures {
            print("SMC \(reading.key): \(reading.celsius.map(String.init(describing:)) ?? reading.issue ?? "unavailable")")
        }
    }
}
