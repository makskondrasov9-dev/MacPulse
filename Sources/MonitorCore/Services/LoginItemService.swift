import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
private struct MainAppLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

/// The OS is the source of truth; there is no separate stored toggle that can drift.
@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var status: SMAppService.Status
    @Published public private(set) var isUpdating = false
    @Published public private(set) var errorMessage: String?
    private let service: any LoginItemManaging

    public convenience init() { self.init(service: MainAppLoginItem()) }
    init(service: any LoginItemManaging) {
        self.service = service
        status = service.status
    }
    public var isEnabled: Bool { status == .enabled }
    public func refresh() { status = service.status }
    public func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { refresh(); isUpdating = false }
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered { try await service.unregister() }
        } catch { errorMessage = error.localizedDescription }
    }
    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
