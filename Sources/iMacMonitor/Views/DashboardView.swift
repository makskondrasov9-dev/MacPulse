import Charts
import MonitorCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    @State private var rankByMemory = false
    @State private var selectedProcess: ProcessMetrics?
    @State private var selection: ProcessMetrics.ID?
    @State private var pendingProcess: ProcessMetrics?
    @State private var processMessage: String?
    @State private var confirmingProcess = false

    private var topProcesses: [ProcessMetrics] {
        Array((model.snapshot?.processes ?? []).sorted {
            let left = rankByMemory ? Double($0.residentBytes) : ($0.cpu ?? -1)
            let right = rankByMemory ? Double($1.residentBytes) : ($1.cpu ?? -1)
            return left == right ? $0.pid < $1.pid : left > right
        }.prefix(10))
    }

    @Environment(\.locale) private var presentationLocale

    var body: some View {
        let _ = presentationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("MacPulse").font(.largeTitle.bold())
                        Text(L("Обновление: \(model.pollingInterval, specifier: "%.1f") с")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(L("Uptime  \(MetricFormat.uptime(model.snapshot?.uptime))")).font(.callout.monospacedDigit())
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)], spacing: 16) {
                    card("CPU", icon: "cpu") {
                        Text(MetricFormat.percent(model.snapshot?.cpu?.usage)).font(.title.bold())
                        Text(L("\(ProcessInfo.processInfo.processorCount) logical cores · \(MetricFormat.temperature(model.snapshot?.cpuTemperature))"))
                        Text(model.snapshot?.hardware.processor ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.snapshot?.hardware.isAppleSilicon == true {
                        card(L("Термосостояние"), icon: "thermometer.medium") {
                            Text(L10n.text(model.snapshot?.thermalState ?? "—"))
                            Text(L("Системная оценка; температура в °C недоступна")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let battery = model.snapshot?.battery, battery.hasBattery {
                        card(L("Аккумулятор"), icon: "battery.100percent") {
                            Text(MetricFormat.percent(battery.charge)).font(.title.bold())
                            Text("\(L10n.text(battery.powerSource)) · \(L10n.text(battery.isCharging ? "Заряжается" : "Не заряжается"))")
                            Text(L("Здоровье: \(MetricFormat.percent(battery.health)) · \(L10n.text(battery.condition ?? "—"))"))
                            Text(L("Циклы: \(battery.cycles.map(String.init) ?? "—")"))
                        }
                    }
                    card(L("Memory"), icon: "memorychip") {
                        if let ram = model.snapshot?.memory {
                            MetricGauge(title: "RAM", used: ram.used, total: ram.total)
                            Text(L("Active \(MetricFormat.gb(ram.active)) · Wired \(MetricFormat.gb(ram.wired)) · Compressed \(MetricFormat.gb(ram.compressed)) GB"))
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text("—") }
                    }
                    card(model.snapshot?.gpu.name ?? "GPU", icon: "display") {
                        if let gpu = model.snapshot?.gpu {
                            if let used = gpu.usedVRAM { MetricGauge(title: L("VRAM In-Use"), used: used, total: gpu.totalVRAM) }
                            else { Text("VRAM — / \(MetricFormat.gb(gpu.totalVRAM)) GB") }
                            if gpu.isUnified, let limit = gpu.workingSetLimit {
                                Text(L("Рекомендованный лимит Metal: \(MetricFormat.gb(limit)) GB")).font(.caption)
                            }
                            Text(L("Load \(MetricFormat.percent(gpu.utilization)) · \(MetricFormat.temperature(model.snapshot?.gpuTemperature))"))
                            if let issue = gpu.issue { Text(L10n.text(issue)).font(.caption).foregroundStyle(.secondary) }
                        } else { Text("—") }
                    }
                    card(L("Storage /"), icon: "internaldrive") {
                        if let disk = model.snapshot?.storage {
                            MetricGauge(title: L("Volume"), used: disk.used, total: disk.total)
                            Text(L("Free \(MetricFormat.gb(disk.free)) GB"))
                                .font(.caption).foregroundStyle(.secondary)
                            if let temperature = model.snapshot?.temperature(keys: ["TH0P"]),
                               temperature.isFinite, (10...150).contains(temperature) {
                                Text(L("Drive bay \(MetricFormat.temperature(temperature))"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("—") }
                    }
                }
                card(L("CPU & GPU · 60 seconds"), icon: "waveform.path.ecg") {
                    Chart(model.history) { point in
                        if let cpu = point.cpu {
                            LineMark(x: .value(L("Time"), point.date), y: .value(L("Load"), cpu))
                                .foregroundStyle(by: .value(L("Device"), "CPU"))
                        }
                        if let gpu = point.gpu {
                            LineMark(x: .value(L("Time"), point.date), y: .value(L("Load"), gpu))
                                .foregroundStyle(by: .value(L("Device"), "GPU"))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: (model.history.last?.date ?? Date()).addingTimeInterval(-60)...(model.history.last?.date ?? Date()))
                    .chartForegroundStyleScale(["CPU": Color.blue, "GPU": Color.orange])
                    .frame(height: 160)
                }
                HStack {
                    Text(L("Top 10 Processes")).font(.headline)
                    Spacer()
                    Picker(L("Sort"), selection: $rankByMemory) {
                        Text("CPU").tag(false)
                        Text("RAM").tag(true)
                    }.pickerStyle(.segmented).frame(width: 160)
                }
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        Table(topProcesses, selection: $selection) {
                            TableColumn(L("Process")) { process in
                                Text(process.name).padding(.vertical, 5)
                            }
                            TableColumn("PID") { Text(String($0.pid)) }.width(70)
                            TableColumn("CPU") { Text(MetricFormat.percent($0.cpu)) }.width(80)
                            TableColumn(L("Действие")) { process in
                                Button(L("Завершить")) { pendingProcess = process; confirmingProcess = true }
                                    .buttonStyle(.bordered).controlSize(.large)
                                    .disabled(!ProcessControlService.canTerminate(process))
                                    .help(ProcessControlService.canTerminate(process) ? L("Запросить завершение процесса") : L("Критический процесс защищён"))
                            }.width(min: 130, ideal: 170, max: 240)
                            TableColumn("RAM") { Text("\(MetricFormat.gb($0.residentBytes)) GB") }.width(100)
                        }.frame(width: max(720, geometry.size.width), height: 360)
                    }
                }.frame(height: 380)
                    .task(id: selection) {
                        guard let id = selection, let process = topProcesses.first(where: { $0.id == id }) else { return }
                        // Present outside NSTableView's selection delegate callback.
                        await Task.yield()
                        guard !Task.isCancelled, selection == id else { return }
                        selectedProcess = process
                    }
                    .sheet(item: $selectedProcess, onDismiss: {
                        selection = nil
                        if pendingProcess != nil { confirmingProcess = true }
                    }) { process in
                        ProcessDetailView(process: process) {
                            pendingProcess = process
                            selectedProcess = nil
                        }
                    }
                if let processMessage { Text(L10n.text(processMessage)).font(.callout).textSelection(.enabled) }
                Text(L("CPU процессов: 100% = одно ядро. RAM: Active + Wired + Compressed; значения GB используют 1024³ байт."))
                    .font(.caption).foregroundStyle(.secondary)

            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .monospacedDigit()
        .alert(pendingProcess?.isSystem == true ? L("Завершить системную службу?") : L("Завершить процесс?"), isPresented: $confirmingProcess) {
            Button(L("Отмена"), role: .cancel) { pendingProcess = nil }
            Button(L("Завершить"), role: .destructive) {
                guard let process = pendingProcess else { return }
                do {
                    try ProcessControlService.terminate(process)
                    processMessage = L("Запрос завершения отправлен: \(process.name) (PID \(process.pid)). Список обновится при следующем опросе.")
                } catch { processMessage = error.localizedDescription }
                pendingProcess = nil
            }
        } message: {
            if let process = pendingProcess {
                Text("\(process.name), PID \(process.pid)\n" + L10n.text(ProcessControlService.warning(for: process)))
            }
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text(title), systemImage: icon).font(.headline).foregroundStyle(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
