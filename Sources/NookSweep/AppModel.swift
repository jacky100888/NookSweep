import AppKit
import NookSweepCore
import SwiftUI

enum DeveloperMode: Hashable {
    case caches, ai
}

enum SidebarScope: Hashable {
    case status
    case applications
    case all
    case category(CleanupCategory)
    var category: CleanupCategory? {
        if case .category(let value) = self { value } else { nil }
    }
    var title: String {
        switch self {
        case .status: "即時狀態"
        case .applications: "軟體移除"
        case .all: "智慧清理"
        case .category(let category): category.rawValue
        }
    }
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
    @Published private(set) var developerMode: DeveloperMode = .caches
    @Published var aiCategory: CleanupCategory?
    @Published var historyAgeDays = 0
    @Published var sortOrder = [KeyPathComparator(\CleanupItem.bytes, order: .reverse)]
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
    @Published private(set) var manualWorktreeReview = false
    private let engine: CleanupEngine
    private var operation: Task<Void, Never>?
    private var resultIsAIOnly = false

    var busy: Bool { isScanning || isCleaning }
    var items: [CleanupItem] { result?.items ?? [] }
    var scopedItems: [CleanupItem] {
        items.filter {
            (!isAIScope || $0.category.isAI) &&
            (activeCategory == nil || $0.category == activeCategory)
        }
    }
    var activeCategory: CleanupCategory? { isAIScope ? aiCategory : scope?.category }
    var eligibleItems: [CleanupItem] { items.filter(\.isEligible) }
    var selectedItems: [CleanupItem] { eligibleItems.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var scopeEligibleItems: [CleanupItem] { scopedItems.filter(\.isEligible) }
    var scopeEligibleBytes: Int64 { scopeEligibleItems.reduce(0) { $0 + $1.bytes } }
    var selectedHistoryCount: Int { selectedItems.filter(\.isAIHistory).count }
    var selectedWorktreeCount: Int { selectedItems.filter { $0.category == .aiWorktrees }.count }
    var isAIScope: Bool { scope?.category == .developer && developerMode == .ai }
    var focusedItem: CleanupItem? { items.first { $0.id == focusedID } }
    var dateSortOrder: SortOrder? {
        sortOrder.first?.keyPath == \CleanupItem.modified ? sortOrder.first?.order : nil
    }
    var sortDescription: String {
        guard let first = sortOrder.first else { return "掃描順序" }
        if first.keyPath == \CleanupItem.modified {
            return first.order == .forward ? "最近修改由舊到新" : "最近修改由新到舊"
        }
        if first.keyPath == \CleanupItem.bytes {
            return first.order == .reverse ? "大小由大到小" : "大小由小到大"
        }
        return "掃描順序"
    }
    var visibleItems: [CleanupItem] {
        let cutoff: Date? = isAIScope && activeCategory == .aiHistory && historyAgeDays > 0
            ? (scannedAt ?? Date()).addingTimeInterval(-Double(historyAgeDays) * 86400) : nil
        let filtered = scopedItems.filter { item in
            (!eligibleOnly || item.isEligible) &&
            (cutoff.map { item.measurementAvailable && item.modified <= $0 } ?? true) &&
            (query.isEmpty || item.url.path.localizedCaseInsensitiveContains(query) ||
             item.name.localizedCaseInsensitiveContains(query) ||
             item.aiToolName?.localizedCaseInsensitiveContains(query) == true)
        }
        let sorted = filtered.sorted(using: sortOrder + [KeyPathComparator(\CleanupItem.id)])
        return dateSortOrder == nil ? sorted :
            sorted.filter(\.measurementAvailable) + sorted.filter { !$0.measurementAvailable }
    }
    var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    init(engine: CleanupEngine = CleanupEngine()) {
        self.engine = engine
        refreshDisk()
    }

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
        resultIsAIOnly = false
        scannedAt = nil
        inspectedCount = 0
        progressPath = "準備掃描…"
        status = "正在掃描"
        isScanning = true
        let running = runningBundleIDs
        let runningTools = AIProcessActivity.runningToolIDs(bundleIdentifiers: running)
        let includeHistory = includeAIHistory
        let manualReview = manualWorktreeReview
        let aiOnly = isAIScope
        let categories = aiOnly ? Set(CleanupCategory.allCases.filter(\.isAI)) : nil
        operation = Task {
            do {
                let value = try await engine.scan(includeAIHistory: includeHistory,
                    inventoryAIHistory: true, manualWorktreeReview: manualReview, categories: categories,
                    runningBundleIDs: running, runningAITools: runningTools) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.isScanning else { return }
                        self.progressPath = value.path
                        self.inspectedCount = value.fileCount
                    }
                }
                if aiOnly && !isAIScope {
                    status = "已切換清理範圍，請重新掃描"
                } else {
                    result = value
                    resultIsAIOnly = aiOnly
                    inspectedCount = value.inspectedCount
                    scannedAt = Date()
                    status = "掃描完成 · \(value.inspectedCount.formatted()) 個檔案"
                }
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

    var hiddenSelectionCount: Int {
        let visibleIDs = Set(visibleItems.map(\.id))
        return selectedItems.filter { !visibleIDs.contains($0.id) }.count
    }

    func selectVisibleAIGroup(toolID: String, kind: AIDataKind? = nil) {
        selected.formUnion(visibleItems.filter {
            $0.category.isAI && $0.isEligible && ($0.aiToolID ?? "unknown") == toolID &&
                (kind == nil || $0.aiDataKind == kind)
        }.map(\.id))
    }

    func sortByDate() {
        sortOrder = [KeyPathComparator(\CleanupItem.modified, order: dateSortOrder == .forward ? .reverse : .forward)]
    }

    func sortBySize() {
        let ascending = sortOrder.first?.keyPath == \CleanupItem.bytes && sortOrder.first?.order == .reverse
        sortOrder = [KeyPathComparator(\CleanupItem.bytes, order: ascending ? .forward : .reverse)]
    }

    func setDeveloperMode(_ mode: DeveloperMode) {
        guard !busy, developerMode != mode else { return }
        let rescan = result != nil
        developerMode = mode
        result = nil
        resultIsAIOnly = false
        selected.removeAll()
        focusedID = nil
        scannedAt = nil
        showDetails = false
        eligibleOnly = !isAIScope
        status = "已切換清理範圍，請重新掃描"
        if rescan { startScan() }
    }

    func setIncludeAIHistory(_ enabled: Bool) {
        guard !busy else { return }
        let rescan = result != nil && isAIScope
        includeAIHistory = enabled
        result = nil
        selected.removeAll()
        focusedID = nil
        status = "清理權限已調整，請重新掃描"
        if rescan { startScan() }
    }

    func scopeDidChange() {
        focusedID = nil
        showDetails = false
        eligibleOnly = !isAIScope
        if resultIsAIOnly && !isAIScope {
            result = nil
            resultIsAIOnly = false
            selected.removeAll()
            scannedAt = nil
            status = "已切換清理範圍，請重新掃描"
        }
    }

    func setManualWorktreeReview(_ enabled: Bool) {
        guard !busy else { return }
        let rescan = result != nil && isAIScope
        manualWorktreeReview = enabled
        result = nil
        selected.removeAll()
        focusedID = nil
        status = "工作副本整理模式已調整，請重新掃描"
        if rescan { startScan() }
    }

    var cleanupWarning: String {
        var warnings = ["共 \(formatBytes(selectedBytes))，請先結束相關應用程式、AI 工具與建置工作。"]
        if selectedHistoryCount > 0 {
            warnings.append("包含 \(selectedHistoryCount) 筆舊對話／本機歷史，會失去對話上下文或歷史還原能力。")
        }
        if selectedWorktreeCount > 0 {
            warnings.append("包含 \(selectedWorktreeCount) 個工作副本，會連同未提交、未追蹤、已忽略檔案及 Git 登記移到垃圾桶。請先停止使用這些工作副本的 AI 工作、終端機與編輯器；舊對話的工作路徑可能需要還原。")
            if manualWorktreeReview {
                warnings.append("手動整理可包含近期或未合併的工作。會在原儲存庫建立 Git 保留參照以保護提交；參照會留存，不會自動刪除。還原時須將工作區及 Git 管理目錄一起放回原位置，並保留原儲存庫。")
            }
        }
        warnings.append("會重新驗證後移到垃圾桶。關聯項目失敗時會嘗試回復；清空垃圾桶後才會釋放磁碟空間。")
        return warnings.joined(separator: "\n\n")
    }

    func cleanSelected(confirmedAIHistory: Bool = false, confirmedAIWorktrees: Bool = false) {
        guard !busy, !selectedItems.isEmpty else { return }
        guard selectedHistoryCount == 0 || (includeAIHistory && confirmedAIHistory) else { return }
        guard selectedWorktreeCount == 0 || confirmedAIWorktrees else { return }
        let candidates = selectedItems
        let running = runningBundleIDs
        let runningTools = AIProcessActivity.runningToolIDs(bundleIdentifiers: running)
        let manualReview = manualWorktreeReview
        isCleaning = true
        operation = Task {
            let value = await engine.trash(candidates, runningBundleIDs: running,
                runningAITools: runningTools, allowAIHistory: confirmedAIHistory,
                allowAIWorktrees: confirmedAIWorktrees, manualWorktreeReview: manualReview)
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
