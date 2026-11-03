import Foundation

enum OpenCodeCatalog {
    private static let cachePath = ".cache/opencode"
    private static let dataPath = ".local/share/opencode"

    static func candidates(home: URL) throws -> [AICatalogEntry] {
        var entries: [AICatalogEntry] = []
        for path in [cachePath, dataPath + "/log", dataPath + "/tool-output"] {
            for child in try AICatalogFileSystem.children(of: home.appendingPathComponent(path), home: home) {
                if let entry = try entry(for: child, home: home) { entries.append(entry) }
            }
        }
        for name in ["snapshot", "repos"] {
            if let entry = try entry(for: home.appendingPathComponent(dataPath + "/" + name), home: home) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.url.path < $1.url.path }
    }

    static func entry(for url: URL, home: URL) throws -> AICatalogEntry? {
        guard let parts = AICatalogFileSystem.relativeParts(of: url, home: home),
              let canonical = AICatalogFileSystem.canonicalURL(url, home: home),
              let type = try AICatalogFileSystem.type(of: canonical, home: home),
              [.typeDirectory, .typeRegular].contains(type) else { return nil }
        let path = parts.joined(separator: "/")
        if path == dataPath + "/snapshot" {
            return AICatalogEntry(url: canonical, category: .aiHistory,
                metadata: AIItemMetadata(toolID: "opencode", kind: .localHistory, title: "OpenCode 檔案復原快照"),
                preservationReason: "檔案復原用 Git 快照，移除會影響還原能力，請在 OpenCode 中管理")
        }
        if path == dataPath + "/repos" {
            return AICatalogEntry(url: canonical, category: .aiWorktrees,
                metadata: AIItemMetadata(toolID: "opencode", kind: .worktree, title: "OpenCode 儲存庫與工作副本"),
                preservationReason: "可能包含專案原始碼與未提交內容，請在 OpenCode 中管理")
        }
        let parent = parts.dropLast().joined(separator: "/")
        let name = canonical.lastPathComponent
        let title: String
        let note: String
        let known: Bool
        switch parent {
        case cachePath:
            title = "OpenCode 快取：\(name)"
            note = "只整理可重新取得的模型清單；外掛相依套件、安裝狀態與未知內容保留。"
            // 單獨刪除 manifest、version 或模組，可能破壞外掛安裝或觸發整個快取重建。
            known = name == "models.json" && type == .typeRegular
        case dataPath + "/log":
            title = "OpenCode 記錄檔：\(name)"
            note = "診斷記錄可能包含提示文字或工具資訊，整理前請先確認。"
            known = type == .typeRegular && name.range(of:
                #"\A(?:dev|opencode(?:-[A-Za-z0-9._-]+)?|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6})\.log\z"#,
                options: .regularExpression) != nil
        case dataPath + "/tool-output":
            title = "OpenCode 工具輸出：\(name)"
            note = "逾期工具回覆暫存；移除後無法再次讀取這份完整輸出。"
            known = type == .typeRegular && name.range(of: #"\Atool_[0-9a-f]{12}[0-9A-Za-z]{14}\z"#,
                options: .regularExpression) != nil
        default:
            return nil
        }
        return AICatalogEntry(url: canonical, category: .aiCaches,
            metadata: AIItemMetadata(toolID: "opencode", kind: .cache, title: title, note: note),
            preservationReason: known ? nil : "非已確認可獨立重建的快取或暫存格式，保留原狀")
    }
}
