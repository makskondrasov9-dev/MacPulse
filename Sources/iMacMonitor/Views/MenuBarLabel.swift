import SwiftUI
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
    private var components: [String] {
        var values: [String] = []
        let snapshot = model.snapshot
        func append(_ label: String, _ value: Double?, temperature: Bool = false) {
            guard value != nil || !hideUnavailable else { return }
            values.append(label + " " + (temperature ? MetricFormat.temperature(value) : MetricFormat.percent(value)))
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
            values.append("↓\(ByteSizeFormat.rate(snapshot?.network.downloadBytesPerSecond)) ↑\(ByteSizeFormat.rate(snapshot?.network.uploadBytesPerSecond))")
        }
        return values + identityComponents
    }
    private var displayedComponents: [String] { mode.hasText ? components : identityComponents }

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        HStack(spacing: 5) {
            if hasChart {
                Image(nsImage: SparklineView.image(cpu: showCPUChart ? model.history.map(\.cpu) : nil,
                    network: showNetworkChart ? model.history.map(\.network) : nil, showIcon: showIcon))
            } else if showIcon || displayedComponents.isEmpty {
                Image(systemName: "desktopcomputer").accessibilityLabel("MacPulse")
            }
            if !displayedComponents.isEmpty { Text(displayedComponents.joined(separator: compact ? " · " : " | ")).monospacedDigit() }
        }
        .accessibilityLabel("MacPulse. " + (hasChart ? [showCPUChart ? L("График CPU") : "", showNetworkChart ? L("График сети") : ""].filter { !$0.isEmpty }.joined(separator: ", ") + ". " : "") + displayedComponents.joined(separator: ", "))
        .help(showVPN ? L("VPN detection is based on tunnel interfaces with an assigned IP; it does not guarantee traffic protection.") : "MacPulse")
    }
}
