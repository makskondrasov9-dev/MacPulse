import AppKit
import Charts
import MonitorCore
import SwiftUI

struct DashboardView: View {
    let model: MonitorModel
    @ObservedObject private var display: DashboardTelemetry
    init(model: MonitorModel) {
        self.model = model
        self.display = model.dashboard
    }
    @AppStorage("hideUnavailableMetrics") private var hideUnavailable = true
    @State private var columns = 2
    @State private var rankByMemory = false
    @State private var selectedProcess: ProcessMetrics?
    @State private var selection: ProcessMetrics.ID?
    @State private var pendingProcess: ProcessMetrics?
    @State private var processMessage: String?
    @State private var confirmingProcess = false

    private var topProcesses: [ProcessMetrics] {
        Array(
            (display.snapshot?.processes ?? []).sorted {
                let left = rankByMemory ? Double($0.residentBytes) : ($0.cpu ?? -1)
                let right = rankByMemory ? Double($1.residentBytes) : ($1.cpu ?? -1)
                return left == right ? $0.pid < $1.pid : left > right
            }.prefix(10))
    }

    @Environment(\.locale) private var presentationLocale

    private var graphics: [GPUMetrics] {
        guard let snapshot = display.snapshot else { return [] }
        return snapshot.gpus.isEmpty ? [snapshot.gpu] : snapshot.gpus
    }

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
                    Text(L("Uptime  \(MetricFormat.uptime(display.snapshot?.uptime))")).font(.callout.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(0..<((cardIDs.count + columns - 1) / columns), id: \.self) { row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(cardIDs.dropFirst(row * columns).prefix(columns)), id: \.self) { id in
                                StableMetricCard(signature: signature(id)) { metricCard(id) }.equatable()
                                    .frame(maxWidth: .infinity, maxHeight: cardHidden(id) ? 0 : nil)
                                    .clipped().opacity(cardHidden(id) ? 0 : 1)
                                    .animation(.easeInOut(duration: 0.2), value: cardHidden(id))
                            }
                            if row == (cardIDs.count - 1) / columns && cardIDs.count % columns != 0 {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
                .id("metric-cards")
                InsightsView(model: model.insights).id("session-insights")
                card(L("CPU & GPU · 60 seconds"), icon: "waveform.path.ecg") {
                    Text(display.snapshot?.gpu.name ?? "GPU").font(.caption).foregroundStyle(.secondary)
                    HistoryChart(history: display.history)
                }
                .id("history-chart")
                HStack {
                    Text(L("Top 10 Processes")).font(.headline)
                    Spacer()
                    Picker(L("Sort"), selection: $rankByMemory) {
                        Text("CPU").tag(false)
                        Text("RAM").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
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
                                Button(L("Завершить")) {
                                    pendingProcess = process
                                    confirmingProcess = true
                                }
                                .buttonStyle(.bordered).controlSize(.large)
                                .disabled(!ProcessControlService.canTerminate(process))
                                .help(
                                    ProcessControlService.canTerminate(process)
                                        ? L("Запросить завершение процесса") : L("Критический процесс защищён"))
                            }.width(min: 130, ideal: 170, max: 240)
                            TableColumn("RAM") { Text("\(MetricFormat.gb($0.residentBytes)) GB") }.width(100)
                        }.frame(width: max(720, geometry.size.width), height: 360)
                    }
                }.frame(height: 380)
                    .task(id: selection) {
                        guard let id = selection, let process = topProcesses.first(where: { $0.id == id }) else {
                            return
                        }
                        // Present outside NSTableView's selection delegate callback.
                        await Task.yield()
                        guard !Task.isCancelled, selection == id else { return }
                        selectedProcess = process
                    }
                    .sheet(
                        item: $selectedProcess,
                        onDismiss: {
                            selection = nil
                            if pendingProcess != nil { confirmingProcess = true }
                        }
                    ) { process in
                        ProcessDetailView(process: process) {
                            pendingProcess = process
                            selectedProcess = nil
                        }
                    }
                if let processMessage { Text(L10n.text(processMessage)).font(.callout).textSelection(.enabled) }
                Text(
                    L(
                        "CPU процессов: 100% = одно ядро. RAM: Active + Wired + Compressed; значения GB используют 1024³ байт."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)

            }
            .id("dashboard-content")
            .animation(.easeInOut(duration: 0.2), value: hideUnavailable)
            .padding(24)
            .background(StableScrollAnchor(collapsed: hideUnavailable, display: display))
            }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: DashboardWidth.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(DashboardWidth.self) { width in
            Task { @MainActor in
                let next = width >= 960 ? 3 : 2
                if columns != next { columns = next }
            }
        }
        .background(.ultraThinMaterial)
        .monospacedDigit()
        .alert(
            pendingProcess?.isSystem == true ? L("Завершить системную службу?") : L("Завершить процесс?"),
            isPresented: $confirmingProcess
        ) {
            Button(L("Отмена"), role: .cancel) { pendingProcess = nil }
            Button(L("Завершить"), role: .destructive) {
                guard let process = pendingProcess else { return }
                do {
                    try ProcessControlService.terminate(process)
                    processMessage = L(
                        "Запрос завершения отправлен: \(process.name) (PID \(process.pid)). Список обновится при следующем опросе."
                    )
                } catch { processMessage = error.localizedDescription }
                pendingProcess = nil
            }
        } message: {
            if let process = pendingProcess {
                Text("\(process.name), PID \(process.pid)\n" + L10n.text(ProcessControlService.warning(for: process)))
            }
        }
    }

    private var cardIDs: [String] {
        var ids = ["cpu", "ram"] + graphics.map { "gpu:" + $0.id } + ["network", "storage"]
        if display.snapshot?.hardware.isAppleSilicon == true { ids.append("thermal") }
        if display.snapshot?.battery.hasBattery == true { ids.append("battery") }
        return ids
    }
    private func cardHidden(_ id: String) -> Bool {
        guard hideUnavailable else { return false }
        switch id {
        case "cpu": return display.snapshot?.cpu == nil
        case "ram": return display.snapshot?.memory == nil
        case "storage": return display.snapshot?.storage == nil
        case "network": return display.snapshot?.network.isAvailable != true
        default: return false
        }
    }
    private func signature(_ id: String) -> String {
        let s = display.snapshot
        var value = id + presentationLocale.identifier + String(hideUnavailable)
        switch id {
        case "cpu":
            value +=
                MetricFormat.percent(s?.cpu?.usage) + MetricFormat.temperature(s?.cpuTemperature)
                + (s?.hardware.processor ?? "")
        case "ram":
            value +=
                MetricFormat.percent(s?.memory.flatMap { MetricFormat.ratio($0.used, $0.total) })
                + String(s?.memory?.total ?? 0)
        case "storage":
            value +=
                MetricFormat.percent(s?.storage.flatMap { MetricFormat.ratio($0.used, $0.total) })
                + String(s?.storage?.total ?? 0) + MetricFormat.temperature(s?.temperature(keys: ["TH0P"]))
                + String(describing: s?.storageHealth)
        case "network":
            value +=
                String(
                    format: "%.2g:%.2g:%.2g:%.2g", s?.network.downloadBytesPerSecond ?? -1,
                    s?.network.uploadBytesPerSecond ?? -1, Double(s?.network.receivedBytes ?? 0),
                    Double(s?.network.sentBytes ?? 0)) + String(describing: s?.network.interfaces)
        case "thermal": value += s?.thermalState ?? ""
        case "battery": value += String(describing: s?.battery)
        default:
            if let gpu = graphics.first(where: { "gpu:" + $0.id == id }) {
                value +=
                    gpu.name + MetricFormat.percent(gpu.utilization) + MetricFormat.temperature(gpu.temperature)
                    + MetricFormat.percent(
                        gpu.usedVRAM.flatMap { used in gpu.totalVRAM.flatMap { MetricFormat.ratio(used, $0) } })
                    + String(gpu.totalVRAM ?? 0)
            }
        }
        return value
    }
    @ViewBuilder private func metricCard(_ id: String) -> some View {
        switch id {
        case "cpu":
            card("CPU", icon: "cpu") {
                Text(MetricFormat.percent(display.snapshot?.cpu?.usage)).font(.title.bold())
                if hideUnavailable && display.snapshot?.cpuTemperature == nil {
                    Text("CPU × \(ProcessInfo.processInfo.processorCount)")
                } else {
                    Text(
                        L(
                            "\(ProcessInfo.processInfo.processorCount) logical cores · \(MetricFormat.temperature(display.snapshot?.cpuTemperature))"
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(display.snapshot?.hardware.processor ?? "—").font(.caption).foregroundStyle(.secondary)
            }

        case "ram":
            card(L("Memory"), icon: "memorychip") {
                if let ram = display.snapshot?.memory {
                    MetricGauge(title: "RAM", used: ram.used, total: ram.total)
                    Text(
                        L(
                            "Active \(MetricFormat.gb(ram.active)) · Wired \(MetricFormat.gb(ram.wired)) · Compressed \(MetricFormat.gb(ram.compressed)) GB"
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("—")
                }
            }

        case "network":
            card(L("Сеть"), icon: "network") {
                NetworkCardContent(
                    network: display.snapshot?.network ?? NetworkMetrics(), diagnostics: model.diagnostics)
            }

        case "storage":
            card(L("Storage /"), icon: "internaldrive") {
                if let disk = display.snapshot?.storage {
                    MetricGauge(title: L("Volume"), used: disk.used, total: disk.total)
                    Text(L("Free \(MetricFormat.gb(disk.free)) GB"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let health = display.snapshot?.storageHealth {
                        StorageHealthBadge(health: health)
                    }
                    if let temperature = display.snapshot?.temperature(keys: ["TH0P"]),
                        temperature.isFinite, (10...150).contains(temperature)
                    {
                        Text(L("Drive bay \(MetricFormat.temperature(temperature))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                }
            }

        case "thermal":

            card(L("Термосостояние"), icon: "thermometer.medium") {
                Text(L10n.text(display.snapshot?.thermalState ?? "—"))
                Text(L("Системная оценка; температура в °C недоступна")).font(.caption).foregroundStyle(.secondary)
            }

        case "battery":
            if let battery = display.snapshot?.battery {

                card(L("Аккумулятор"), icon: "battery.100percent") {
                    Text(MetricFormat.percent(battery.charge)).font(.title.bold())
                    Text(
                        "\(L10n.text(battery.powerSource)) · \(L10n.text(battery.isCharging ? "Заряжается" : "Не заряжается"))"
                    )
                    Text(
                        L("Здоровье: \(MetricFormat.percent(battery.health)) · \(L10n.text(battery.condition ?? "—"))"))
                    Text(L("Циклы: \(battery.cycles.map(String.init) ?? "—")"))
                }

            }
        default:
            if let gpu = graphics.first(where: { "gpu:" + $0.id == id }) {
                card(gpu.name, icon: "display") {
                    GPUCardContent(gpu: gpu)
                }

            }
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text(title), systemImage: icon).font(.headline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Rasterize only the rolling plot, preserving native text and controls elsewhere.
private struct HistoryChart: View {
    let history: [HistoryPoint]
    var body: some View {
        Chart(history) { point in
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
        .chartXScale(domain: (history.last?.date ?? Date()).addingTimeInterval(-60)...(history.last?.date ?? Date()))
        .chartForegroundStyleScale(["CPU": Color.blue, "GPU": Color.orange])
        .frame(height: 160)
        .padding(.vertical, 8)
        .drawingGroup()
    }
}

private struct DashboardWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Preserve the native clip offset through a disclosure-size change, clamping only at the end.
private struct StableScrollAnchor: NSViewRepresentable {
    let collapsed: Bool
    let display: DashboardTelemetry
    final class Anchor: NSView {
        var previous: Bool?
        weak var display: DashboardTelemetry?
        private var observers: [NSObjectProtocol] = []
        private weak var installedScroll: NSScrollView?
        var preservingOffset = false
        private var trackingScroll = false
        func restore(_ offset: CGPoint) {
            guard let scroll = enclosingScrollView else { return }
            let maximum = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: CGPoint(x: offset.x, y: min(offset.y, maximum)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            // Include keyboard/accessibility scrolling, which has no live-scroll gesture.
            if newWindow == nil, !preservingOffset, let scroll = installedScroll {
                display?.scrollOffset = scroll.contentView.bounds.origin
            }
            super.viewWillMove(toWindow: newWindow)
        }
        func disconnect() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = []
            installedScroll = nil
            display?.setScrolling(false)
        }
        override func layout() {
            super.layout()
            if installedScroll == nil { DispatchQueue.main.async { [weak self] in self?.install() } }
        }
        func install() {
            guard window != nil, let scroll = enclosingScrollView, scroll !== installedScroll else { return }
            disconnect()
            installedScroll = scroll
            preservingOffset = true
            let saved = display?.scrollOffset ?? .zero
            restore(saved)
            // SwiftUI installs safe-area insets and the scroll document after attachment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak scroll] in
                guard let self, let scroll, self.installedScroll === scroll else { return }
                self.restore(saved)
                self.preservingOffset = false
            }
            scroll.contentView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.preservingOffset, self.window != nil,
                          let clip = self.installedScroll?.contentView else { return }
                    self.display?.scrollOffset = clip.bounds.origin
                }
            })
            for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: scroll, queue: .main) { [weak self] note in
                    let live = note.name == NSScrollView.willStartLiveScrollNotification
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.trackingScroll = live
                        if !live, !self.preservingOffset, let scroll = self.installedScroll {
                            self.display?.scrollOffset = scroll.contentView.bounds.origin
                        }
                        self.display?.setScrolling(live)
                    }
                })
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { let view = Anchor(); view.display = display; return view }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.disconnect() }
    func updateNSView(_ view: Anchor, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.install() }
        defer { view.previous = collapsed }
        guard let previous = view.previous, previous != collapsed, view.enclosingScrollView != nil else { return }
        let offset = view.enclosingScrollView?.contentView.bounds.origin ?? display.scrollOffset
        display.scrollOffset = offset
        view.preservingOffset = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak view] in
            view?.restore(offset)
            view?.preservingOffset = false
        }
    }
}

private struct StableMetricCard<Content: View>: View, Equatable {
    let signature: String
    @ViewBuilder let content: () -> Content
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.signature == rhs.signature }
    var body: some View { content() }
}
