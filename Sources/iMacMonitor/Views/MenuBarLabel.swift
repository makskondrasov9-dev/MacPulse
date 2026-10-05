import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: MonitorModel
    @AppStorage("showMenuBarIcon") private var showIcon = true
    @AppStorage("showCPUPercentage") private var showCPU = true
    @AppStorage("showRAMPercentage") private var showRAM = false
    @AppStorage("showGPUPercentage") private var showGPU = false
    @AppStorage("showCPUTemperature") private var showTemperature = false
    @AppStorage("menuBarGPUUsesVRAM") private var gpuUsesVRAM = false

    private var components: [String] {
        var values: [String] = []
        let snapshot = model.snapshot
        if showCPU { values.append("CPU \(MetricFormat.percent(snapshot?.cpu?.usage))") }
        if showRAM {
            let percentage = snapshot?.memory.flatMap { MetricFormat.ratio($0.used, $0.total) }
            values.append("RAM \(MetricFormat.percent(percentage))")
        }
        if showGPU {
            if gpuUsesVRAM {
                let percentage = snapshot.flatMap { snapshot in
                    snapshot.gpu.usedVRAM.flatMap { used in snapshot.gpu.totalVRAM.flatMap { MetricFormat.ratio(used, $0) } }
                }
                values.append("VRAM \(MetricFormat.percent(percentage))")
            } else { values.append("GPU \(MetricFormat.percent(snapshot?.gpu.utilization))") }
        }
        if showTemperature { values.append("CPU \(MetricFormat.temperature(snapshot?.cpuTemperature))") }
        return values
    }

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        HStack(spacing: 5) {
            if showIcon || components.isEmpty { Image(systemName: "desktopcomputer").accessibilityLabel("MacPulse") }
            if !components.isEmpty { Text(components.joined(separator: " | ")).monospacedDigit() }
        }
        .accessibilityLabel("MacPulse. " + components.joined(separator: ", "))
    }
}
