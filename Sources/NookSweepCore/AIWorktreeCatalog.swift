import Foundation

enum AIWorktreeCatalog {
    static func candidates(home: URL, manualWorktreeReview: Bool = false) throws -> [AICatalogEntry] {
        let root = home.appendingPathComponent(".codex/worktrees")
        var result: [AICatalogEntry] = []
        for group in try AICatalogFiles.children(root) where AICatalogFiles.isDirectory(group) {
            for repository in try AICatalogFiles.children(group) where AICatalogFiles.isDirectory(repository) {
                if let entry = try entry(for: repository, home: home, manualWorktreeReview: manualWorktreeReview) {
                    result.append(entry)
                }
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    static func entry(for url: URL, home: URL, manualWorktreeReview: Bool = false) throws -> AICatalogEntry? {
        let url = url.standardizedFileURL
        let root = home.appendingPathComponent(".codex/worktrees").standardizedFileURL
        guard url.deletingLastPathComponent().deletingLastPathComponent().path == root.path,
              AICatalogFiles.exists(url) else { return nil }
        var reason = try AICatalogFiles.blockReason(url)
        var related: [URL] = []
        var review: AIWorktreeReview?
        if reason == nil && !AICatalogFiles.isDirectory(url) { reason = "工作副本不是目錄，保留原狀" }
        if reason == nil {
            do {
                let git = try GitInspection(repository: url)
                review = try git.review()
                reason = manualWorktreeReview ? nil : review?.conservativeReason
                if reason == nil { related = [git.administrationDirectory] }
            } catch is CancellationError { throw CancellationError() }
            catch { reason = error.localizedDescription }
        }
        return AICatalogEntry(url: url, category: .aiWorktrees,
            metadata: AIItemMetadata(toolID: "codex", kind: .worktree, title: "Codex 工作副本：\(url.lastPathComponent)",
                note: review?.summary ?? "保留工作區與 Git 資料", worktreeReview: review),
            preservationReason: reason, relatedURLs: related)
    }
}
