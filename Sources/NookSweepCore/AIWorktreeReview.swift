import Foundation

public struct AIWorktreeReview: Equatable, Sendable {
    public let headOID: String
    public let commonGitDirectory: URL
    public let trackedChanges: Int
    public let untrackedItems: Int
    public let ignoredItems: Int
    public let unmergedCommitCount: Int
    public let comparisonBranch: String

    public var summary: String {
        "已追蹤變更 \(trackedChanges) 項、未追蹤 \(untrackedItems) 項、已忽略 \(ignoredItems) 項；" +
        "有 \(unmergedCommitCount) 個提交不在 \(comparisonBranch)。已忽略項目可能是整個資料夾。"
    }

    var conservativeReason: String? {
        if trackedChanges + untrackedItems + ignoredItems > 0 {
            return "含變更、未追蹤或已忽略的檔案，保留原狀"
        }
        return unmergedCommitCount > 0 ? "工作副本 HEAD 尚未合併至 main／master，保留原狀" : nil
    }
}

public struct WorktreeRecoveryReference: Equatable, Sendable {
    public let worktreeURL: URL
    public let commonGitDirectory: URL
    public let refName: String
    public let headOID: String
}
