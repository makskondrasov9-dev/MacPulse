import AppKit
import MonitorCore

@MainActor final class InsightsModel: ObservableObject {
    @Published private(set) var peaks = SessionPeaks()
    @Published private(set) var usage = DailyUsage()
    @Published private(set) var audit = ProcessAudit()
    @Published var tracksUsage = UserDefaults.standard.bool(forKey: "trackApplicationUsage") {
        didSet { UserDefaults.standard.set(tracksUsage, forKey: "trackApplicationUsage"); previousApp = nil }
    }
    private let store = AnalyticsStore()
    private var previousDate: Date?
    private var previousApp: (String, String)?
    private var saved = Date.distantPast
    private var saveTask: Task<Void, Never>?

    func load() async { if let value = await store.load(DailyUsage.self, name: "usage.json") { usage = value }; usage.resetDay() }
    func sample(_ snapshot: MonitorSnapshot) {
        peaks.record(temperature: snapshot.cpuTemperature, memory: snapshot.memory?.used,
                     gpu: (snapshot.gpus.isEmpty ? [snapshot.gpu] : snapshot.gpus).compactMap(\.utilization).max())
        let now = snapshot.date
        usage.resetDay(at: now)
        if let previousDate {
            audit.record(snapshot.processes, elapsed: now.timeIntervalSince(previousDate))
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
            let onConsole = (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool ?? false
            if tracksUsage, onConsole, idle < 60, let app = previousApp {
                usage.record(id: app.0, name: app.1, from: previousDate, to: now)
            }
        }
        previousDate = now
        if tracksUsage, let app = NSWorkspace.shared.frontmostApplication {
            previousApp = (app.bundleIdentifier ?? app.localizedName ?? String(app.processIdentifier), app.localizedName ?? "Application")
        } else { previousApp = nil }
        if now.timeIntervalSince(saved) >= 30 { saved = now; persist() }
    }
    func clearUsage() { usage = DailyUsage(); previousApp = nil; persist() }
    private func persist() {
        let value = usage, previous = saveTask
        saveTask = Task { await previous?.value; try? await store.save(value, name: "usage.json") }
    }
    func stop() async { persist(); await saveTask?.value }
}
