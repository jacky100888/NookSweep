import Foundation

extension CleanupEngine {
    func catalogEntries(warnings: inout [String], manualWorktreeReview: Bool = false) throws -> [AICatalogEntry] {
        guard home.resolvingSymlinksInPath().standardizedFileURL.path == home.path else {
            warnings.append("使用者目錄包含符號連結，未掃描額外 AI 資料")
            return []
        }
        let providers: [(String, () throws -> [AICatalogEntry])] = [
            ("AI 快取", { try AICacheCatalog.candidates(home: self.home) }),
            ("OpenCode", { try OpenCodeCatalog.candidates(home: self.home) }),
            ("Claude 版本", { try ClaudeVersionCatalog.candidates(home: self.home) }),
            ("本機歷史", { try AILegacyHistoryCatalog.candidates(home: self.home) }),
            ("工作副本", { try AIWorktreeCatalog.candidates(home: self.home, manualWorktreeReview: manualWorktreeReview) })
        ]
        var entries: [AICatalogEntry] = []
        for (name, discover) in providers {
            try Task.checkCancellation()
            do { entries += try discover() }
            catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(name)：\(error.localizedDescription)") }
        }
        return entries
    }

    func catalogEntry(for url: URL, manualWorktreeReview: Bool = false) throws -> AICatalogEntry? {
        guard url.standardizedFileURL.pathComponents.starts(with: home.pathComponents) else { return nil }
        if let result = try AICacheCatalog.entry(for: url, home: home) { return result }
        if let result = try OpenCodeCatalog.entry(for: url, home: home) { return result }
        if let result = try ClaudeVersionCatalog.entry(for: url, home: home) { return result }
        if let result = try AILegacyHistoryCatalog.entry(for: url, home: home) { return result }
        return try AIWorktreeCatalog.entry(for: url, home: home, manualWorktreeReview: manualWorktreeReview)
    }

    func inventoryMetadata(for url: URL, category: CleanupCategory,
                           entry: AICatalogEntry?) -> AIItemMetadata? {
        if let metadata = entry?.metadata { return metadata }
        guard let tool = aiToolIdentifier(for: url), category.isAI else { return nil }
        return AIItemMetadata(toolID: tool, kind: category == .aiHistory ? .conversation : .cache,
                              title: url.lastPathComponent)
    }
}
