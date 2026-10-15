import AppKit
import MonitorCore
import SwiftUI

/// Four independent, themed panels. All plots share the bounded three-second history buckets.
struct DesktopHUD: View {
    @ObservedObject var model: MonitorModel
    let kind: DesktopWidgetKind
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("accentColor") private var accent = AppAccent.blue.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @State private var size = "medium"
    private static let nominalGHz = CPUCapabilities.nominalGHz
    private var color: Color { (AppAccent(rawValue: accent) ?? .blue).color }
    private var snapshot: MonitorSnapshot? { model.snapshot }
    private var dimensions: (width: Double, height: Double) { PresentationPolicy.widgetSize(size) }
    private var history: [HistoryPoint] { size == "large" ? model.widgetHistory : Array(model.widgetHistory.suffix(12)) }

    var body: some View {
        content.font(.callout.monospacedDigit())
            .padding(16).frame(width: dimensions.width, height: dimensions.height)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .tint(color)
            .environment(\.locale, Locale(identifier: AppLanguage.resolve(language).rawValue))
            .environment(\.layoutDirection, AppLanguage.resolve(language) == .ar ? .rightToLeft : .leftToRight)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onAppear { size = WidgetPreferences.size(kind) }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in size = WidgetPreferences.size(kind) }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .compute: compute
        case .memory: memory
        case .network: NetworkDesktopHUD(model: model, size: size, color: color)
        case .summary: summary
        }
    }
    private var cpuUsage: Double? { snapshot?.cpu?.usage }
    private var gpuUsage: Double? { snapshot?.gpu.utilization }
    private var ramUsage: Double? { snapshot?.memory.flatMap { MetricFormat.ratio($0.used, $0.total) } }
    private var diskUsage: Double? { snapshot?.storage.flatMap { MetricFormat.ratio($0.used, $0.total) } }

    @ViewBuilder private var compute: some View {
        if size == "small" {
            VStack(spacing: 12) {
                ringRow("CPU", value: cpuUsage)
                ringRow("GPU", value: gpuUsage)
            }
        } else {
            VStack(alignment: .leading, spacing: size == "large" ? 10 : 4) {
                reading("CPU", MetricFormat.percent(cpuUsage))
                plot(history.map(\.cpu), maximum: 100, height: size == "large" ? 56 : 22)
                reading("GPU", MetricFormat.percent(gpuUsage))
                plot(history.map(\.gpu), maximum: 100, height: size == "large" ? 56 : 22)
                if size == "large" {
                    Text(L("History · 60 seconds")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("CPU " + MetricFormat.temperature(snapshot?.cpuTemperature))
                        Spacer()
                        Text("GPU " + MetricFormat.temperature(snapshot?.gpu.temperature ?? snapshot?.gpuTemperature))
                    }.font(.caption)
                    if let frequency = Self.nominalGHz {
                        reading(L("Nominal frequency"), String(format: "%.2f GHz", locale: L10n.locale, frequency))
                    } else { reading(L("Nominal frequency"), "—") }
                    reading(L("Thermal throttling"), throttling)
                }
            }
        }
    }
    private var throttling: String {
        let state = snapshot?.thermalState
        if let limit = snapshot?.cpuSpeedLimit {
            let pressure = ProcessInfo.processInfo.thermalState
            return limit < 100 || pressure == .serious || pressure == .critical
                ? L("Detected") + " · " + MetricFormat.percent(limit) : L("No thermal throttling")
        }
        return "— · " + L10n.text(state ?? "—")
    }
    @ViewBuilder private var memory: some View {
        if size == "small" {
            VStack(spacing: 12) {
                ringRow("RAM", value: ramUsage, detail: snapshot?.memory.map { shortAmount($0.used, $0.total) })
                ringRow("SSD", value: diskUsage, detail: snapshot?.storage.map { shortAmount($0.used, $0.total) })
            }
        } else {
            VStack(alignment: .leading, spacing: size == "large" ? 12 : 10) {
                if let ram = snapshot?.memory {
                    amount("RAM", used: ram.used, total: ram.total)
                    if size == "large" {
                        memoryPart(L("Active"), ram.active, total: ram.total)
                        memoryPart(L("Wired"), ram.wired, total: ram.total)
                        memoryPart(L("Compressed"), ram.compressed, total: ram.total)
                        memoryPart(L("Free / Inactive"), ram.freeAndInactive, total: ram.total)
                    }
                } else { reading("RAM", "—") }
                if let disk = snapshot?.storage { amount("SSD", used: disk.used, total: disk.total) }
                else { reading("SSD", "—") }
                if size == "large" {
                    if let health = snapshot?.storageHealth { StorageHealthBadge(health: health) }
                    else { Text(L("SMART unavailable")).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: size == "large" ? 12 : 8) {
            Text(L("System summary")).font(.headline)
            HStack { reading("CPU", MetricFormat.percent(cpuUsage)); Divider().frame(height: 18); reading("GPU", MetricFormat.percent(gpuUsage)) }
            if size == "large" {
                plot(history.map(\.cpu), maximum: 100, height: 40)
                plot(history.map(\.gpu), maximum: 100, height: 40)
            }
            HStack { reading("RAM", MetricFormat.percent(ramUsage)); Divider().frame(height: 18); reading("SSD", MetricFormat.percent(diskUsage)) }
            reading("↓", ByteSizeFormat.rate(snapshot?.network.downloadBytesPerSecond))
            reading("↑", ByteSizeFormat.rate(snapshot?.network.uploadBytesPerSecond))
        }
    }
    private func amount(_ title: String, used: UInt64, total: UInt64) -> some View {
        VStack(spacing: 4) {
            reading(title, MetricFormat.ltr(MetricFormat.gb(used) + " / " + MetricFormat.gb(total) + " GB"))
            ProgressView(value: MetricFormat.ratio(used, total).map { $0 / 100 } ?? 0)
        }
    }
    private func memoryPart(_ title: String, _ bytes: UInt64, total: UInt64) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 100, alignment: .leading).lineLimit(2)
            ProgressView(value: MetricFormat.ratio(bytes, total).map { $0 / 100 } ?? 0)
            Text(memorySize(bytes)).font(.caption).fixedSize()
        }
    }
    private func reading(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) { Text(title); Spacer(minLength: 2); Text(value).lineLimit(1).minimumScaleFactor(0.7) }
    }
    private func memorySize(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return MetricFormat.ltr(MetricFormat.gb(bytes) + " GB") }
        return Int64(bytes).formatted(.byteCount(style: .memory, allowedUnits: [.bytes, .kb, .mb], spellsOutZero: false).locale(L10n.locale))
    }
    private func shortAmount(_ used: UInt64, _ total: UInt64) -> String {
        MetricFormat.ltr(MetricFormat.gb(used) + "/" + MetricFormat.gb(total) + " GB")
    }
    private func ringRow(_ title: String, value: Double?, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption)
                Text(MetricFormat.percent(value)).font(.headline)
                if let detail { Text(detail).font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.7) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func plot(_ values: [Double?], maximum: Double?, height: Double) -> some View {
        WidgetHistoryPlot(points: history, values: values, maximum: maximum, seconds: size == "large" ? 60 : nil, color: color).frame(height: height)
    }
}

private struct NetworkDesktopHUD: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject private var diagnostics: DiagnosticsModel
    let size: String
    let color: Color
    init(model: MonitorModel, size: String, color: Color) {
        self.model = model; self.diagnostics = model.diagnostics; self.size = size; self.color = color
    }
    private var points: [HistoryPoint] { size == "large" ? model.widgetHistory : Array(model.widgetHistory.suffix(12)) }
    var body: some View {
        VStack(alignment: .leading, spacing: size == "large" ? 8 : 6) {
            Text(L("Сеть")).font(.headline)
            if size == "small" {
                GeometryReader { geometry in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 3)
                    let radius = min(geometry.size.width / 2 - 3, geometry.size.height - 6)
                    ZStack {
                        Path { $0.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false) }
                            .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        Path { $0.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + intensity * 1.8), clockwise: false) }
                            .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    }
                }.frame(height: 38).accessibilityHidden(true)
            }
            Text("↓ " + ByteSizeFormat.rate(model.snapshot?.network.downloadBytesPerSecond))
            if size == "large" { plot(points.map(\.download)) }
            Text("↑ " + ByteSizeFormat.rate(model.snapshot?.network.uploadBytesPerSecond))
            if size == "large" { plot(points.map(\.upload)) }
            if size == "medium" { plot(points.map(\.network)) }
            if size == "large" {
                Divider()
                ip(L("Local IP"), NetworkPresentation(diagnostics.interfaces).localIP)
                ip(L("Public IP"), diagnostics.publicIP)
                Text(L("Session traffic")).font(.caption).foregroundStyle(.secondary)
                Text("↓ " + ByteSizeFormat.string(model.snapshot?.network.receivedBytes ?? 0) + "  ↑ " + ByteSizeFormat.string(model.snapshot?.network.sentBytes ?? 0)).font(.caption)
            }
        }
    }
    private var intensity: Double { MenuChartPolicy.networkIntensity(points.map(\.network)) ?? 0 }
    private func ip(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.ltr(value ?? "—")).font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
    private func plot(_ values: [Double?]) -> some View {
        WidgetHistoryPlot(points: points, values: values, maximum: nil, seconds: size == "large" ? 60 : nil, color: color)
            .frame(height: size == "large" ? 42 : 28)
    }
}

struct WidgetHistoryPlot: View {
    let points: [HistoryPoint]
    let values: [Double?]
    let maximum: Double?
    let seconds: Double?
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let pairs = Array(zip(points, values)).suffix(20)
                let peak = maximum ?? max(1, values.compactMap { $0 }.filter { $0.isFinite }.max() ?? 1)
                let end = points.last?.date.timeIntervalSince1970 ?? 0
                var connected = false
                for (index, pair) in pairs.enumerated() {
                    guard let value = pair.1, value.isFinite, value >= 0 else { connected = false; continue }
                    let x = seconds.map { max(0, 1 - (end - pair.0.date.timeIntervalSince1970) / $0) } ?? Double(index) / Double(max(1, pairs.count - 1))
                    let point = CGPoint(x: x * geometry.size.width, y: (1 - min(1, value / peak)) * geometry.size.height)
                    if connected { path.addLine(to: point) } else { path.move(to: point); path.addLine(to: point) }
                    connected = true
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }.allowsHitTesting(false).environment(\.layoutDirection, .leftToRight)
    }
}
