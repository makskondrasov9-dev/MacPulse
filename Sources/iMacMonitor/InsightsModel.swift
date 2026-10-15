import AppKit
import MonitorCore

@MainActor final class InsightsModel: ObservableObject {
    @Published private(set) var peaks = SessionPeaks()
    @Published private(set) var usage = DailyUsage()
    @Published private(set) var audit = ProcessAudit()
    @Published var tracksUsage = UserDefaults.standard.bool(forKey: "trackApplicationUsage") {
        didSet { UserDefaults.standard.set(tracksUsage, forKey: "trackApplicationUsage"); tracker.reset(at: Date()); activationChanged() }
    }
    private let store = AnalyticsStore()
    private var activationObserver: NSObjectProtocol?
    private var tracker = ForegroundUsageTracker()
    private var previousDate: Date?
    private var saved = Date.distantPast
    private var saveTask: Task<Void, Never>?

    func load() async {
        if let value = await store.load(DailyUsage.self, name: "usage.json") { usage = value }; usage.resetDay()
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activationChanged() }
        }
        activationChanged()
    }
    private var eligible: Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let onConsole = (CGSessionCopyCurrentDictionary() as? [String: Any])?[kCGSessionOnConsoleKey as String] as? Bool ?? false
        return tracksUsage && onConsole && idle < 60
    }
    private func activationChanged() {
        let app = tracksUsage ? NSWorkspace.shared.frontmostApplication : nil
        tracker.activate(id: app.map { $0.bundleIdentifier ?? $0.localizedName ?? String($0.processIdentifier) }, name: app?.localizedName ?? "Application", at: Date(), eligible: eligible, usage: &usage)
    }
    private func accountUsage(at now: Date) { tracker.tick(at: now, eligible: eligible, usage: &usage) }
    func sample(_ snapshot: MonitorSnapshot) {
        peaks.record(temperature: snapshot.cpuTemperature, memory: snapshot.memory?.used,
                     gpu: (snapshot.gpus.isEmpty ? [snapshot.gpu] : snapshot.gpus).compactMap(\.utilization).max(), date: snapshot.date)
        let now = snapshot.date
        if let previousDate {
            audit.record(snapshot.processes, elapsed: now.timeIntervalSince(previousDate))
        }
        previousDate = now
        accountUsage(at: now)
        if now.timeIntervalSince(saved) >= 30 { saved = now; persist() }
    }
    func clearUsage() { usage = DailyUsage(); tracker.reset(at: Date()); activationChanged(); persist() }
    private func persist() {
        let value = usage, previous = saveTask
        saveTask = Task { await previous?.value; try? await store.save(value, name: "usage.json") }
    }
    func stop() async {
        accountUsage(at: Date())
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        persist(); await saveTask?.value
    }
}
