import AppKit
import Foundation
import MonitorCore

@MainActor
final class FanModel: ObservableObject {
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var hardwareMinimum: [Int: Double] = [:]
    @Published private(set) var status = "Штатное автоматическое управление"
    @Published private(set) var active = false
    @Published private(set) var authorizing = false
    @Published private(set) var error: String?
    private let service = FanService()
    private var polling: Task<Void, Never>?
    private var launcher: Process?
    private var session: URL?
    private var configurations: [Int: FanConfiguration] = [:]
    private var stopping = false
    private var sleepObserver: NSObjectProtocol?

    func start() {
        guard polling == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                // The notification is delivered on OperationQueue.main. Persist
                // the stop request before returning, rather than scheduling it after sleep.
                MainActor.assumeIsolated { self?.requestAutomatic() }
            }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let service = self?.service else { break }
                let snapshot = await service.sample()
                self?.accept(snapshot)
                self?.heartbeat()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func accept(_ snapshot: FanSnapshot) {
        if snapshot.issue == nil {
            fans = snapshot.fans
            for fan in fans where hardwareMinimum[fan.id] == nil { hardwareMinimum[fan.id] = fan.minimum }
        }
    }

    func apply(id: Int, configuration: FanConfiguration) {
        guard let fan = fans.first(where: { $0.id == id }), fan.controllable else { return }
        do {
            if configuration.mode != .automatic {
                _ = try configuration.target(hardwareMinimum: hardwareMinimum[id] ?? fan.minimum,
                                             hardwareMaximum: fan.maximum, temperature: 60)
            }
            configurations[id] = configuration
            error = nil
            if configurations.values.allSatisfy({ $0.mode == .automatic }) {
                Task { await stopSession() }; return
            }
            guard !authorizing, !stopping else { return }
            if session != nil { try writeLease(); return }
            try launchSession()
        } catch { self.error = error.localizedDescription }
    }

    private func launchSession() throws {
        guard let identity = ProcessControlService.currentProcess(), let executable = Bundle.main.executableURL else {
            throw FanError.message("Не удалось определить процесс MacPulse.")
        }
        let helper = executable.deletingLastPathComponent().appendingPathComponent("MacPulseFanHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw FanError.message("Компонент управления вентиляторами отсутствует. Переустановите приложение из DMG.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulse-fans-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let statusURL = folder.appendingPathComponent("status.json")
        guard FileManager.default.createFile(atPath: statusURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw FanError.message("Не удалось создать сессию управления.")
        }
        session = folder; stopping = false
        try writeLease()
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = [helper.path, "--session", folder.path, String(identity.pid), String(identity.ownerUID),
                       String(identity.startedSeconds), String(identity.startedMicroseconds)].map(shellQuote).joined(separator: " ")
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(literal)\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor in self?.sessionEnded(code: code) }
        }
        authorizing = true
        status = "Подтвердите доступ администратора в окне macOS."
        launcher = process
        do { try process.run() }
        catch { sessionEnded(code: -1); throw error }
    }

    private func writeLease() throws {
        guard let session else { return }
        let data = try JSONEncoder().encode(FanLease(configurations: configurations, stop: stopping))
        try data.write(to: session.appendingPathComponent("lease.json"), options: .atomic)
    }

    private func readStatus() -> FanWorkerStatus? {
        guard let session, let data = try? Data(contentsOf: session.appendingPathComponent("status.json")) else { return nil }
        return try? JSONDecoder().decode(FanWorkerStatus.self, from: data)
    }

    private func heartbeat() {
        guard session != nil else { return }
        do { try writeLease() }
        catch { self.error = "Сессия управления прервана. Помощник вернёт штатные обороты." }
        if let report = readStatus() {
            active = report.active && abs(report.updatedAt.timeIntervalSinceNow) < 8
            status = report.message
            authorizing = false
            if !report.active && !report.restored { error = report.message }
        }
    }

    private func sessionEnded(code: Int32) {
        if let report = readStatus() {
            status = report.message
            if report.active {
                error = "Помощник завершился неожиданно. Минимальные обороты могли остаться повышенными. Перезагрузите Mac для возврата к штатным значениям."
                status = "Проверьте управление вентиляторами"
            } else if !report.restored { error = report.message }
        } else if code != 0 {
            error = "Доступ не предоставлен или помощник не запустился. Настройки не применены."
            status = "Штатное управление"
        }
        active = false; authorizing = false; stopping = false; launcher = nil
        if let session { try? FileManager.default.removeItem(at: session) }
        session = nil
        configurations.removeAll()
    }

    private func requestAutomatic() {
        guard session != nil else { return }
        stopping = true
        try? writeLease()
    }

    func stopSession() async {
        guard session != nil else { return }
        requestAutomatic()
        for _ in 0..<50 {
            if session == nil { return }
            if let report = readStatus(), !report.active { status = report.message; break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        active = false
        // Never terminate the helper; it must finish restoring the hardware.
    }

    func stop() async {
        await stopSession()
        polling?.cancel(); await polling?.value; polling = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
