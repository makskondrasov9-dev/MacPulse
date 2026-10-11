import Foundation
import Testing
@testable import MonitorCore

struct MenuAndStorageHealthTests {
    @Test func legacyPreferencesKeepTheirStyle() {
        #expect(MenuBarDisplayMode.resolve("full") == .fullText)
        #expect(MenuBarDisplayMode.resolve("compact") == .compactText)
        #expect(MenuBarDisplayMode.resolve("") == .fullText)
        for mode in MenuBarDisplayMode.allCases { #expect(MenuBarDisplayMode.resolve(mode.rawValue) == mode) }
        #expect(MenuBarDisplayMode.fullText.hasText && !MenuBarDisplayMode.fullText.hasChart)
        #expect(!MenuBarDisplayMode.sparklineOnly.hasText && MenuBarDisplayMode.sparklineOnly.hasChart)
        #expect(MenuBarDisplayMode.chartAndText.hasText && MenuBarDisplayMode.chartAndText.hasChart)
    }
    @Test func sparklineBoundsGapsAndLastTwelveSamples() {
        let values = (0..<24).map { Optional(Double($0)) }
        let points = SparklineGeometry.points(values, maximum: 100)
        #expect(points.count == 12)
        #expect(points.first??.x == 0)
        #expect(points.first??.y == 0.88)
        #expect(points.last??.x == 1)
        let gaps = SparklineGeometry.points([nil, .nan, -1, .infinity, 200], maximum: 100)
        #expect(gaps.prefix(4).allSatisfy { $0 == nil })
        #expect(gaps.last??.y == 0)
        #expect(SparklineGeometry.points([]).isEmpty)
        #expect(SparklineGeometry.points([0]).first??.y == 1)
        #expect(SparklineGeometry.points([1, 10]).last??.y == 0)
    }
    @Test func nvmeUses128BitUnitsAndWearIsBounded() throws {
        var data = [UInt8](repeating: 0, count: 512)
        data[5] = 7; data[48] = 1
        let health = try #require(StorageHealthService.decode(bytes: data, nvme: true, condition: 0, model: "NVMe"))
        #expect(health.lifeRemaining == 93)
        #expect(health.status == .passed)
        #expect(health.terabytesWritten == 512_000.0 / 1_000_000_000_000)
        data[5] = 150; data[56] = 1
        let old = try #require(StorageHealthService.decode(bytes: data, nvme: true, condition: 1, model: "NVMe"))
        #expect(old.lifeRemaining == 0)
        #expect(old.status == .warning)
        #expect(try #require(old.terabytesWritten) > 1_000_000_000)
    }
    @Test func samsungSpecificAttributesNeverAppliedToUnknownATA() throws {
        var data = [UInt8](repeating: 0, count: 512)
        data[2] = 177; data[5] = 87
        data[14] = 241; data[19] = 2
        let samsung = try #require(StorageHealthService.decode(bytes: data, nvme: false, condition: 0, model: "Samsung SSD 860 EVO 1TB"))
        #expect(samsung.lifeRemaining == 87)
        #expect(samsung.terabytesWritten == 1024.0 / 1_000_000_000_000)
        let other = try #require(StorageHealthService.decode(bytes: data, nvme: false, condition: 0, model: "Another vendor"))
        #expect(other.lifeRemaining == nil && other.terabytesWritten == nil)
        #expect(StorageHealthService.decode(bytes: [], nvme: true, condition: -1, model: "USB") == nil)
        let truncated = try #require(StorageHealthService.decode(bytes: [1], nvme: true, condition: 1, model: "NVMe"))
        #expect(truncated.lifeRemaining == nil && truncated.status == .warning)
    }
}
