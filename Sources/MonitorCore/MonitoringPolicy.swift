import Foundation

public struct MetricSelection: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let cpu = Self(rawValue: 1 << 0)
    public static let memory = Self(rawValue: 1 << 1)
    public static let gpu = Self(rawValue: 1 << 2)
    public static let temperature = Self(rawValue: 1 << 3)
    public static let network = Self(rawValue: 1 << 4)
    public static let processes = Self(rawValue: 1 << 5)
    public static let storage = Self(rawValue: 1 << 6)
    public static let battery = Self(rawValue: 1 << 7)
    public static let cpuDetails = Self(rawValue: 1 << 8)
    public static let all: Self = [.cpu, .memory, .gpu, .temperature, .network, .processes, .storage, .battery, .cpuDetails]
}

public enum PresentationPolicy {
    public static func widgetSize(_ name: String) -> (width: Double, height: Double) {
        switch name {
        case "small": (160, 160)
        case "large": (340, 340)
        default: (340, 160)
        }
    }
    public static func loadBand(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return value < 50 ? 0 : value <= 80 ? 1 : 2
    }
}
