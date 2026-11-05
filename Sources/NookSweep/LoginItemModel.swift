import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(status: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        readStatus = status
        self.register = register
        self.unregister = unregister
        refresh()
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var statusText: String {
        switch status {
        case .enabled: "已開啟，下次登入時會自動啟動。"
        case .notRegistered: "已關閉，登入時不會自動啟動。"
        case .requiresApproval: "尚未獲准啟動，請至系統設定允許 NookSweep。"
        case .notFound: "系統找不到 App，請先放入「應用程式」後重新開啟。"
        @unknown default: "無法確認登入啟動狀態，請查看系統設定。"
        }
    }

    func refresh() { status = readStatus() }
    func setEnabled(_ enabled: Bool) {
        lastError = nil
        guard enabled != isRegistered else { return }
        do {
            if enabled { try register() }
            else { try unregister() }
        } catch {
            lastError = "上次變更失敗：\(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
