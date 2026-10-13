import MonitorCore
import SwiftUI

struct InsightsView: View {
    @ObservedObject var model: InsightsModel
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    @Environment(\.locale) private var locale
    var body: some View {
        let _ = locale
        GroupBox(L("Session peaks")) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { peaks }
                    VStack(alignment: .leading, spacing: 8) { peaks }
                }
                DisclosureGroup(L("Application usage today")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L("Track foreground application time"), isOn: $model.tracksUsage)
                        Text(L("Local, approximate active time; idle periods over 60 seconds and sleep are excluded. Window titles are never stored."))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.usage.top) { entry in
                            HStack { Text(entry.name); Spacer(); Text(time(entry.seconds)) }
                        }
                        Button(L("Clear history")) { model.clearUsage() }
                    }
                }
                DisclosureGroup(L("Top CPU consumers this session")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Estimated CPU seconds from sampled processes, not an energy measurement."))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.audit.top) { entry in HStack { Text(entry.name); Spacer(); Text(time(entry.seconds)) } }
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var peaks: some View {
        if model.peaks.cpuTemperature != nil || !hideUnavailable { Text("CPU: " + MetricFormat.temperature(model.peaks.cpuTemperature)) }
        Text("RAM: " + ByteSizeFormat.string(model.peaks.memoryBytes))
        if model.peaks.gpuLoad != nil || !hideUnavailable { Text("GPU: " + MetricFormat.percent(model.peaks.gpuLoad)) }
    }
    private func time(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter(); formatter.allowedUnits = [.hour, .minute, .second]; formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "—"
    }
}
