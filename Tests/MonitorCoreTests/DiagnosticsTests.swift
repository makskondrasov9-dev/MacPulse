import Foundation
import Testing
@testable import MonitorCore

@Suite(.serialized) struct DiagnosticsTests {
    @Test func qualityUnitsAndMissingMetrics() throws {
        let value = try NetworkQualityResult.parse(Data(#"{"dl_throughput":52700000,"ul_throughput":12000000,"base_rtt":12.5,"responsiveness":400}"#.utf8))
        #expect(value.downloadMbps == 52.7); #expect(value.uploadMbps == 12)
        #expect(value.latencyMilliseconds == 12.5); #expect(value.responsiveness == 400)
        let partial = try NetworkQualityResult.parse(Data(#"{"dl_throughput":1000000}"#.utf8))
        #expect(partial.uploadMbps == nil); #expect(partial.responsiveness == nil)
        #expect(throws: (any Error).self) { try NetworkQualityResult.parse(Data(#"{"dl_throughput":true}"#.utf8)) }
        #expect(throws: (any Error).self) { try NetworkQualityResult.parse(Data(#"{"error":"offline"}"#.utf8)) }
    }
    @Test func ipValidationAndHistoryBound() throws {
        #expect(NetworkDiagnosticsService.validIP("2001:db8::1"))
        #expect(NetworkDiagnosticsService.validIP("192.0.2.1"))
        #expect(!NetworkDiagnosticsService.validIP("not an ip"))
        var history = IPHistory()
        let identity = [NetworkIdentity(interface: "en0", addresses: ["192.0.2.1"])]
        history.record(interfaces: identity, publicIP: nil)
        history.record(interfaces: identity, publicIP: nil)
        #expect(history.entries.count == 1)
        history.record(interfaces: identity, publicIP: "203.0.113.1")
        #expect(history.entries.count == 2)
        for index in 0..<220 { history.record(interfaces: [NetworkIdentity(interface: "utun\(index)", addresses: ["2001:db8::1"])], publicIP: nil) }
        #expect(history.entries.count == 200)
        let restored = try JSONDecoder().decode(IPHistory.self, from: JSONEncoder().encode(history))
        #expect(restored.entries.count == 200)
    }
    @Test func peaksRejectInvalidAndNeverDecrease() {
        var peaks = SessionPeaks()
        peaks.record(temperature: 80, memory: 100, gpu: 50)
        peaks.record(temperature: .nan, memory: 90, gpu: 110)
        peaks.record(temperature: -7, memory: nil, gpu: 40)
        #expect(peaks.cpuTemperature == 80); #expect(peaks.memoryBytes == 100); #expect(peaks.gpuLoad == 50)
    }
    @Test func usageMidnightAndSleep() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 86400)
        var usage = DailyUsage(now: midnight.addingTimeInterval(-10), calendar: calendar)
        usage.record(id: "app", name: "App", from: midnight.addingTimeInterval(-2), to: midnight.addingTimeInterval(2), calendar: calendar)
        #expect(usage.top.first?.seconds == 2)
        usage.record(id: "app", name: "App", from: midnight, to: midnight.addingTimeInterval(3600), calendar: calendar)
        #expect(usage.top.first?.seconds == 2)
        usage.resetDay(at: midnight.addingTimeInterval(86400), calendar: calendar)
        #expect(usage.top.isEmpty)
    }
    @Test func diskCleanupAndCancel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = try await BenchmarkEngine.disk(bytes: 4 * 1024 * 1024, directory: dir)
        #expect(result.writeMBps > 0); #expect(result.readMBps > 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        let task = Task { try await BenchmarkEngine.disk(directory: dir) { _ in try? await Task.sleep(for: .seconds(1)) } }
        try await Task.sleep(for: .milliseconds(50)); task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation should throw") } catch is CancellationError {} catch { throw error }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
    @Test func networkCancellationReapsProcess() async throws {
        let service = NetworkDiagnosticsService()
        let started = Date()
        let task = Task { try await service.measure(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation should throw") } catch is CancellationError {} catch { throw error }
        #expect(Date().timeIntervalSince(started) < 5)
    }
    @Test func networkTimeoutAndExitFailure() async throws {
        await #expect(throws: (any Error).self) { try await NetworkDiagnosticsService().measure(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.1) }
        await #expect(throws: (any Error).self) { try await NetworkDiagnosticsService().measure(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: []) }
    }
    @Test func persistentUsageRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AnalyticsStore(directory: dir)
        var usage = DailyUsage()
        usage.record(id: "app", name: "App", from: Date().addingTimeInterval(-2), to: Date())
        try await store.save(usage, name: "usage.json")
        let loaded = await store.load(DailyUsage.self, name: "usage.json")
        #expect(loaded?.top.first?.id == "app")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPULSE_RUN_DIAGNOSTICS"] == "1"))
    func actualPublicIP() async throws {
        let ip = try await NetworkDiagnosticsService().publicIP()
        #expect(NetworkDiagnosticsService.validIP(ip))
    }
    @Test func cpuCancellation() async throws {
        let task = Task { try await BenchmarkEngine.cpu(seconds: 15) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation should throw") } catch is CancellationError {} catch { throw error }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPULSE_RUN_DIAGNOSTICS"] == "1"))
    func actualMetalBenchmark() async throws {
        let result = try await BenchmarkEngine.gpu(seconds: 15)
        print("Metal batches in 15 s: \(result)")
        #expect(result > 0)
        let task = Task { try await BenchmarkEngine.gpu(seconds: 15) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation should throw") } catch is CancellationError {} catch { throw error }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPULSE_RUN_DIAGNOSTICS"] == "1"))
    func actualHardwareBenchmarks() async throws {
        let disk = try await BenchmarkEngine.disk()
        print("Disk 1 GB: write \(disk.writeMBps) MB/s; read \(disk.readMBps) MB/s")
        #expect(disk.bytes == 1_000_000_000)
        let batches = try await BenchmarkEngine.cpu(seconds: 15)
        #expect(batches > 0)
        let result = try await NetworkDiagnosticsService().measure()
        print("networkQuality: download \(result.downloadMbps ?? -1) Mbps; upload \(result.uploadMbps ?? -1) Mbps; RPM \(result.responsiveness ?? -1)")
        #expect(result.downloadMbps != nil)
    }
}
