import AppKit
import Foundation
import MonitorCore
import SwiftUI

struct HistoryPoint: Identifiable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    var network: Double? = nil
    var download: Double? = nil
    var upload: Double? = nil
    var id: Date { date }
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var widgetHistory: [HistoryPoint] = []
    @Published private(set) var pollingInterval = normalizedInterval(
        UserDefaults.standard.object(forKey: "pollingInterval") as? Double ?? 2
    )

    static func normalizedInterval(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 1), 3) : 2
    }

    func setPollingInterval(_ value: Double) {
        pollingInterval = Self.normalizedInterval(value)
    }

    var fullInterfaceVisible = false { didSet { if !fullInterfaceVisible { dashboard.setScrolling(false) } } }
    var popoverVisible = false
    var fullMonitoringRequired: Bool {
        fullInterfaceVisible || popoverVisible || !WidgetPreferences.enabled.isEmpty
            || diagnostics.running != nil
    }
    var effectivePollingInterval: Double {
        fullMonitoringRequired ? pollingInterval : max(3, pollingInterval)
    }
    var requestedMetrics: MetricSelection {
        if fullInterfaceVisible || popoverVisible || diagnostics.running != nil { return .all }
        let d = UserDefaults.standard
        let mode = MenuBarDisplayMode.resolve(d.string(forKey: "menuBarTextStyle") ?? "full")
        var selection = WidgetPreferences.metrics
        if (mode.hasText && (d.object(forKey: "showCPUPercentage") as? Bool ?? true))
            || (mode.hasChart && (d.object(forKey: "showCPUChart") as? Bool ?? true))
        {
            selection.insert(.cpu)
        }
        if mode.hasText && d.bool(forKey: "showRAMPercentage") { selection.insert(.memory) }
        if mode.hasText && d.bool(forKey: "showGPUPercentage") { selection.insert(.gpu) }
        if mode.hasText && d.bool(forKey: "showCPUTemperature") { selection.insert(.temperature) }
        if (mode.hasText && d.bool(forKey: "showNetworkSpeed")) || (mode.hasChart && d.bool(forKey: "showNetworkChart"))
        {
            selection.insert(.network)
        }
        return selection
    }
    let dashboard = DashboardTelemetry()
    let diagnostics = DiagnosticsModel()
    let insights = InsightsModel()
    let cleaner = CleanerModel()
    let fans = FanModel()
    let uninstaller = UninstallerModel()
    private let collector = MetricCollector()
    private var polling: Task<Void, Never>?

    func start() {
        guard polling == nil else { return }
        fans.start()
        let collector = collector
        polling = Task { [weak self] in
            await self?.diagnostics.load()
            await self?.insights.load()
            while !Task.isCancelled {
                let snapshot = await collector.sample(selection: self?.requestedMetrics ?? [])
                guard !Task.isCancelled else { break }
                self?.accept(snapshot)
                do {
                    try await Task.sleep(
                        for: .seconds(
                            self?.effectivePollingInterval ?? 3),
                        tolerance: .milliseconds(200))
                } catch { break }
            }
            await collector.close()
        }
    }

    func stop() async {
        DesktopWidgetService.shared.stop()
        polling?.cancel()
        await polling?.value
        polling = nil
        DisplayTestController.shared.close()
        await diagnostics.stop()
        await insights.stop()
        await fans.stop()
        await cleaner.stop()
        await uninstaller.stop()
    }

    private func accept(_ snapshot: MonitorSnapshot) {
        if let previous = self.snapshot, previous.gpu.id != snapshot.gpu.id {
            // A newly connected primary GPU must not inherit another device's chart values.
            history = history.map { HistoryPoint(date: $0.date, cpu: $0.cpu, gpu: nil, network: $0.network, download: $0.download, upload: $0.upload) }
            widgetHistory = widgetHistory.map { HistoryPoint(date: $0.date, cpu: $0.cpu, gpu: nil, network: $0.network, download: $0.download, upload: $0.upload) }
        }
        diagnostics.sample(
            snapshot,
            identityNeeded: fullInterfaceVisible || popoverVisible || WidgetPreferences.enabled.contains(.network) || UserDefaults.standard.bool(forKey: "showMenuBarIP")
                || UserDefaults.standard.bool(forKey: "showMenuBarVPN"))
        insights.sample(snapshot)
        self.snapshot = snapshot
        history.append(
            HistoryPoint(
                date: snapshot.date, cpu: snapshot.cpu?.usage, gpu: snapshot.gpu.utilization,
                network: snapshot.network.downloadBytesPerSecond.flatMap { down in
                    snapshot.network.uploadBytesPerSecond.map { down + $0 }
                }, download: snapshot.network.downloadBytesPerSecond, upload: snapshot.network.uploadBytesPerSecond))
        history.removeAll { $0.date < snapshot.date.addingTimeInterval(-60) }
        if history.count > 20 { history = Array(history.dropFirst(history.count - 20)) }
        if !WidgetPreferences.enabled.isEmpty, let point = history.last {
            let bucket = Int(point.date.timeIntervalSince1970 / 3)
            if let last = widgetHistory.last, Int(last.date.timeIntervalSince1970 / 3) == bucket {
                widgetHistory[widgetHistory.count - 1] = point
            } else { widgetHistory.append(point) }
            widgetHistory.removeAll { $0.date < point.date.addingTimeInterval(-60) }
            if widgetHistory.count > 20 { widgetHistory = Array(widgetHistory.suffix(20)) }
        } else if !widgetHistory.isEmpty { widgetHistory = [] }
        if fullInterfaceVisible { dashboard.accept(snapshot: snapshot, history: history) }
    }
}

enum MetricFormat {
    static func ratio(_ used: UInt64, _ total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        return min(Double(used) / Double(total) * 100, 100)
    }
    // Keep compound numeric readings in their conventional order inside RTL sentences.
    static func ltr(_ value: String) -> String {
        L10n.language == .ar ? "\u{2066}\(value)\u{2069}" : value
    }
    static func percent(_ value: Double?) -> String {
        value.map { ltr(String(format: "%.0f%%", locale: L10n.locale, $0)) } ?? "—"
    }
    static func temperature(_ value: Double?) -> String {
        value.map { ltr(String(format: "%.0f\u{00a0}°C", locale: L10n.locale, $0)) } ?? "—"
    }
    // Binary units match the hardware profile (32 GB RAM / 4 GB VRAM).
    static func gb(_ value: UInt64) -> String {
        String(format: "%.1f", locale: L10n.locale, Double(value) / 1_073_741_824)
    }
    static func uptime(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        let minutes = Int(value) / 60
        return L("\(minutes / 1440)d \(minutes / 60 % 24)h \(minutes % 60)m")
    }
}

/// Preserve the dashboard while hidden; freeze its presentation during native inertial scrolling.
@MainActor final class DashboardTelemetry: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    var scrollOffset: CGPoint = .zero
    private var scrolling = false
    private var pending: (MonitorSnapshot, [HistoryPoint])?
    func setScrolling(_ value: Bool) {
        scrolling = value
        if !value, let pending { self.pending = nil; accept(snapshot: pending.0, history: pending.1) }
    }
    func accept(snapshot: MonitorSnapshot, history: [HistoryPoint]) {
        guard !scrolling else { pending = (snapshot, history); return }
        self.snapshot = snapshot; self.history = history
    }
}
