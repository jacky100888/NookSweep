import AppKit
import NookSweepCore
import SwiftUI

enum SidebarScope: Hashable {
    case status
    case all
    case category(CleanupCategory)
    var category: CleanupCategory? {
        if case .category(let value) = self { value } else { nil }
    }
    var title: String { self == .status ? "即時狀態" : category?.rawValue ?? "智慧清理" }
}

struct DiskInfo {
    let total: Int64
    let available: Int64
    var used: Int64 { max(0, total - available) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var scope: SidebarScope? = .status
    @Published var result: ScanResult?
    @Published var selected = Set<String>()
    @Published var focusedID: String?
    @Published var query = ""
    @Published var eligibleOnly = true
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var progressPath = ""
    @Published var inspectedCount = 0
    @Published var status = "尚未掃描"
    @Published var disk: DiskInfo?
    @Published var report: CleanupReport?
    @Published var showReport = false
    @Published var scannedAt: Date?
    @Published var showWarnings = false
    @Published var confirmCleanup = false
    @Published var showDetails = false
    @Published private(set) var includeAIHistory = false
    private let engine = CleanupEngine()
    private var operation: Task<Void, Never>?

    var busy: Bool { isScanning || isCleaning }
    var items: [CleanupItem] { result?.items ?? [] }
    var eligibleItems: [CleanupItem] { items.filter(\.isEligible) }
    var selectedItems: [CleanupItem] { eligibleItems.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var eligibleBytes: Int64 { eligibleItems.reduce(0) { $0 + $1.bytes } }
    var selectedHistoryCount: Int { selectedItems.filter(\.isAIHistory).count }
    var focusedItem: CleanupItem? { items.first { $0.id == focusedID } }
    var visibleItems: [CleanupItem] {
        items.filter {
            ((scope ?? .all).category == nil || $0.category == scope?.category) &&
            (!eligibleOnly || $0.isEligible) &&
            (query.isEmpty || $0.url.path.localizedCaseInsensitiveContains(query))
        }
    }
    var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    init() { refreshDisk() }

    func refreshDisk() {
        do {
            let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let total = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacityForImportantUsage {
                disk = DiskInfo(total: Int64(total), available: available)
            }
        } catch { disk = nil }
    }

    func startScan() {
        guard !busy else { return }
        selected.removeAll()
        focusedID = nil
        result = nil
        scannedAt = nil
        inspectedCount = 0
        progressPath = "準備掃描…"
        status = "正在掃描"
        isScanning = true
        let running = runningBundleIDs
        let runningTools = AIProcessActivity.runningToolIDs(bundleIdentifiers: running)
        let includeHistory = includeAIHistory
        operation = Task {
            do {
                let value = try await engine.scan(includeAIHistory: includeHistory,
                    runningBundleIDs: running, runningAITools: runningTools) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.isScanning else { return }
                        self.progressPath = value.path
                        self.inspectedCount = value.fileCount
                    }
                }
                result = value
                inspectedCount = value.inspectedCount
                scannedAt = Date()
                status = "掃描完成 · \(value.inspectedCount.formatted()) 個檔案"
            } catch is CancellationError {
                status = "已取消掃描，可隨時重新開始"
            } catch { status = "掃描失敗：\(error.localizedDescription)" }
            isScanning = false
            operation = nil
            refreshDisk()
        }
    }

    func cancelScan() { operation?.cancel() }

    func selectVisible() {
        selected.formUnion(visibleItems.filter(\.isEligible).map(\.id))
    }

    func setIncludeAIHistory(_ enabled: Bool) {
        guard !busy else { return }
        includeAIHistory = enabled
        result = nil
        selected.removeAll()
        focusedID = nil
        if !enabled, scope == .category(.aiHistory) { scope = .category(.aiCaches) }
        status = "掃描範圍已調整，請重新掃描"
    }

    func cleanSelected(confirmedAIHistory: Bool = false) {
        guard !busy, !selectedItems.isEmpty else { return }
        guard selectedHistoryCount == 0 || (includeAIHistory && confirmedAIHistory) else { return }
        let candidates = selectedItems
        let running = runningBundleIDs
        let runningTools = AIProcessActivity.runningToolIDs(bundleIdentifiers: running)
        isCleaning = true
        operation = Task {
            let value = await engine.trash(candidates, runningBundleIDs: running,
                runningAITools: runningTools, allowAIHistory: confirmedAIHistory)
            let movedIDs = Set(value.moved.map { $0.originalURL.path })
            if let old = result {
                result = ScanResult(items: old.items.filter { !movedIDs.contains($0.id) },
                                    warnings: old.warnings, inspectedCount: old.inspectedCount)
            }
            selected.removeAll()
            focusedID = nil
            report = value
            showReport = true
            isCleaning = false
            operation = nil
            status = "已移到垃圾桶 \(value.moved.count) 項 · \(formatBytes(value.bytes))"
            refreshDisk()
        }
    }

    func reveal(_ item: CleanupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}

func formatBytes(_ value: Int64) -> String {
    value == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
