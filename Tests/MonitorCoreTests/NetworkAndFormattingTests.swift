import Foundation
import Testing
@testable import MonitorCore

struct NetworkAndFormattingTests {
    private func counter(_ received: UInt64, _ sent: UInt64) -> NetworkCounter {
        counter("en0:1", received, sent)
    }
    private func counter(_ id: String, _ received: UInt64, _ sent: UInt64) -> NetworkCounter {
        NetworkCounter(id: id, label: "Ethernet (en0)", received: received, sent: sent)
    }

    @Test func ratesUseActualIntervalAndStartAtZeroSessionBytes() {
        var accumulator = NetworkAccumulator()
        let first = accumulator.sample([counter(9_000_000_000, 5_000_000_000)], at: 100)
        #expect(first.receivedBytes == 0)
        #expect(first.downloadBytesPerSecond == nil)
        let next = accumulator.sample([counter(9_006_000_000, 5_001_000_000)], at: 103)
        #expect(next.downloadBytesPerSecond == 2_000_000)
        #expect(next.uploadBytesPerSecond == 1_000_000.0 / 3)
        #expect(next.receivedBytes == 6_000_000)
        #expect(next.sentBytes == 1_000_000)
        let idle = accumulator.sample([counter(9_006_000_000, 5_001_000_000)], at: 104)
        #expect(idle.downloadBytesPerSecond == 0)
        #expect(idle.receivedBytes == 6_000_000)
    }

    @Test func reconnectResetAndReadFailureDoNotProduceSpikes() {
        var accumulator = NetworkAccumulator()
        _ = accumulator.sample([counter(1000, 1000)], at: 1)
        _ = accumulator.sample([counter(2000, 2000)], at: 2)
        let reset = accumulator.sample([counter(10, 20)], at: 3)
        #expect(reset.downloadBytesPerSecond == 0)
        #expect(reset.receivedBytes == 1000)
        let disconnected = accumulator.sample([], at: 4)
        #expect(disconnected.interfaces.isEmpty)
        #expect(disconnected.downloadBytesPerSecond == 0)
        let reconnected = accumulator.sample([counter(50_000, 50_000)], at: 5)
        #expect(reconnected.downloadBytesPerSecond == 0)
        let unavailable = accumulator.sample(nil, at: 6)
        #expect(!unavailable.isAvailable)
        #expect(unavailable.downloadBytesPerSecond == nil)
        #expect(unavailable.receivedBytes == 1000)
        let restored = accumulator.sample([counter(90_000, 90_000)], at: 7)
        #expect(restored.downloadBytesPerSecond == nil)
        #expect(restored.receivedBytes == 1000)
    }

    @Test func multipleInterfacesAndReplacementUseIndependentBaselines() {
        var accumulator = NetworkAccumulator()
        _ = accumulator.sample([counter("en0:1", 1000, 0), counter("en1:2", 2000, 0)], at: 1)
        let next = accumulator.sample([counter("en0:1", 1300, 100), counter("en1:2", 2200, 200)], at: 3)
        #expect(next.downloadBytesPerSecond == 250)
        #expect(next.uploadBytesPerSecond == 150)
        let replacement = accumulator.sample([counter("en0:3", 9_000_000_000, 0)], at: 4)
        #expect(replacement.downloadBytesPerSecond == 0)
        #expect(replacement.receivedBytes == 500)
    }

    @Test func invalidTimeRebaselinesWithoutLosingSession() {
        var accumulator = NetworkAccumulator()
        _ = accumulator.sample([counter(10, 10)], at: 2)
        let next = accumulator.sample([counter(20, 20)], at: 2)
        #expect(next.downloadBytesPerSecond == nil)
        #expect(next.receivedBytes == 0)
        let invalid = accumulator.sample([counter(30, 30)], at: .nan)
        #expect(!invalid.isAvailable)
    }

    @Test func adaptiveCleanerSizeNeverRoundsMegabytesToZeroGigabytes() {
        let ru = Locale(identifier: "ru")
        #expect(ByteSizeFormat.string(52_700_000, locale: ru).contains("52,7"))
        #expect(ByteSizeFormat.string(52_700_000, locale: ru).contains("МБ"))
        #expect(ByteSizeFormat.string(1_500_000_000, locale: ru).contains("1,50"))
        #expect(ByteSizeFormat.string(1_500_000_000, locale: ru).contains("ГБ"))
        #expect(ByteSizeFormat.string(12_000, locale: ru).localizedCaseInsensitiveContains("КБ"))
        #expect(ByteSizeFormat.string(999_999_999, locale: ru).contains("МБ"))
        #expect(ByteSizeFormat.string(1_000_000_000, locale: ru).contains("ГБ"))
        for lang in AppLanguage.allCases where lang != .system {
            for count: UInt64 in [0, 1, 1500, 52_700_000, 1_500_000_000, .max] {
                let result = ByteSizeFormat.string(count, locale: Locale(identifier: lang.rawValue))
                #expect(!result.isEmpty)
                #expect(!result.contains("{0}"))
            }
        }
    }
}
