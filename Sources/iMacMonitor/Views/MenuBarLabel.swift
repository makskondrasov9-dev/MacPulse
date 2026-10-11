import SwiftUI
import MonitorCore

struct MenuBarLabel: View {
    @ObservedObject var model: MonitorModel
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

    private var components: [String] {
        var values: [String] = []
        let snapshot = model.snapshot
        if showCPU { values.append("\(compact ? "C" : "CPU") \(MetricFormat.percent(snapshot?.cpu?.usage))") }
        if showRAM {
            let percentage = snapshot?.memory.flatMap { MetricFormat.ratio($0.used, $0.total) }
            values.append("\(compact ? "M" : "RAM") \(MetricFormat.percent(percentage))")
        }
        if showGPU {
            if gpuUsesVRAM {
                let percentage = snapshot.flatMap { snapshot in
                    snapshot.gpu.usedVRAM.flatMap { used in snapshot.gpu.totalVRAM.flatMap { MetricFormat.ratio(used, $0) } }
                }
                values.append("\(compact ? "V" : "VRAM") \(MetricFormat.percent(percentage))")
            } else { values.append("\(compact ? "G" : "GPU") \(MetricFormat.percent(snapshot?.gpu.utilization))") }
        }
        if showTemperature { values.append("\(compact ? "T" : "CPU") \(MetricFormat.temperature(snapshot?.cpuTemperature))") }
        if showNetwork {
            values.append("↓\(ByteSizeFormat.rate(snapshot?.network.downloadBytesPerSecond)) ↑\(ByteSizeFormat.rate(snapshot?.network.uploadBytesPerSecond))")
        }
        return values
    }

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        HStack(spacing: 5) {
            if hasChart {
                Image(nsImage: SparklineView.image(cpu: showCPUChart ? model.history.map(\.cpu) : nil,
                    network: showNetworkChart ? model.history.map(\.network) : nil, showIcon: showIcon))
            } else if showIcon || !mode.hasText || components.isEmpty {
                Image(systemName: "desktopcomputer").accessibilityLabel("MacPulse")
            }
            if mode.hasText && !components.isEmpty { Text(components.joined(separator: compact ? " · " : " | ")).monospacedDigit() }
        }
        .accessibilityLabel("MacPulse. " + (hasChart ? [showCPUChart ? L("График CPU") : "", showNetworkChart ? L("График сети") : ""].filter { !$0.isEmpty }.joined(separator: ", ") + ". " : "") + components.joined(separator: ", "))
    }
}
