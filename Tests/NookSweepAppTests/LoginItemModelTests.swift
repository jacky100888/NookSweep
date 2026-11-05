import Foundation
import ServiceManagement
import Testing
@testable import NookSweep

@MainActor
private final class LoginServiceFixture {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var failure: Error?

    func model() -> LoginItemModel {
        LoginItemModel(status: { self.status }, register: {
            self.registrations += 1
            if let failure = self.failure { throw failure }
            self.status = .enabled
        }, unregister: {
            self.removals += 1
            if let failure = self.failure { throw failure }
            self.status = .notRegistered
        })
    }
}

@Test @MainActor func loginItemStartsFromSystemStateWithoutChangingRegistration() {
    let service = LoginServiceFixture()
    let model = service.model()
    #expect(!model.isRegistered)
    #expect(service.registrations == 0 && service.removals == 0)
    service.status = .enabled
    model.refresh()
    #expect(model.isRegistered)
    #expect(service.registrations == 0 && service.removals == 0)
}

@Test @MainActor func loginItemToggleRegistersAndUnregistersTheMainApp() {
    let service = LoginServiceFixture()
    let model = service.model()
    model.setEnabled(true)
    #expect(model.status == .enabled)
    #expect(model.isRegistered)
    #expect(model.lastError == nil)
    model.setEnabled(false)
    #expect(model.status == .notRegistered)
    #expect(!model.isRegistered)
    #expect(service.registrations == 1 && service.removals == 1)
}

@Test @MainActor func loginItemPendingApprovalRemainsRegisteredAndExplainsTheRequiredAction() {
    let service = LoginServiceFixture()
    service.status = .requiresApproval
    let model = service.model()
    #expect(model.isRegistered)
    #expect(model.needsApproval)
    #expect(model.statusText.contains("系統設定"))
    model.setEnabled(false)
    #expect(!model.isRegistered)
    #expect(service.removals == 1)
}

@Test @MainActor func loginItemRegistrationFailureDoesNotShowAnEnabledToggle() {
    let service = LoginServiceFixture()
    service.failure = NSError(domain: "LoginItemTest", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "系統拒絕測試註冊"])
    let model = service.model()
    model.setEnabled(true)
    #expect(!model.isRegistered)
    #expect(model.lastError?.contains("系統拒絕測試註冊") == true)
    #expect(service.registrations == 1)
}

@Test @MainActor func loginItemRemovalFailureKeepsTheActualSystemState() {
    let service = LoginServiceFixture()
    service.status = .enabled
    service.failure = NSError(domain: "LoginItemTest", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "系統拒絕測試取消"])
    let model = service.model()
    model.setEnabled(false)
    #expect(model.isRegistered)
    #expect(model.lastError?.contains("系統拒絕測試取消") == true)
    #expect(service.removals == 1)
}
