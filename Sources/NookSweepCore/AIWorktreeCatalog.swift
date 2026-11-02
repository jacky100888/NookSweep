import Foundation

enum AIWorktreeCatalog {
    static func candidates(home: URL) throws -> [AICatalogEntry] {
        let root = home.appendingPathComponent(".codex/worktrees")
        var result: [AICatalogEntry] = []
        for group in try AICatalogFiles.children(root) where AICatalogFiles.isDirectory(group) {
            for repository in try AICatalogFiles.children(group) where AICatalogFiles.isDirectory(repository) {
                if let entry = try entry(for: repository, home: home) { result.append(entry) }
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    static func entry(for url: URL, home: URL) throws -> AICatalogEntry? {
        let url = url.standardizedFileURL
        let root = home.appendingPathComponent(".codex/worktrees").standardizedFileURL
        guard url.deletingLastPathComponent().deletingLastPathComponent().path == root.path,
              AICatalogFiles.exists(url) else { return nil }
        var reason = try AICatalogFiles.blockReason(url)
        var related: [URL] = []
        if reason == nil && !AICatalogFiles.isDirectory(url) { reason = "工作副本不是目錄，保留原狀" }
        if reason == nil {
            do {
                let git = try GitInspection(repository: url)
                reason = try git.preservationReason()
                if reason == nil { related = [git.administrationDirectory] }
            } catch is CancellationError { throw CancellationError() }
            catch { reason = error.localizedDescription }
        }
        return AICatalogEntry(url: url, category: .aiWorktrees,
            metadata: AIItemMetadata(toolID: "codex", kind: .worktree, title: "Codex 工作副本：\(url.lastPathComponent)",
                note: reason == nil ? "已確認乾淨且合併；會連同 Git 管理目錄移至垃圾桶供還原" : "保留工作區與 Git 資料"),
            preservationReason: reason, relatedURLs: related)
    }
}
