import AppKit
import NookSweepCore
import SwiftUI

@MainActor
final class ApplicationsModel: ObservableObject {
    @Published var applications: [ApplicationRecord] = []
    @Published var warnings: [String] = []
    @Published var selectedID: String?
    @Published var relatedItems: [ApplicationRelatedItem] = []
    @Published var selectedRelatedIDs = Set<String>()
    @Published var query = ""
    @Published var isScanning = false
    @Published var isInspecting = false
    @Published var isRemoving = false
    @Published var showConfirmation = false
    @Published var errorMessage: String?
    @Published var report: ApplicationRemovalReport?
    @Published var status = "正在讀取應用程式…"
    private let engine: ApplicationsEngine
    private var operation: Task<Void, Never>?
    private var inspection: Task<Void, Never>?

    init(engine: ApplicationsEngine = ApplicationsEngine(), automaticallyScans: Bool = true) {
        self.engine = engine
        if automaticallyScans { startScan() }
    }

    var busy: Bool { isScanning || isRemoving }
    var selectedApplication: ApplicationRecord? { applications.first { $0.id == selectedID } }
    var selectedRelatedItems: [ApplicationRelatedItem] {
        relatedItems.filter { $0.isSelectable && selectedRelatedIDs.contains($0.id) }
    }
    var visibleApplications: [ApplicationRecord] {
        applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleID.localizedCaseInsensitiveContains(query) ||
            $0.url.path.localizedCaseInsensitiveContains(query) }
    }
    var canRemove: Bool {
        !busy && !isInspecting && selectedApplication?.isRemovable == true
    }

    func startScan() {
        guard !busy else { return }
        inspection?.cancel()
        selectedID = nil
        relatedItems = []
        selectedRelatedIDs = []
        applications = []
        warnings = []
        report = nil
        errorMessage = nil
        isInspecting = false
        isScanning = true
        status = "正在讀取 App 名稱與版本…"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await engine.scan { [weak self] items, path in
                    Task { @MainActor in
                        guard let self, self.isScanning else { return }
                        self.applications = items
                        self.status = "正在量測：\(path)"
                    }
                }
                applications = result.applications
                warnings = result.warnings
                status = "找到 \(applications.count) 個第三方 App"
            } catch is CancellationError {
                status = "已取消掃描，可重新掃描"
            } catch {
                errorMessage = error.localizedDescription
                status = "掃描未完成"
            }
            isScanning = false
            operation = nil
        }
    }

    func cancelScan() { if isScanning { operation?.cancel() } }

    func inspectSelection() {
        inspection?.cancel()
        relatedItems = []
        selectedRelatedIDs = []
        errorMessage = nil
        showConfirmation = false
        guard let app = selectedApplication, !isScanning else { isInspecting = false; return }
        isInspecting = true
        inspection = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await engine.relatedData(for: app)
                guard !Task.isCancelled, selectedID == app.id else { return }
                relatedItems = items
            } catch is CancellationError { }
            catch {
                guard selectedID == app.id else { return }
                errorMessage = error.localizedDescription
            }
            if selectedID == app.id { isInspecting = false }
        }
    }

    func removeSelected(terminationMode: ApplicationTerminationMode = .none) {
        showConfirmation = false
        guard canRemove, let app = selectedApplication else { return }
        let selected = selectedRelatedItems
        isRemoving = true
        errorMessage = nil
        report = nil
        status = terminationMode == .none ? "正在重新驗證並移到垃圾桶…" : "正在結束 App，完成後重新驗證並移到垃圾桶…"
        operation = Task { [weak self] in
            guard let self else { return }
            let result = await engine.trash(app, relatedItems: selected, terminationMode: terminationMode)
            report = result
            if result.results.contains(where: { $0.originalURL == app.url && $0.succeeded }) {
                applications.removeAll { $0.id == app.id }
                selectedID = nil
                relatedItems = []
                selectedRelatedIDs = []
            }
            let failures = result.results.filter { !$0.succeeded }.count
            status = "已移到垃圾桶 \(result.movedCount) 項" +
                (failures == 0 ? "" : "；\(failures) 項保留，請查看結果")
            isRemoving = false
            operation = nil
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func openAppManagementSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") else { return }
        if !NSWorkspace.shared.open(url),
           let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(privacy)
        }
    }
}
