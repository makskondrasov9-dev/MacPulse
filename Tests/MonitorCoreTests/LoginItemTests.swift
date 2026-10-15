import Foundation
import Darwin
import ServiceManagement
import Testing
@testable import MonitorCore

private actor FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var fail = false
    var registrations = 0
    var removals = 0
    var delay: Duration = .zero
    var calledOnMainThread = false
    func configure(status: SMAppService.Status? = nil, fail: Bool = false, delay: Duration = .zero) {
        if let status { self.status = status }; self.fail = fail; self.delay = delay
    }
    func currentStatus() -> SMAppService.Status { status }
    func register() async throws {
        calledOnMainThread = pthread_main_np() != 0
        registrations += 1
        blockLikeServiceManagement()
        if fail { throw NSError(domain: "LoginItemTest", code: 1) }
        status = .enabled
    }
    private func blockLikeServiceManagement() {
        let parts = delay.components
        Thread.sleep(forTimeInterval: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
    func unregister() async throws {
        calledOnMainThread = pthread_main_np() != 0
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
        #expect(await fake.registrations == 1)
        await service.setEnabled(true)
        #expect(await fake.registrations == 1)
        await fake.configure(status: .requiresApproval)
        await service.refresh()
        #expect(!service.isEnabled)
        await service.setEnabled(false)
        #expect(service.status == .notRegistered)
        #expect(await fake.removals == 1)
        await fake.configure(status: .enabled)
        await service.refresh()
        #expect(service.isEnabled)
        await service.setEnabled(false)
        #expect(!service.isEnabled)
        #expect(await !fake.calledOnMainThread)
    }

    @Test func errorsDoNotPretendThatSystemSettingChanged() async {
        let fake = FakeLoginItem()
        await fake.configure(fail: true)
        let service = LoginItemService(service: fake)
        await service.setEnabled(true)
        #expect(!service.isEnabled)
        #expect(service.errorMessage != nil)
        #expect(!service.isUpdating)
        await fake.configure(status: .enabled, fail: true)
        await service.refresh()
        await service.setEnabled(false)
        #expect(service.isEnabled)
        #expect(service.errorMessage != nil)
        await fake.configure()
        await service.setEnabled(false)
        #expect(!service.isEnabled)
        #expect(service.errorMessage == nil)
    }

    @Test func timeoutKeepsUIResponsiveAndPreventsOverlappingMutations() async throws {
        let fake = FakeLoginItem()
        await fake.configure(delay: .milliseconds(150))
        let service = LoginItemService(service: fake, timeout: .milliseconds(20))
        await service.setEnabled(true)
        #expect(service.hasPendingOperation)
        #expect(!service.isUpdating)
        #expect(service.errorMessage != nil)
        #expect(!service.isEnabled)
        await service.setEnabled(false)
        #expect(await fake.removals == 0)
        // The late OS reply must reconcile the real state, rather than undoing it.
        for _ in 0..<100 where service.hasPendingOperation { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!service.hasPendingOperation)
        #expect(service.isEnabled)
        #expect(service.errorMessage == nil)
        #expect(await fake.registrations == 1)
        #expect(await !fake.calledOnMainThread)
    }
}
