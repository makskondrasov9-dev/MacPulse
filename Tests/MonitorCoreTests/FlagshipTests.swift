import Foundation
import Testing
@testable import MonitorCore

struct FlagshipTests {
    func rows(_ text: String) -> [ProcessConnection] { ConnectionParser.parse(Data(text.utf8)) }
    @Test func tcpFields() {
        let parsed = rows("p123\0cBrowser\0\nf4\0PTCP\0n127.0.0.1:50100->17.1.2.3:443\0TST=ESTABLISHED\0\n")
        #expect(parsed.count == 1)
        #expect(parsed.first?.pid == 123)
        #expect(parsed.first?.remote == "17.1.2.3:443")
        #expect(parsed.first?.state == "ESTABLISHED")
        #expect(parsed.first?.isActiveRemote == true)
    }
    @Test func ipv6AndUDP() {
        let parsed = rows("p12\ncDNS\nf1\nPUDP\nn[::1]:53->[2001:db8::1]:53\nf2\nPTCP\nn*:443\nTST=LISTEN\n")
        #expect(parsed.count == 2)
        #expect(parsed[0].remote == "[2001:db8::1]:53")
        #expect(parsed[1].remote == nil)
        #expect(parsed[1].state == "LISTEN")
        #expect(!parsed[1].isActiveRemote)
        #expect(parsed[0].isActiveRemote)
    }
    @Test func parserResetsProcessAndSocket() {
        let parsed = rows("p1\ncOne\nf1\nPTCP\nn*:80\nTST=LISTEN\np2\ncTwo\nf2\nPUDP\nn*:53\n")
        #expect(parsed.count == 2)
        #expect(parsed[1].process == "Two")
        #expect(parsed[1].state == "UDP")
    }
    @Test func parserRejectsMalformed() {
        #expect(rows("lsof: permission denied\npbad\nf1\nPTCP\nn*:1\n").isEmpty)
        #expect(rows("p1\nf1\nPTCP\nnx->y->z\n").isEmpty)
        #expect(rows("p1\nf1\nPFILE\nn/tmp/file\n").isEmpty)
    }
    @Test func parserDeduplicates() {
        #expect(rows("p1\ncA\nf1\nPTCP\nn*:80\nf1\nPTCP\nn*:80\n").count == 1)
    }
    @Test func connectionSearch() throws {
        let row = try #require(rows("p123\ncBrowser\nf1\nPTCP\nn127.0.0.1:22->1.2.3.4:443\n").first)
        #expect(row.matches("BROWSER")); #expect(row.matches("443")); #expect(row.matches("123")); #expect(!row.matches("xyz"))
    }
    @Test func activationSplitsUsage() {
        let start = Date(); var usage = DailyUsage(now: start); var tracker = ForegroundUsageTracker()
        tracker.activate(id: "a", name: "A", at: start, eligible: true, usage: &usage)
        tracker.activate(id: "b", name: "B", at: start.addingTimeInterval(0.5), eligible: true, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(2), eligible: true, usage: &usage)
        #expect(usage.entries["a"]?.seconds == 0.5)
        #expect(usage.entries["b"]?.seconds == 1.5)
    }
    @Test func usageExcludesSleepAndIdle() {
        let start = Date(); var usage = DailyUsage(now: start); var tracker = ForegroundUsageTracker()
        tracker.activate(id: "a", name: "A", at: start, eligible: true, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(60), eligible: true, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(62), eligible: false, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(64), eligible: true, usage: &usage)
        #expect(usage.entries["a"]?.seconds == 2)
    }
    @Test func delayedSamplesDoNotDoubleCount() {
        let start = Date(); var usage = DailyUsage(now: start); var tracker = ForegroundUsageTracker()
        tracker.activate(id: "a", name: "A", at: start, eligible: true, usage: &usage)
        tracker.activate(id: "b", name: "B", at: start.addingTimeInterval(2), eligible: true, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(1), eligible: true, usage: &usage)
        tracker.tick(at: start.addingTimeInterval(3), eligible: true, usage: &usage)
        #expect(usage.entries["a"]?.seconds == 2); #expect(usage.entries["b"]?.seconds == 1)
    }
    @Test func peakTimestampOnlyChangesOnNewMaximum() {
        let start = Date(); var peaks = SessionPeaks()
        peaks.record(temperature: 50, memory: 100, gpu: 20, date: start)
        peaks.record(temperature: 50, memory: 90, gpu: 10, date: start.addingTimeInterval(2))
        #expect(peaks.cpuTemperatureDate == start)
        peaks.record(temperature: .nan, memory: nil, gpu: nil)
        #expect(peaks.cpuTemperature == 50)
        peaks.record(temperature: 60, memory: nil, gpu: nil, date: start.addingTimeInterval(4))
        #expect(peaks.cpuTemperatureDate == start.addingTimeInterval(4))
    }
}
