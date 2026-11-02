import Foundation

extension CleanupEngine {
    public func trash(_ items: [CleanupItem], runningBundleIDs: Set<String> = [],
                      runningAITools: Set<String> = [], allowAIHistory: Bool = false) -> CleanupReport {
        var moved: [TrashedItem] = []
        var failures: [String] = []
        var seen = Set<String>()
        for item in items where seen.insert(item.id).inserted {
            do {
                try Task.checkCancellation()
                let root = try validatedRoot(for: item.url)
                guard item.isEligible, item.category == root.category else {
                    throw CleanupError.refused("項目不符合清理規則，請重新掃描")
                }
                guard !item.isAIHistory || allowAIHistory else {
                    throw CleanupError.refused("對話紀錄需另外確認，未移動任何對話")
                }
                let current = try measure(item.url)
                guard current.fingerprint == item.fingerprint else {
                    throw CleanupError.refused("掃描後內容已改變，請重新掃描")
                }
                guard try state(for: item.url, category: root.category, bytes: current.bytes,
                            modified: current.modified,
                            runningBundleIDs: runningBundleIDs, runningAITools: runningAITools) == .eligible else {
                    throw CleanupError.refused("項目最近有使用或應用程式執行中，已保留")
                }
                _ = try validatedRoot(for: item.url)
                var destination: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &destination)
                guard let destination else {
                    throw CleanupError.refused("系統未回傳垃圾桶位置，請到 Finder 確認")
                }
                moved.append(TrashedItem(originalURL: item.url,
                                         trashURL: destination as URL, bytes: item.bytes))
            } catch { failures.append("\(item.name)：\(error.localizedDescription)") }
        }
        return CleanupReport(moved: moved, failures: failures)
    }
}
