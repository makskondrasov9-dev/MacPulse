import SwiftUI
import AppKit
import MonitorCore

struct MenuBarLabel: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject private var diagnostics: DiagnosticsModel
    init(model: MonitorModel) { self.model = model; self.diagnostics = model.diagnostics }
    @AppStorage("showMenuBarIP") private var showIP = false
    @AppStorage("showMenuBarVPN") private var showVPN = false
    @AppStorage("menuBarIPSource") private var ipSource = "local"
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    @AppStorage("showMenuBarIcon") private var showIcon = true
    @AppStorage("showCPUPercentage") private var showCPU = true
    @AppStorage("showRAMPercentage") private var showRAM = false
    @AppStorage("showGPUPercentage") private var showGPU = false
    @AppStorage("showCPUTemperature") private var showTemperature = false
    @AppStorage("menuBarGPUUsesVRAM") private var gpuUsesVRAM = false

    @AppStorage("menuBarTextStyle") private var style = "full"
    @AppStorage("showNetworkSpeed") private var showNetwork = false
    @AppStorage("showCPUChart") private var showCPUChart = true
    @AppStorage("showNetworkChart") private var showNetworkChart = false
    private var mode: MenuBarDisplayMode { .resolve(style) }
    private var compact: Bool { mode == .compactText || mode == .chartAndText }
    private var hasChart: Bool { mode.hasChart && (showCPUChart || showNetworkChart) }

    private var identityComponents: [String] {
        let network = NetworkPresentation(diagnostics.interfaces)
        var result: [String] = []
        if showIP {
            if let ip = network.menuIP(source: ipSource, publicIP: diagnostics.publicIP) { result.append("IP " + ip) }
            else if !hideUnavailable { result.append("IP —") }
        }
        if showVPN { result.append(network.hasTunnel ? "VPN ◉" : "VPN ○") }
        return result
    }
    private struct Segment {
        let text: String
        let category: Int
        let value: Double?
    }
    @AppStorage("menuBarColorMode") private var colorMode = "mono"
    @AppStorage("accentColor") private var accent = AppAccent.blue.rawValue
    private var segments: [Segment] {
        var values: [Segment] = []
        let snapshot = model.snapshot
        func append(_ label: String, _ value: Double?, temperature: Bool = false) {
            guard value != nil || !hideUnavailable else { return }
            let category = temperature ? 3 : (["CPU", "C"].contains(label) ? 0 : ["RAM", "M"].contains(label) ? 1 : 2)
            values.append(Segment(text: label + " " + (temperature ? MetricFormat.temperature(value) : MetricFormat.percent(value)), category: category, value: value))
        }
        if showCPU { append(compact ? "C" : "CPU", snapshot?.cpu?.usage) }
        if showRAM { append(compact ? "M" : "RAM", snapshot?.memory.flatMap { MetricFormat.ratio($0.used, $0.total) }) }
        if showGPU {
            if gpuUsesVRAM {
                let percentage = snapshot.flatMap { snapshot in
                    snapshot.gpu.usedVRAM.flatMap { used in snapshot.gpu.totalVRAM.flatMap { MetricFormat.ratio(used, $0) } }
                }
                append(compact ? "V" : "VRAM", percentage)
            } else { append(compact ? "G" : "GPU", snapshot?.gpu.utilization) }
        }
        if showTemperature { append(compact ? "T" : "CPU", snapshot?.cpuTemperature, temperature: true) }
        if showNetwork, !hideUnavailable || (snapshot?.network.downloadBytesPerSecond != nil && snapshot?.network.uploadBytesPerSecond != nil) {
            values.append(Segment(text: "↓\(ByteSizeFormat.rate(snapshot?.network.downloadBytesPerSecond)) ↑\(ByteSizeFormat.rate(snapshot?.network.uploadBytesPerSecond))", category: 4, value: nil))
        }
        return values + identityComponents.map { Segment(text: $0, category: 4, value: nil) }
    }
    private var displayedSegments: [Segment] { mode.hasText ? segments : identityComponents.map { Segment(text: $0, category: 4, value: nil) } }
    private var displayedComponents: [String] { displayedSegments.map(\.text) }
    private var attributedLabel: AttributedString {
        var result = AttributedString()
        for (index, segment) in displayedSegments.enumerated() {
            if index > 0 { result += AttributedString(compact ? " · " : " | ") }
            var text = AttributedString(segment.text)
            switch colorMode {
            case "category": text.foregroundColor = [Color.cyan, .purple, .orange, .yellow, .green][segment.category]
            case "load":
                if let band = PresentationPolicy.loadBand(segment.value) { text.foregroundColor = [Color.green, .orange, .red][band] }
            case "accent": text.foregroundColor = (AppAccent(rawValue: accent) ?? .blue).color
            default: break
            }
            result += text
        }
        return result
    }

    private func chartColor(network: Bool) -> Color {
        let load = network ? MenuChartPolicy.networkIntensity(model.history.suffix(12).map(\.network)) : model.snapshot?.cpu?.usage
        return MenuChartPolicy.color(mode: colorMode, network: network, load: load)
            .viewColor(accent: (AppAccent(rawValue: accent) ?? .blue).color)
    }

    @Environment(\.locale) private var presentationLocale

    private var cpuReadings: [Double?]? {
        guard hasChart && showCPUChart else { return nil }
        return model.history.suffix(12).map { $0.cpu.map { $0.rounded() } }
    }
    private var networkReadings: [Double?]? {
        guard hasChart && showNetworkChart else { return nil }
        return model.history.suffix(12).map { $0.network }
    }
    private var spokenLabel: String {
        var parts = ["MacPulse"]
        if hasChart && showCPUChart { parts.append(L("График CPU")) }
        if hasChart && showNetworkChart { parts.append(L("График сети")) }
        parts += displayedComponents
        return parts.joined(separator: ", ")
    }
    var body: some View {
        let _ = presentationLocale
        labelContent.fixedSize().accessibilityLabel(spokenLabel)
            .help(showVPN ? L("VPN detection is based on tunnel interfaces with an assigned IP; it does not guarantee traffic protection.") : "MacPulse")
    }
    @ViewBuilder private var labelContent: some View {
        if hasChart || colorMode != "mono" {
            CachedStatusLabel(label: attributedLabel, cpu: cpuReadings, network: networkReadings,
                icon: showIcon || (!hasChart && displayedComponents.isEmpty), cpuColor: chartColor(network: false), networkColor: chartColor(network: true))
        } else {
            HStack(spacing: 6) {
                if showIcon || displayedComponents.isEmpty { Image(systemName: "desktopcomputer") }
                Text(attributedLabel).monospacedDigit().fixedSize().layoutPriority(1)
            }.fixedSize()
        }
    }

}

/// A single original image prevents MenuBarExtra from dropping sibling text/images.
/// The native monochrome text path stays allocation-free between changed readings.
struct StatusLabelComposition: View {
    let label: AttributedString
    let cpu: [Double?]?
    let network: [Double?]?
    let icon: Bool
    let cpuColor: Color
    var networkColor: Color = .green
    var body: some View {
        HStack(spacing: 6) {
            if icon { Image(systemName: "desktopcomputer").font(.system(size: 14)) }
            if let cpu { SparklineView(readings: cpu, maximum: 100, color: cpuColor) }
            if let network { SparklineView(readings: network, color: networkColor) }
            if !label.characters.isEmpty {
                Text(label).monospacedDigit().fixedSize().layoutPriority(1)
            }
        }.font(.system(size: NSFont.systemFontSize)).fixedSize()
    }
    @MainActor func image(scheme: ColorScheme) -> NSImage? {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, scheme))
        renderer.scale = 2
        let result = renderer.nsImage
        result?.isTemplate = false
        return result
    }
}

private struct CachedStatusLabel: View {
    let label: AttributedString
    let cpu: [Double?]?
    let network: [Double?]?
    let icon: Bool
    let cpuColor: Color
    var networkColor: Color = .green
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?
    private struct Key: Equatable {
        let label: AttributedString
        let cpu: [Double?]?
        let network: [Double?]?
        let icon: Bool
        let color: Color
        let networkColor: Color
        let scheme: ColorScheme
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).renderingMode(.original) }
            else { composition }
        }.fixedSize()
        .onInitialChange(of: Key(label: label, cpu: cpu, network: network, icon: icon, color: cpuColor, networkColor: networkColor, scheme: scheme)) { _ in
            image = composition.image(scheme: scheme)
        }
    }
    private var composition: StatusLabelComposition {
        StatusLabelComposition(label: label, cpu: cpu, network: network, icon: icon, cpuColor: cpuColor, networkColor: networkColor)
    }
}

extension MenuChartPalette {
    func viewColor(accent: Color) -> Color {
        switch self {
        case .primary: .primary
        case .accent: accent
        case .cyan: .cyan
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }
}
