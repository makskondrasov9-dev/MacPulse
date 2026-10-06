import Foundation
import ServiceManagement
import Testing
@testable import MonitorCore

@MainActor
private final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var fail = false
    var registrations = 0
    var removals = 0
    func register() throws {
        registrations += 1
        if fail { throw NSError(domain: "LoginItemTest", code: 1) }
        status = .enabled
    }
    func unregister() async throws {
        removals += 1
        if fail { throw NSError(domain: "LoginItemTest", code: 2) }
        status = .notRegistered
    }
}

@MainActor
struct LoginItemTests {
    @Test func toggleReflectsSystemStateAndExternalChanges() async {
        let fake = FakeLoginItem()
        let service = LoginItemService(service: fake)
        #expect(!service.isEnabled)
        await service.setEnabled(true)
        #expect(service.isEnabled)
        #expect(fake.registrations == 1)
        await service.setEnabled(true)
        #expect(fake.registrations == 1)
        fake.status = .requiresApproval
        service.refresh()
        #expect(!service.isEnabled)
        await service.setEnabled(false)
        #expect(service.status == .notRegistered)
        #expect(fake.removals == 1)
        fake.status = .enabled
        service.refresh()
        #expect(service.isEnabled)
        await service.setEnabled(false)
        #expect(!service.isEnabled)
    }

    @Test func errorsDoNotPretendThatSystemSettingChanged() async {
        let fake = FakeLoginItem()
        fake.fail = true
        let service = LoginItemService(service: fake)
        await service.setEnabled(true)
        #expect(!service.isEnabled)
        #expect(service.errorMessage != nil)
        #expect(!service.isUpdating)
        fake.status = .enabled
        service.refresh()
        await service.setEnabled(false)
        #expect(service.isEnabled)
        #expect(service.errorMessage != nil)
        fake.fail = false
        await service.setEnabled(false)
        #expect(!service.isEnabled)
        #expect(service.errorMessage == nil)
    }
}
