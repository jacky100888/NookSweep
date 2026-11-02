import Foundation

extension CleanupEngine {
    public func scan(
        includeAIHistory: Bool = false,
        inventoryAIHistory: Bool = false,
        manualWorktreeReview: Bool = false,
        categories: Set<CleanupCategory>? = nil,
        runningBundleIDs: Set<String> = [],
        runningAITools: Set<String> = [],
        progress: @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> ScanResult {
        try Task.checkCancellation()
        let manager = FileManager.default
        var items: [CleanupItem] = []
        var warnings: [String] = []
        var totalFiles = 0
        var seen = Set<String>()
        let catalog = try catalogEntries(warnings: &warnings, manualWorktreeReview: manualWorktreeReview)
        func inspect(_ url: URL, entry: AICatalogEntry? = nil) throws {
            try Task.checkCancellation()
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            progress(ScanProgress(path: url.path, fileCount: totalFiles))
            do {
                let root = try validatedRoot(for: url, knownEntry: entry)
                guard categories == nil || categories?.contains(root.category) == true else { return }
                guard root.category != .aiHistory || includeAIHistory || inventoryAIHistory else { return }
                let base = totalFiles
                let group = try measureGroup(url, relatedURLs: entry?.relatedURLs ?? []) {
                    progress(ScanProgress(path: url.path, fileCount: base + $0))
                }
                let value = group.total
                totalFiles += value.fileCount
                var state = try state(for: url, category: root.category,
                                      bytes: value.bytes, modified: value.modified,
                                      runningBundleIDs: runningBundleIDs, runningAITools: runningAITools,
                    knownEntry: entry, manualWorktreeReview: manualWorktreeReview)
                if root.category == .aiHistory, !includeAIHistory, state == .eligible {
                    state = .blocked("已保留舊對話／歷史，開啟允許整理後重新掃描才可選取")
                }
                items.append(CleanupItem(url: url, category: root.category,
                    bytes: value.bytes, fileCount: value.fileCount, modified: value.modified,
                    state: state, fingerprint: value.fingerprint,
                    aiMetadata: inventoryMetadata(for: url, category: root.category, entry: entry),
                    relatedURLs: entry?.relatedURLs ?? []))
            } catch is CancellationError { throw CancellationError() }
            catch {
                warnings.append("\(url.path)：\(error.localizedDescription)")
                if let entry, categories == nil || categories?.contains(entry.category) == true,
                   entry.category != .aiHistory || includeAIHistory || inventoryAIHistory {
                    items.append(CleanupItem(url: url, category: entry.category, bytes: 0, fileCount: 0,
                        modified: .distantPast, state: .blocked("無法完整驗證：\(error.localizedDescription)"),
                        fingerprint: "", aiMetadata: entry.metadata, relatedURLs: entry.relatedURLs))
                }
            }
        }
        for entry in catalog {
            try inspect(entry.url, entry: entry)
        }
        for root in roots + aiCacheRoots {
            try Task.checkCancellation()
            if let categories, !categories.contains(root.category), root.url.lastPathComponent != "Caches" { continue }
            guard manager.fileExists(atPath: root.url.path) else { continue }
            do {
                guard root.url.resolvingSymlinksInPath().path == root.url.path else {
                    throw CleanupError.refused("掃描根目錄包含符號連結，已略過")
                }
                let children = try manager.contentsOfDirectory(at: root.url,
                    includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                for url in children {
                    if AICacheCatalog.replacesGenericCache(url, home: home), catalog.contains(where: {
                        $0.url.standardizedFileURL.pathComponents.starts(with: url.standardizedFileURL.pathComponents)
                    }) { continue }
                    try inspect(url)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(root.url.path)：\(error.localizedDescription)") }
        }
        if (includeAIHistory || inventoryAIHistory), categories == nil || categories?.contains(.aiHistory) == true {
            for url in try aiHistoryCandidates(warnings: &warnings) { try inspect(url) }
        }
        return ScanResult(items: items.sorted { $0.bytes > $1.bytes },
                          warnings: warnings, inspectedCount: totalFiles)
    }
}
