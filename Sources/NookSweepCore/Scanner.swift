import Foundation

extension CleanupEngine {
    public func scan(
        includeAIHistory: Bool = false,
        runningBundleIDs: Set<String> = [],
        runningAITools: Set<String> = [],
        progress: @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> ScanResult {
        try Task.checkCancellation()
        let manager = FileManager.default
        var items: [CleanupItem] = []
        var warnings: [String] = []
        var totalFiles = 0
        func inspect(_ url: URL) throws {
            try Task.checkCancellation()
            progress(ScanProgress(path: url.path, fileCount: totalFiles))
            do {
                let root = try validatedRoot(for: url)
                let base = totalFiles
                let value = try measure(url) {
                    progress(ScanProgress(path: url.path, fileCount: base + $0))
                }
                totalFiles += value.fileCount
                let state = try state(for: url, category: root.category,
                                      bytes: value.bytes, modified: value.modified,
                                      runningBundleIDs: runningBundleIDs, runningAITools: runningAITools)
                items.append(CleanupItem(url: url, category: root.category,
                    bytes: value.bytes, fileCount: value.fileCount, modified: value.modified,
                    state: state, fingerprint: value.fingerprint))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(url.path)：\(error.localizedDescription)") }
        }
        for root in roots + aiCacheRoots {
            try Task.checkCancellation()
            guard manager.fileExists(atPath: root.url.path) else { continue }
            do {
                guard root.url.resolvingSymlinksInPath().path == root.url.path else {
                    throw CleanupError.refused("掃描根目錄包含符號連結，已略過")
                }
                let children = try manager.contentsOfDirectory(at: root.url,
                    includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                for url in children {
                    try inspect(url)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(root.url.path)：\(error.localizedDescription)") }
        }
        if includeAIHistory {
            for url in try aiHistoryCandidates(warnings: &warnings) { try inspect(url) }
        }
        return ScanResult(items: items.sorted { $0.bytes > $1.bytes },
                          warnings: warnings, inspectedCount: totalFiles)
    }
}
