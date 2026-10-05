import MonitorCore
import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 14) {
            Text("MacPulse").font(.headline)
            LabeledContent("CPU", value: MetricFormat.percent(model.snapshot?.cpu?.usage))
            ProgressView(value: (model.snapshot?.cpu?.usage ?? 0) / 100)
                .accessibilityLabel(L("Загрузка CPU"))
            LabeledContent("GPU", value: MetricFormat.percent(model.snapshot?.gpu.utilization))
            LabeledContent(L("Температура CPU"), value: MetricFormat.temperature(model.snapshot?.cpuTemperature))
            if let memory = model.snapshot?.memory {
                MetricGauge(title: "RAM", used: memory.used, total: memory.total)
            } else { LabeledContent("RAM", value: "—") }
            if let gpu = model.snapshot?.gpu, let used = gpu.usedVRAM, let total = gpu.totalVRAM {
                MetricGauge(title: L("VRAM In-Use"), used: used, total: total)
            } else { LabeledContent("VRAM", value: "—") }
            if let disk = model.snapshot?.storage {
                MetricGauge(title: L("Диск"), used: disk.used, total: disk.total)
            }
            Divider()
            Button(L("Открыть MacPulse")) {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(L("Завершить MacPulse")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .monospacedDigit()
        .padding(20)
        .frame(width: 380)
    }
}

struct MetricGauge: View {
    let title: String
    let used: UInt64
    let total: UInt64

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(title)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            MemoryAmountView(used: used, total: total)
            ProgressView(value: total > 0 ? min(Double(used) / Double(total), 1) : 0)
                .accessibilityLabel(title)
        }
    }
}


/// Separate text runs keep used / total in the same order even with Arabic numerals.
struct MemoryAmountView: View {
    let used: UInt64?
    let total: UInt64?
    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        HStack(spacing: 4) {
            Text(used.map(MetricFormat.gb) ?? "—")
            Text("/")
            Text(total.map(MetricFormat.gb) ?? "—")
            Text("GB")
        }
        .environment(\.layoutDirection, .leftToRight)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
