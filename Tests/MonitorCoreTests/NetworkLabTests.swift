import Foundation
import Testing
@testable import MonitorCore

private actor LabEvents {
    var lines: [String] = []
    var rates: [Double] = []
    func line(_ value: String) { lines.append(value) }
    func rate(_ value: CPUProgress) { rates.append(value.batchesPerSecond) }
}

@Suite(.serialized) struct NetworkLabTests {
    @Test func traceParsing() {
        let hop = TraceHop.parse(" 2  192.0.2.1  4.52 ms  5.1 ms !H")
        #expect(hop?.number == 2); #expect(hop?.address == "192.0.2.1")
        #expect(hop?.milliseconds == [4.52, 5.1]); #expect(hop?.timedOut == false)
        #expect(TraceHop.parse(" 3 * * *")?.timedOut == true)
        #expect(TraceHop.parse(" 4 2001:db8::1  0.18 ms")?.address == "2001:db8::1")
        #expect(TraceHop.parse("traceroute to example.com") == nil)
        #expect(TraceHop.parse("999 192.0.2.1 5 ms") == nil)
    }
    @Test func hostValidationRejectsOptionsAndShellSyntax() {
        for value in ["example.com", "192.0.2.1", "2001:db8::1", "localhost"] { #expect(NetworkLab.validHost(value)) }
        for value in ["", "-n", "foo;id", "foo bar", "https://example.com", "foo\nbar", "a..b", "-foo.com"] { #expect(!NetworkLab.validHost(value)) }
    }
    @Test func ipv6UsesOnlySelectedInterface() {
        let interfaces = [NetworkIdentity(interface: "en0", addresses: ["192.0.2.1", "fe80::1%en0"]),
                          NetworkIdentity(interface: "utun0", addresses: ["fe80::2%utun0"])]
        #expect(NetworkLab.ipv6Addresses(interfaces, primary: "en0") == ["fe80::1%en0"])
        #expect(NetworkLab.ipv6Addresses(interfaces, primary: nil).isEmpty)
    }
    @Test func configurableIPValidation() throws {
        let config = try PublicIPConfiguration(endpoint: " https://example.com/ip ", interval: 90)
        #expect(config.url.host == "example.com"); #expect(config.interval == 90)
        for endpoint in ["http://example.com", "file:///tmp/ip", "https://user:pass@example.com", "https://example.com/#fragment", "invalid"] {
            #expect(throws: (any Error).self) { try PublicIPConfiguration(endpoint: endpoint, interval: 60) }
        }
        for interval in [Double.nan, .infinity, 0, 14, 3601] {
            #expect(throws: (any Error).self) { try PublicIPConfiguration(endpoint: PublicIPConfiguration.defaultURL, interval: interval) }
        }
    }
    @Test func plainAndJSONIPResponses() throws {
        #expect(try PublicIPConfiguration.parse(Data("203.0.113.9\n".utf8)) == "203.0.113.9")
        #expect(try PublicIPConfiguration.parse(Data(#"{"ip":"2001:db8::1"}"#.utf8)) == "2001:db8::1")
        for data in [Data("<html>error</html>".utf8), Data(repeating: 65, count: 1025), Data(#"{"ip":false}"#.utf8)] {
            #expect(throws: (any Error).self) { try PublicIPConfiguration.parse(data) }
        }
    }
    @Test func networkConfigRequiresHTTPSForEveryTarget() throws {
        let good = Data(#"{"urls":{"small_https_download_url":"https://a.test/s","large_https_download_url":"https://a.test/l","https_upload_url":"https://a.test/u"}}"#.utf8)
        #expect(try NetworkTestConfiguration.endpoints(good).count == 3)
        let bad = Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "https://a.test/u", with: "file:///tmp/secret").utf8)
        #expect(throws: (any Error).self) { try NetworkTestConfiguration.endpoints(bad) }
    }
    @Test func streamingArrivesBeforeProcessExits() async throws {
        let events = LabEvents()
        let task = Task { try await DiagnosticProcess.run("/usr/bin/perl", arguments: ["-e", "$|=1; print qq(first\\n); select undef,undef,undef,0.4; print qq(second\\n);"], timeout: 3) { await events.line($0) } }
        for _ in 0..<20 { if await !events.lines.isEmpty { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(await events.lines == ["first"])
        let output = try await task.value
        #expect(output.status == 0); #expect(await events.lines == ["first", "second"])
    }
    @Test func processOutputLimit() async {
        await #expect(throws: (any Error).self) {
            try await DiagnosticProcess.run("/usr/bin/printf", arguments: [String(repeating: "x", count: 1000)], timeout: 2, maximumBytes: 100)
        }
    }
    @Test func performanceReferenceIsMeasuredAndBounded() {
        var reference = CPUPerformanceReference(best: .nan)
        #expect(reference.record(-1) == nil); #expect(reference.record(.infinity) == nil)
        #expect(reference.record(100) == 100); #expect(reference.record(50) == 50)
        #expect(reference.record(200) == 100); #expect(reference.best == 200)
    }
    @Test func workerCountAndLiveCPUProgress() async throws {
        await #expect(throws: (any Error).self) { try await BenchmarkEngine.cpu(seconds: 15, workers: 0) }
        await #expect(throws: (any Error).self) { try await BenchmarkEngine.cpu(seconds: 15, workers: CPUCapabilities.maximumWorkers + 1) }
        let events = LabEvents()
        let task = Task { try await BenchmarkEngine.cpu(seconds: 15, workers: 1) { await events.rate($0) } }
        for _ in 0..<100 { if await !events.rates.isEmpty { break }; try await Task.sleep(for: .milliseconds(50)) }
        task.cancel()
        do { _ = try await task.value; Issue.record("CPU cancellation expected") } catch is CancellationError {}
        #expect(await events.rates.contains { $0.isFinite && $0 > 0 })
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MACPULSE_RUN_DIAGNOSTICS"] == "1"))
    func actualNetworkLab() async throws {
        let events = LabEvents()
        try await NetworkLab.trace(host: "127.0.0.1") { hop in await events.line(String(hop.number)) }
        #expect(await !events.lines.isEmpty)
        _ = try await NetworkLab.ipv6()
        let data = try await DiagnosticHTTP.fetch(URL(string: "https://mensura.cdn-apple.com/api/v1/gm/config")!, maximumBytes: 65_536)
        let endpoints = try NetworkTestConfiguration.endpoints(data)
        let latency = try await DiagnosticHTTP.latency(URL(string: endpoints[0])!)
        #expect(latency > 0)
        let result = try await NetworkDiagnosticsService().measure()
        #expect(result.downloadMbps != nil); #expect(result.uploadMbps != nil)
        print("Live Network Lab: download \(result.downloadMbps ?? -1), upload \(result.uploadMbps ?? -1) Mbps; HTTP latency \(latency) ms")
    }

}
