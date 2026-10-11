import Foundation

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case fullText, compactText, sparklineOnly, chartAndText
    public var id: String { rawValue }
    public var hasChart: Bool { self == .sparklineOnly || self == .chartAndText }
    public var hasText: Bool { self != .sparklineOnly }
    public var title: String {
        switch self {
        case .fullText: L("Классический текст")
        case .compactText: L("Компактный текст")
        case .sparklineOnly: L("Микро-график")
        case .chartAndText: L("График + Текст")
        }
    }
    /// Existing 0.7 preferences remain valid; missing/unknown values keep classic text.
    public static func resolve(_ value: String) -> Self {
        if value == "compact" { return .compactText }
        return Self(rawValue: value) ?? .fullText
    }
}

public enum SparklineGeometry {
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }
    /// Exactly the last 12 ticks; unknown readings break the path rather than inventing zeroes.
    public static func points(_ readings: [Double?], maximum: Double? = nil) -> [Point?] {
        let values = Array(readings.suffix(12))
        let ceiling = maximum.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? max(1, values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }.max() ?? 1)
        return values.enumerated().map { index, value in
            guard let value, value.isFinite, value >= 0 else { return nil }
            return Point(x: Double(index + 12 - values.count) / 11,
                         y: 1 - min(value / ceiling, 1))
        }
    }
}
