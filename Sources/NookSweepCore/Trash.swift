import Foundation

extension CleanupEngine {
    public func trash(_ items: [CleanupItem], runningBundleIDs: Set<String> = [],
                      runningAITools: Set<String> = [], allowAIHistory: Bool = false,
                      allowAIWorktrees: Bool = false) -> CleanupReport {
        var moved: [TrashedItem] = []
        var failures: [String] = []
        var seen = Set<String>()
        for item in items where seen.insert(item.id).inserted {
            do {
                try Task.checkCancellation()
                let entry = try catalogEntry(for: item.url)
                let root = try validatedRoot(for: item.url, knownEntry: entry)
                guard item.isEligible, item.category == root.category else {
                    throw CleanupError.refused("項目不符合清理規則，請重新掃描")
                }
                guard !item.isAIHistory || allowAIHistory else {
                    throw CleanupError.refused("對話紀錄需另外確認，未移動任何對話")
                }
                guard item.category != .aiWorktrees || allowAIWorktrees else {
                    throw CleanupError.refused("工作副本與 Git 登記需另外確認")
                }
                guard item.aiMetadata == inventoryMetadata(for: item.url, category: root.category, entry: entry),
                      Set(item.relatedURLs.map { $0.standardizedFileURL.path }) ==
                        Set((entry?.relatedURLs ?? []).map { $0.standardizedFileURL.path }) else {
                    throw CleanupError.refused("資料類型、使用版本或關聯內容已改變，請重新掃描")
                }
                let current = try measureGroup(item.url, relatedURLs: entry?.relatedURLs ?? [])
                guard current.total.fingerprint == item.fingerprint else {
                    throw CleanupError.refused("掃描後內容已改變，請重新掃描")
                }
                let freshEntry = try catalogEntry(for: item.url)
                guard item.aiMetadata == inventoryMetadata(for: item.url, category: root.category, entry: freshEntry),
                      Set(item.relatedURLs.map { $0.standardizedFileURL.path }) ==
                        Set((freshEntry?.relatedURLs ?? []).map { $0.standardizedFileURL.path }) else {
                    throw CleanupError.refused("驗證期間資料類型、使用版本或關聯內容已改變，請重新掃描")
                }
                guard try state(for: item.url, category: root.category, bytes: current.total.bytes,
                            modified: current.total.modified,
                            runningBundleIDs: runningBundleIDs, runningAITools: runningAITools,
                            knownEntry: freshEntry) == .eligible else {
                    throw CleanupError.refused("項目最近有使用或應用程式執行中，已保留")
                }
                _ = try validatedRoot(for: item.url, knownEntry: freshEntry)
                if let tool = item.aiToolID, activity().contains(tool) {
                    throw CleanupError.refused("AI 工具執行中，請結束後重新掃描")
                }
                let destinations = try trashGroup(current.paths)
                if let primary = destinations.first {
                    moved.append(TrashedItem(originalURL: item.url, trashURL: primary.trashURL,
                        bytes: current.total.bytes, relatedMoves: Array(destinations.dropFirst())))
                }
            } catch let error as GroupTrashFailure {
                failures.append("\(item.name)：\(error.localizedDescription)")
                moved += error.remaining.map { TrashedItem(originalURL: $0.originalURL, trashURL: $0.trashURL, bytes: $0.bytes) }
            } catch { failures.append("\(item.name)：\(error.localizedDescription)") }
        }
        return CleanupReport(moved: moved, failures: failures)
    }
}
