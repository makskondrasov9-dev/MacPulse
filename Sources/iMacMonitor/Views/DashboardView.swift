import Charts
import MonitorCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    @State private var rankByMemory = false

    private var topProcesses: [ProcessMetrics] {
        Array((model.snapshot?.processes ?? []).sorted {
            let left = rankByMemory ? Double($0.residentBytes) : ($0.cpu ?? -1)
            let right = rankByMemory ? Double($1.residentBytes) : ($1.cpu ?? -1)
            return left == right ? $0.pid < $1.pid : left > right
        }.prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("MacPulse").font(.largeTitle.bold())
                        Text("Обновление: \(model.pollingInterval, specifier: "%.1f") с").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Uptime  \(MetricFormat.uptime(model.snapshot?.uptime))").font(.callout.monospacedDigit())
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)], spacing: 16) {
                    card("CPU", icon: "cpu") {
                        Text(MetricFormat.percent(model.snapshot?.cpu?.usage)).font(.title.bold())
                        Text("\(ProcessInfo.processInfo.processorCount) logical cores · \(MetricFormat.temperature(model.snapshot?.cpuTemperature))")
                        Text(model.snapshot?.hardware.processor ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.snapshot?.hardware.isAppleSilicon == true {
                        card("Термосостояние", icon: "thermometer.medium") {
                            Text(model.snapshot?.thermalState ?? "—")
                            Text("Системная оценка; температура в °C недоступна").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let battery = model.snapshot?.battery, battery.hasBattery {
                        card("Аккумулятор", icon: "battery.100percent") {
                            Text(MetricFormat.percent(battery.charge)).font(.title.bold())
                            Text("\(battery.powerSource) · \(battery.isCharging ? "Заряжается" : "Не заряжается")")
                            Text("Здоровье: \(MetricFormat.percent(battery.health)) · \(battery.condition ?? "—")")
                            Text("Циклы: \(battery.cycles.map(String.init) ?? "—")")
                        }
                    }
                    card("Memory", icon: "memorychip") {
                        if let ram = model.snapshot?.memory {
                            MetricGauge(title: "RAM", used: ram.used, total: ram.total)
                            Text("Active \(MetricFormat.gb(ram.active)) · Wired \(MetricFormat.gb(ram.wired)) · Compressed \(MetricFormat.gb(ram.compressed)) GB")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text("—") }
                    }
                    card(model.snapshot?.gpu.name ?? "GPU", icon: "display") {
                        if let gpu = model.snapshot?.gpu {
                            if let used = gpu.usedVRAM { MetricGauge(title: "VRAM In-Use", used: used, total: gpu.totalVRAM) }
                            else { Text("VRAM — / \(MetricFormat.gb(gpu.totalVRAM)) GB") }
                            if gpu.isUnified, let limit = gpu.workingSetLimit {
                                Text("Рекомендованный лимит Metal: \(MetricFormat.gb(limit)) GB").font(.caption)
                            }
                            Text("Load \(MetricFormat.percent(gpu.utilization)) · \(MetricFormat.temperature(model.snapshot?.gpuTemperature))")
                            if let issue = gpu.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        } else { Text("—") }
                    }
                    card("Storage /", icon: "internaldrive") {
                        if let disk = model.snapshot?.storage {
                            MetricGauge(title: "Volume", used: disk.used, total: disk.total)
                            Text("Free \(MetricFormat.gb(disk.free)) GB")
                                .font(.caption).foregroundStyle(.secondary)
                            if let temperature = model.snapshot?.temperature(keys: ["TH0P"]),
                               temperature.isFinite, (10...150).contains(temperature) {
                                Text("Drive bay \(MetricFormat.temperature(temperature))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("—") }
                    }
                }
                card("CPU & GPU · 60 seconds", icon: "waveform.path.ecg") {
                    Chart(model.history) { point in
                        if let cpu = point.cpu {
                            LineMark(x: .value("Time", point.date), y: .value("Load", cpu))
                                .foregroundStyle(by: .value("Device", "CPU"))
                        }
                        if let gpu = point.gpu {
                            LineMark(x: .value("Time", point.date), y: .value("Load", gpu))
                                .foregroundStyle(by: .value("Device", "GPU"))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: (model.history.last?.date ?? Date()).addingTimeInterval(-60)...(model.history.last?.date ?? Date()))
                    .chartForegroundStyleScale(["CPU": Color.blue, "GPU": Color.orange])
                    .frame(height: 160)
                }
                HStack {
                    Text("Top 10 Processes").font(.headline)
                    Spacer()
                    Picker("Sort", selection: $rankByMemory) {
                        Text("CPU").tag(false)
                        Text("RAM").tag(true)
                    }.pickerStyle(.segmented).frame(width: 160)
                }
                Table(topProcesses) {
                    TableColumn("Process") { process in
                        Text(process.name)
                    }
                    TableColumn("PID") { Text(String($0.pid)) }.width(70)
                    TableColumn("CPU") { Text(MetricFormat.percent($0.cpu)) }.width(80)
                    TableColumn("RAM") { Text("\(MetricFormat.gb($0.residentBytes)) GB") }.width(100)
                }.frame(height: 280)
                Text("CPU процессов: 100% = одно ядро. RAM: Active + Wired + Compressed; значения GB используют 1024³ байт.")
                    .font(.caption).foregroundStyle(.secondary)

            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .monospacedDigit()
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.secondary)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
