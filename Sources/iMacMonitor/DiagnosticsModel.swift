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
    enum Test: String { case disk = "Disk benchmark", cpu = "CPU stress test", gpu = "GPU Metal test", network = "Network speed test", trace = "Traceroute", ipv6 = "IPv6 check" }
    @Published private(set) var running: Test?
    @Published private(set) var progress = 0.0
    @Published private(set) var message: String?
    @Published private(set) var disk: DiskBenchmarkResult?
    @Published private(set) var network: NetworkQualityResult?
    @Published private(set) var thermal: [ThermalPoint] = []
    @Published private(set) var thermalState = "Неизвестно"
    @Published private(set) var workRate: Double?
    @Published private(set) var performancePercent: Double?
    @Published private(set) var log: [String] = []
    @Published private(set) var hops: [TraceHop] = []
    @Published private(set) var ipv6: IPv6Report?
    @Published private(set) var networkTargets: [String] = []
    @Published private(set) var transfers: [TransferPoint] = []
    @Published private(set) var httpLatency: Double?
    @Published private(set) var probingLatency = false
    @Published private(set) var publicIPEndpoint = UserDefaults.standard.string(forKey: "publicIPEndpoint") ?? PublicIPConfiguration.defaultURL
    @Published private(set) var publicIPInterval = UserDefaults.standard.object(forKey: "publicIPInterval") as? Double ?? 60
    let nominalGHz = CPUCapabilities.nominalGHz
    private var reference = CPUPerformanceReference()
    private var referenceKey = ""
    private var lastPhase = 0
    private var latencyTask: Task<Void, Never>?

    @Published private(set) var sawThermalPressure = false
    @Published private(set) var currentThermalPressure = false
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

    init() {
        if (try? PublicIPConfiguration(endpoint: publicIPEndpoint, interval: publicIPInterval)) == nil {
            publicIPEndpoint = PublicIPConfiguration.defaultURL; publicIPInterval = 60
        }
    }
    func load() async {
        history = await store.load(IPHistory.self, name: "ip-history.json") ?? IPHistory()
        refreshIdentity()
    }
    func start(_ test: Test, seconds: Int = 15, workers: Int = CPUCapabilities.maximumWorkers, host: String = "1.1.1.1") {
        guard running == nil else { return }
        running = test; progress = 0; message = nil; started = Date(); duration = Double(seconds)
        thermalStop = false; workRate = nil; performancePercent = nil; log = []; lastPhase = 0
        appendLog(L("Preparing test"))
        referenceKey = "cpu-vector-v2-\(HardwareProfile.current.processor)-\(ProcessInfo.processInfo.processorCount)-\(workers)"
        reference = CPUPerformanceReference(best: UserDefaults.standard.double(forKey: referenceKey))
        if test == .trace { hops = [] }
        if test == .ipv6 { ipv6 = nil }
        if test == .network { networkTargets = []; transfers = []; httpLatency = nil }
        if test == .cpu || test == .gpu { thermal = []; sawThermalPressure = false; currentThermalPressure = false }
        if test == .disk { disk = nil }; if test == .network { network = nil }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch test {
                case .disk:
                    disk = try await BenchmarkEngine.disk { [weak self] value in await self?.updateProgress(value) }
                case .cpu:
                    workRate = Double(try await BenchmarkEngine.cpu(seconds: seconds, workers: workers) { [weak self] value in
                        await self?.acceptCPU(value)
                    }) / max(Date().timeIntervalSince(started), 0.001)
                    UserDefaults.standard.set(reference.best, forKey: referenceKey)
                case .gpu: workRate = Double(try await BenchmarkEngine.gpu(seconds: seconds)) / max(Date().timeIntervalSince(started), 0.001)
                case .network:
                    network = try await service.measure { [weak self] targets in await self?.acceptTargets(targets) }
                case .trace: try await NetworkLab.trace(host: host) { [weak self] hop in await self?.acceptHop(hop) }
                case .ipv6: ipv6 = try await NetworkLab.ipv6()
                }
                try Task.checkCancellation()
                progress = 1; message = "Test completed"
            } catch is CancellationError { message = thermalStop ? "Stopped: critical thermal state" : "Test cancelled" }
            catch { message = error.localizedDescription }
            latencyTask?.cancel(); await latencyTask?.value; latencyTask = nil; probingLatency = false
            appendLog(L10n.text(message ?? "Test completed"))
            running = nil; task = nil
        }
    }
    private func appendLog(_ text: String) {
        log.append("[" + Date().formatted(date: .omitted, time: .standard) + "] " + text)
        if log.count > 180 { log.removeFirst(log.count - 180) }
    }
    private func acceptCPU(_ value: CPUProgress) {
        workRate = value.batchesPerSecond
        if value.elapsed >= 3 { performancePercent = reference.record(value.batchesPerSecond) }
        let phase = min(3, Int(value.elapsed / max(duration / 3, 1)) + 1)
        if phase != lastPhase { lastPhase = phase; appendLog(L("Phase \(phase)/3: CPU load")) }
        appendLog(L("Batches per second") + ": " + String(format: "%.0f", value.batchesPerSecond))
    }
    private func acceptHop(_ value: TraceHop) {
        if let index = hops.firstIndex(where: { $0.number == value.number }) { hops[index] = value }
        else { hops.append(value) }
    }
    private func acceptTargets(_ targets: [String]) {
        networkTargets = targets
        appendLog(L("Network test endpoints") + ": " + targets.joined(separator: " · "))
        guard targets.count == 3, let url = URL(string: targets[0]) else { return }
        latencyTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.probingLatency = true
                do { self?.httpLatency = try await DiagnosticHTTP.latency(url) }
                catch { self?.httpLatency = nil }
                self?.probingLatency = false
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }
    func configurePublicIP(endpoint: String, interval: Double) {
        do {
            let config = try PublicIPConfiguration(endpoint: endpoint, interval: interval)
            ipTask?.cancel(); publicIP = nil; ipError = nil
            publicIPEndpoint = config.url.absoluteString; publicIPInterval = config.interval
            UserDefaults.standard.set(publicIPEndpoint, forKey: "publicIPEndpoint")
            UserDefaults.standard.set(publicIPInterval, forKey: "publicIPInterval")
            lastPublic = .distantPast
            refreshIdentity(forcePublic: true)
        } catch { ipError = error.localizedDescription }
    }
    private func updateProgress(_ value: Double) { progress = value }
    func cancel() { task?.cancel(); latencyTask?.cancel() }
    func sample(_ snapshot: MonitorSnapshot, identityNeeded: Bool = true) {
        if running == .network {
            transfers.append(TransferPoint(date: snapshot.date,
                download: snapshot.network.downloadBytesPerSecond.map { $0 * 8 / 1e6 },
                upload: snapshot.network.uploadBytesPerSecond.map { $0 * 8 / 1e6 }, latency: httpLatency))
            if transfers.count > 120 { transfers.removeFirst() }
        }
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
            if let temperature = snapshot.cpuTemperature { appendLog("CPU: " + MetricFormat.temperature(temperature)) }
            let state = ProcessInfo.processInfo.thermalState
            currentThermalPressure = state == .serious || state == .critical
            if currentThermalPressure || (limit ?? 100) < 100 { sawThermalPressure = true }
            if state == .critical { thermalStop = true; cancel() }
        }
        if identityNeeded && snapshot.date.timeIntervalSince(lastIdentity) >= 15 || (publicIPEnabled && !ipBusy && snapshot.date.timeIntervalSince(lastPublic) >= publicIPInterval) { refreshIdentity() }
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
        guard publicIPEnabled, !ipBusy, forcePublic || Date().timeIntervalSince(lastPublic) >= publicIPInterval else { return }
        ipBusy = true; lastPublic = Date(); ipError = nil
        let baseline = interfaces, endpoint = publicIPEndpoint
        ipTask = Task {
            defer { ipBusy = false; ipTask = nil }
            do {
                let ip = try await service.publicIP(endpoint: endpoint)
                try Task.checkCancellation()
                let current = await Task.detached(priority: .utility) { NetworkIdentity.current() }.value
                guard !Task.isCancelled, publicIPEnabled, endpoint == publicIPEndpoint, baseline == current else { return }
                publicIP = ip
                history.record(interfaces: baseline, publicIP: ip); persist()
            } catch is CancellationError {} catch { if !Task.isCancelled && endpoint == publicIPEndpoint { publicIP = nil; ipError = error.localizedDescription } }
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

struct TransferPoint: Identifiable {
    let date: Date
    let download: Double?
    let upload: Double?
    let latency: Double?
    var id: Date { date }
}
