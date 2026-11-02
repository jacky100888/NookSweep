import Foundation

struct ScanRoot: Sendable {
    let url: URL
    let category: CleanupCategory
}

extension CleanupEngine {
    var roots: [ScanRoot] {
        [
            ("Library/Caches", CleanupCategory.caches),
            ("Library/Logs", .logs),
            ("Library/Developer/Xcode/DerivedData", .developer),
            (".npm/_cacache", .developer),
            (".cache/pip", .developer),
            (".cache/uv", .developer),
            (".gradle/caches", .developer)
        ].map { ScanRoot(url: home.appendingPathComponent($0.0), category: $0.1) }
    }

    func validatedRoot(for url: URL, knownEntry: AICatalogEntry? = nil) throws -> ScanRoot {
        let path = url.standardizedFileURL
        let entry = try knownEntry ?? catalogEntry(for: url)
        // macOS 的 /var 與 /private/var 會正規化成同一路徑，須比較正規化後的實體位置。
        guard let root = entry.map({ ScanRoot(url: $0.url.deletingLastPathComponent(), category: $0.category) }) ??
            (roots + aiCacheRoots).first(where: {
            $0.url.path == path.deletingLastPathComponent().path
        }) ?? aiHistoryRoot(for: url),
              url.resolvingSymlinksInPath().standardizedFileURL.path == path.path,
              root.url.resolvingSymlinksInPath().path == root.url.path else {
            throw CleanupError.refused("路徑不在允許範圍，或包含符號連結")
        }
        if root.category == .caches, aiToolIdentifier(for: path) != nil {
            return ScanRoot(url: root.url, category: .aiCaches)
        }
        if entry == nil, root.category == .aiCaches, try !acceptsAICacheFile(path, root: root.url) {
            throw CleanupError.refused("非已知的 AI 暫存格式，保留原狀")
        }
        return root
    }

    func state(for url: URL, category: CleanupCategory, bytes: Int64, modified: Date,
               runningBundleIDs: Set<String>, runningAITools: Set<String> = [],
               knownEntry: AICatalogEntry? = nil, manualWorktreeReview: Bool = false) throws -> ItemState {
        let name = url.lastPathComponent.lowercased()
        let entry = try knownEntry ?? catalogEntry(for: url, manualWorktreeReview: manualWorktreeReview)
        if let reason = entry?.preservationReason { return .blocked(reason) }
        if let tool = entry?.metadata.toolID ?? aiToolIdentifier(for: url) {
            if category == .aiHistory, tool == "codex" {
                return .blocked("Codex 對話受資料庫索引管理，請在 Codex 中管理對話")
            }
            if runningAITools.contains(tool), !(category == .aiWorktrees && manualWorktreeReview) { return .running }
            if category != .aiWorktrees, let reason = try aiContentBlockReason(url) { return .blocked(reason) }
        }
        if [".gitignore", ".ds_store", "cachedir.tag", "lock"].contains(name) ||
            name.hasSuffix(".lock") || name.hasSuffix(".lck") {
            return .blocked("快取標記或鎖定檔，保留原狀")
        }
        let protected = ["com.apple.", "systemsettings", "systempreferences", "controlcenter",
                         "backgroundtaskmanagement", "loginitems", "sharedfilelist", "tcc",
                         "coreaudio", "coreaudiod", "macsweep", "nooksweep"]
        if protected.contains(where: name.contains) {
            return .blocked("系統或受保護項目，保留原狀")
        }
        if runningBundleIDs.contains(where: {
            name == $0.lowercased() || name.hasPrefix($0.lowercased() + ".")
        }) {
            return .running
        }
        if bytes == 0 { return .blocked("沒有可回收的檔案內容") }
        if category == .aiWorktrees && manualWorktreeReview { return .eligible }
        let cutoff = Date().addingTimeInterval(-Double(category.minimumDays) * 86400)
        return modified > cutoff ? .recent : .eligible
    }
}
