import AppKit
import IOKit.pwr_mgt
import MonitorCore

struct ThermalPoint: Identifiable {
    let date: Date
    let temperature: Double?
    let gpuTemperature: Double?
    let speedLimit: Double?
    var id: Date { date }
}

@MainActor final class DiagnosticsModel: ObservableObject {
    enum Test: String { case disk = "Disk benchmark", cpu = "CPU stress test", gpu = "GPU Metal test", network = "Network speed test" }
    @Published private(set) var running: Test?
    @Published private(set) var progress = 0.0
    @Published private(set) var message: String?
    @Published private(set) var disk: DiskBenchmarkResult?
    @Published private(set) var network: NetworkQualityResult?
    @Published private(set) var thermal: [ThermalPoint] = []
    @Published private(set) var thermalState = "Неизвестно"
    @Published private(set) var workRate: Double?
    @Published private(set) var sawThermalPressure = false
    @Published private(set) var interfaces: [NetworkIdentity] = []
    @Published private(set) var publicIP: String?
    @Published private(set) var history = IPHistory()
    @Published private(set) var ipBusy = false
    @Published private(set) var ipError: String?
    @Published var publicIPEnabled = UserDefaults.standard.bool(forKey: "publicIPHistory") {
        didSet {
            UserDefaults.standard.set(publicIPEnabled, forKey: "publicIPHistory")
            if !publicIPEnabled { ipTask?.cancel(); publicIP = nil }
            refreshIdentity()
        }
    }
    private let service = NetworkDiagnosticsService()
    private let store = AnalyticsStore()
    private var task: Task<Void, Never>?
    private var ipTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?
    private var persistence: Task<Void, Never>?
    private var started = Date()
    private var duration = 15.0
    private var lastIdentity = Date.distantPast
    private var lastPublic = Date.distantPast
    private var thermalStop = false

    func load() async {
        history = await store.load(IPHistory.self, name: "ip-history.json") ?? IPHistory()
        refreshIdentity()
    }
    func start(_ test: Test, seconds: Int = 15) {
        guard running == nil else { return }
        running = test; progress = 0; message = nil; started = Date(); duration = Double(seconds)
        thermalStop = false; workRate = nil
        if test == .cpu || test == .gpu { thermal = []; sawThermalPressure = false }
        if test == .disk { disk = nil }; if test == .network { network = nil }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch test {
                case .disk:
                    disk = try await BenchmarkEngine.disk { [weak self] value in await self?.updateProgress(value) }
                case .cpu: workRate = Double(try await BenchmarkEngine.cpu(seconds: seconds)) / max(Date().timeIntervalSince(started), 0.001)
                case .gpu: workRate = Double(try await BenchmarkEngine.gpu(seconds: seconds)) / max(Date().timeIntervalSince(started), 0.001)
                case .network: network = try await service.measure()
                }
                try Task.checkCancellation()
                progress = 1; message = "Test completed"
            } catch is CancellationError { message = thermalStop ? "Stopped: critical thermal state" : "Test cancelled" }
            catch { message = error.localizedDescription }
            running = nil; task = nil
        }
    }
    private func updateProgress(_ value: Double) { progress = value }
    func cancel() { task?.cancel() }
    func sample(_ snapshot: MonitorSnapshot) {
        if running == .cpu || running == .gpu {
            thermalState = snapshot.thermalState
            progress = min(snapshot.date.timeIntervalSince(started) / duration, 0.99)
            var status: Unmanaged<CFDictionary>?
            var limit: Double?
            if IOPMCopyCPUPowerStatus(&status) == kIOReturnSuccess, let dictionary = status?.takeRetainedValue() as? [String: Any] {
                limit = (dictionary[kIOPMCPUPowerLimitProcessorSpeedKey] as? NSNumber)?.doubleValue
            }
            thermal.append(ThermalPoint(date: snapshot.date, temperature: snapshot.cpuTemperature, gpuTemperature: snapshot.gpuTemperature, speedLimit: limit))
            if thermal.count > 90 { thermal.removeFirst() }
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical || (limit ?? 100) < 100 { sawThermalPressure = true }
            if state == .critical { thermalStop = true; cancel() }
        }
        if snapshot.date.timeIntervalSince(lastIdentity) >= 15 { refreshIdentity() }
    }
    func refreshIdentity(forcePublic: Bool = false) {
        guard identityTask == nil else { return }
        lastIdentity = Date()
        identityTask = Task {
            let current = await Task.detached(priority: .utility) { NetworkIdentity.current() }.value
            if !Task.isCancelled { acceptIdentity(current, forcePublic: forcePublic) }
            identityTask = nil
        }
    }
    private func acceptIdentity(_ current: [NetworkIdentity], forcePublic: Bool) {
        if current != interfaces { interfaces = current; publicIP = nil; lastPublic = .distantPast }
        let previousEntry = history.entries.last?.id
        history.record(interfaces: interfaces, publicIP: publicIP)
        if history.entries.last?.id != previousEntry { persist() }
        guard publicIPEnabled, !ipBusy, forcePublic || Date().timeIntervalSince(lastPublic) >= 60 else { return }
        ipBusy = true; lastPublic = Date(); ipError = nil
        let baseline = interfaces
        ipTask = Task {
            defer { ipBusy = false; ipTask = nil }
            do {
                let ip = try await service.publicIP()
                try Task.checkCancellation()
                let current = await Task.detached(priority: .utility) { NetworkIdentity.current() }.value
                guard !Task.isCancelled, publicIPEnabled, baseline == current else { return }
                publicIP = ip
                history.record(interfaces: baseline, publicIP: ip); persist()
            } catch is CancellationError {} catch { publicIP = nil; ipError = error.localizedDescription }
        }
    }
    func clearHistory() { history = IPHistory(); persist() }
    private func persist() {
        let value = history, previous = persistence
        persistence = Task { await previous?.value; try? await store.save(value, name: "ip-history.json") }
    }
    func stop() async {
        cancel(); identityTask?.cancel(); ipTask?.cancel()
        await identityTask?.value
        await task?.value; await ipTask?.value; await persistence?.value
    }
}
