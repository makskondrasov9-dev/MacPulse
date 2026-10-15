import Foundation

public enum DesktopWidgetKind: String, CaseIterable, Sendable, Identifiable {
    case compute, memory, network, summary
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .compute: "CPU & GPU"
        case .memory: "RAM / Storage"
        case .network: "Сеть"
        case .summary: "System summary"
        }
    }
    public var supportsSmall: Bool { self != .summary }
    public func normalizedSize(_ size: String) -> String {
        if size == "large" { return "large" }
        return size == "small" && supportsSmall ? "small" : "medium"
    }
    public var metrics: MetricSelection {
        switch self {
        case .compute: [.cpu, .gpu, .temperature]
        case .memory: [.memory, .storage]
        case .network: [.network]
        case .summary: [.cpu, .gpu, .memory, .storage, .network]
        }
    }
}

public enum DesktopWidgetPolicy {
    /// Missing per-widget choices preserve the original three-widget configuration.
    public static func enabled(master: Bool, choices: [DesktopWidgetKind: Bool]) -> Set<DesktopWidgetKind> {
        guard master else { return [] }
        return Set(DesktopWidgetKind.allCases.filter { choices[$0] ?? ($0 != .summary) })
    }
}

public enum MenuChartPalette: Equatable, Sendable { case primary, accent, cyan, green, orange, red }
public enum MenuChartPolicy {
    public static func color(mode: String, network: Bool, load: Double?) -> MenuChartPalette {
        switch mode {
        case "accent": .accent
        case "category": network ? .green : .cyan
        case "load": PresentationPolicy.loadBand(load).map { [MenuChartPalette.green, .orange, .red][$0] } ?? .primary
        default: .primary
        }
    }
    /// Relative to the recent traffic peak, with a 1 MiB/s floor to avoid idle noise appearing red.
    public static func networkIntensity(_ values: [Double?]) -> Double? {
        guard let current = values.last ?? nil, current.isFinite, current >= 0 else { return nil }
        let peak = max(1_048_576, values.suffix(12).compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }.max() ?? 0)
        return min(100, current / peak * 100)
    }
}
