import Combine
import Foundation
import ServiceManagement

protocol LoginItemManaging: Sendable {
    func currentStatus() async -> SMAppService.Status
    func register() async throws
    func unregister() async throws
}

private struct MainAppLoginItem: LoginItemManaging {
    func currentStatus() async -> SMAppService.Status { SMAppService.mainApp.status }
    func register() async throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

/// Only presentation state is main-actor isolated. ServiceManagement can block in XPC.
@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var status: SMAppService.Status = .notRegistered
    @Published public private(set) var isUpdating = false
    @Published public private(set) var hasPendingOperation = false
    @Published public private(set) var errorMessage: String?
    private let service: any LoginItemManaging
    private let timeout: Duration
    private var completion: CheckedContinuation<Void, Never>?
    private var timer: Task<Void, Never>?

    public convenience init() { self.init(service: MainAppLoginItem()) }
    init(service: any LoginItemManaging, timeout: Duration = .seconds(10)) {
        self.service = service
        self.timeout = timeout
    }
    public var isEnabled: Bool { status == .enabled }
    public func refresh() async { await perform(nil) }
    public func setEnabled(_ enabled: Bool) async {
        if enabled && status == .requiresApproval { openSettings(); return }
        await perform(enabled)
    }
    private func perform(_ enabled: Bool?) async {
        guard !hasPendingOperation else { return }
        hasPendingOperation = true
        isUpdating = true
        errorMessage = nil
        let service = service
        await withCheckedContinuation { continuation in
            completion = continuation
            timer = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                guard let self else { return }
                self.isUpdating = false
                self.errorMessage = L("Login item request is taking longer than expected. Check System Settings; MacPulse will update when macOS responds.")
                self.resumeWaitingCaller()
                // A timed-out XPC call cannot be safely cancelled. Keep the single-flight
                // guard until it actually returns; never start an overlapping mutation.
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                var message: String?
                let before = await service.currentStatus()
                do {
                    if let enabled {
                        if enabled && before != .enabled && before != .requiresApproval {
                            try await service.register()
                        } else if !enabled && before != .notRegistered {
                            try await service.unregister()
                        }
                    }
                } catch { message = error.localizedDescription }
                let current = await service.currentStatus()
                await self?.finished(status: current, error: message)
            }
        }
    }
    private func finished(status: SMAppService.Status, error: String?) {
        timer?.cancel()
        timer = nil
        self.status = status
        errorMessage = error
        isUpdating = false
        hasPendingOperation = false
        resumeWaitingCaller()
    }
    private func resumeWaitingCaller() {
        completion?.resume()
        completion = nil
    }
    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
