import Charts
import MonitorCore
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel
    @AppStorage("showNetworkDetails") private var showNetworkDetails = false
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    @State private var showLog = true
    @State private var seconds = 15
    @State private var workers = CPUCapabilities.maximumWorkers
    @State private var traceHost = "1.1.1.1"
    @State private var pending: DiagnosticsModel.Test?
    @State private var confirm = false
    @Environment(\.locale) private var locale
    var body: some View {
        let _ = locale
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let message = model.message { Text(L10n.text(message)).textSelection(.enabled) }
                diskSection
                stressSection
                displaySection
                networkSection
                NetworkLabView(model: model, host: $traceHost, start: ask)
                identitySection
                logSection
            }.frame(maxWidth: 900, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            if let running = model.running {
                HStack(spacing: 16) {
                    Text(L10n.text(running.rawValue)).font(.headline)
                    if running == .cpu || running == .gpu || running == .disk { ProgressView(value: model.progress).frame(maxWidth: 240) }
                    else if running == .network { Text(model.transfers.last?.download.map { String(format: "↓ %.1f Mbps", $0) } ?? L("Running…")).monospacedDigit() }
                    else { Text(L("Running…")) }
                    Spacer(minLength: 0)
                    Button(L("Stop test")) { model.cancel() }.keyboardShortcut(.cancelAction)
                }.padding().background(.regularMaterial)
            }
        }
        .alert(L("Start test?"), isPresented: $confirm) {
            Button(L("Отмена"), role: .cancel) { pending = nil }
            Button(L("Start test")) { if let pending { model.start(pending, seconds: seconds, workers: workers, host: traceHost) }; pending = nil }
        } message: { Text(L("Save your work. Tests use disk, CPU/GPU or network resources. You can cancel at any time.")) }
    }
    private var diskSection: some View {
        GroupBox(L("Disk benchmark")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Writes and reads a temporary 1 GB file on the temporary-folder volume. OS cache bypassed; controller caches may affect results."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    speed(L("Write"), value: model.disk?.writeMBps)
                    speed(L("Read"), value: model.disk?.readMBps)
                }.frame(maxWidth: .infinity)
                Button(L("Start test")) { ask(.disk) }.disabled(model.running != nil)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stressSection: some View {
        GroupBox(L("CPU stress test")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L("Duration"), selection: $seconds) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 300).disabled(model.running != nil)
                Picker(L("Worker threads"), selection: $workers) {
                    ForEach(1...CPUCapabilities.maximumWorkers, id: \.self) { count in
                        Text(count == CPUCapabilities.maximumWorkers ? L("All threads") : String(count)).tag(count)
                    }
                }.disabled(model.running != nil)
                Text(L("macOS schedules threads across cores. Critical thermal pressure stops the test automatically."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("CPU stress test")) { ask(.cpu) }
                    Button(L("GPU Metal test")) { ask(.gpu) }
                }.disabled(model.running != nil)
                CPUTelemetryView(model: model)
                if let rate = model.workRate { Text(L("Batches per second") + ": " + String(format: "%.1f", locale: L10n.locale, rate)) }
                if !model.thermal.isEmpty {
                    Text(L("Термосостояние") + ": " + L10n.text(model.thermalState))
                    if !hideUnavailable || model.thermal.contains(where: { $0.temperature != nil || $0.gpuTemperature != nil }) {
                    Chart(model.thermal) { point in
                        if let value = point.temperature {
                            LineMark(x: .value("Time", point.date), y: .value("°C", value))
                                .foregroundStyle(by: .value("Device", "CPU"))
                        }
                        if let value = point.gpuTemperature {
                            LineMark(x: .value("Time", point.date), y: .value("°C", value))
                                .foregroundStyle(by: .value("Device", "GPU"))
                        }
                    }.frame(height: 150)
                    }
                    Text(model.sawThermalPressure ? L("Thermal or CPU power limit detected") : L("No thermal limit detected in sampled readings"))
                    if let limit = model.thermal.compactMap(\.speedLimit).min() { Text(L("CPU speed limit") + ": " + MetricFormat.percent(limit)) }
                    Text(L("Power limits and thermal state are indicators, not a measured clock frequency. Unavailable temperatures stay blank."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displaySection: some View {
        GroupBox(L("Display test")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Click or Space: red, green, blue, white, black. Escape: exit. Opens on the current screen."))
                Button(L("Display test")) { DisplayTestController.shared.show(instructions: L("Click or Space — next color • ESC — exit")) }.disabled(model.running != nil)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var networkSection: some View {
        GroupBox(L("Network speed test")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Uses Apple's networkQuality servers and can transfer substantial data. RPM is responsiveness, not ping."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Start test")) { ask(.network) }.disabled(model.running != nil)
                NetworkTransferView(model: model)
                if let result = model.network {
                    if result.downloadMbps != nil || !hideUnavailable { LabeledContent(L("Загрузка"), value: rate(result.downloadMbps, suffix: "Mbps")) }
                    if result.uploadMbps != nil || !hideUnavailable { LabeledContent(L("Отправка"), value: rate(result.uploadMbps, suffix: "Mbps")) }
                    if result.latencyMilliseconds != nil || !hideUnavailable { LabeledContent(L("Idle latency"), value: rate(result.latencyMilliseconds, suffix: "ms")) }
                    if result.responsiveness != nil || !hideUnavailable { LabeledContent("RPM", value: rate(result.responsiveness, suffix: "")) }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var identitySection: some View {
        GroupBox(L("Network identity")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L("Show technical network details"), isOn: $showNetworkDetails)
                Toggle(L("Hide unavailable values"), isOn: $hideUnavailable)
                ForEach(NetworkPresentation(model.interfaces).visibleInterfaces(details: showNetworkDetails), id: \.interface) { interface in
                    VStack(alignment: .leading) {
                        Text([interface.label, interface.interface].compactMap { $0 }.joined(separator: " · ")).bold()
                        Text(interface.addresses.joined(separator: " · ")).textSelection(.enabled)
                        if interface.mac != nil || !hideUnavailable { Text("MAC: \(interface.mac ?? "—")").font(.caption).textSelection(.enabled) }
                    }
                }
                Toggle(L("Public IP history"), isOn: $model.publicIPEnabled)
                Text(L("The configured service receives your public IP. History stays on this Mac (up to 200 changes). Configure the URL and interval in Settings."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.publicIP != nil || !hideUnavailable { LabeledContent(L("Public IP"), value: model.publicIP ?? "—").textSelection(.enabled) }
                HStack {
                    Button(L("Обновить")) { model.refreshIdentity(forcePublic: true) }.disabled(model.ipBusy)
                    if model.ipBusy { ProgressView().controlSize(.small) }
                }
                if let error = model.ipError { Text(error).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup(L("IP history")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.history.entries.reversed()) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.date.formatted(date: .abbreviated, time: .standard)).font(.caption)
                                if let ip = entry.publicIP { Text(ip) }
                                Text(entry.interfaces.map { "\($0.label ?? $0.interface) (\($0.interface)): \($0.addresses.joined(separator: ", "))" }.joined(separator: " · ")).font(.caption)
                            }.textSelection(.enabled)
                            Divider()
                        }
                    }
                }
                Button(L("Clear history")) { model.clearHistory() }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logSection: some View {
        DisclosureGroup(L("Test log"), isExpanded: $showLog) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in Text(line).font(.caption.monospaced()).textSelection(.enabled).id(index) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 160)
            .onChange(of: model.log.last) { _ in proxy.scrollTo(model.log.count - 1, anchor: .bottom) }
            }
        }
    }
    private func ask(_ test: DiagnosticsModel.Test) { pending = test; confirm = true }
    private func rate(_ value: Double?, suffix: String) -> String {
        value.map { String(format: "%.1f", locale: L10n.locale, $0) + " " + suffix } ?? "—"
    }
    private func speed(_ title: String, value: Double?) -> some View {
        VStack {
            Gauge(value: value ?? 0, in: 0...max(1000, value ?? 0)) { Text(title) } currentValueLabel: {
                Text(value.map { String(format: "%.0f", $0) } ?? "—").font(.caption)
            }.gaugeStyle(.accessoryCircular).tint(.blue)
            Text(title + " · " + rate(value, suffix: "MB/s")).font(.caption).monospacedDigit()
        }
    }
}
