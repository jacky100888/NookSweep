import Foundation
import Testing
@testable import NookSweepCore

@Test func manualReviewPreviewsChangesAndAllowsRecentWorktreesWhileCodexRuns() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    try Data("changed".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try Data("untracked".utf8).write(to: value.worktree.appendingPathComponent("private.txt"))
    let ignored = value.worktree.appendingPathComponent("ignored/payload")
    try FileManager.default.createDirectory(at: ignored.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("ignored".utf8).write(to: ignored)
    let engine = CleanupEngine(home: value.fixture.home, activity: { ["codex"] })
    let regular = try await engine.scan(categories: [.aiWorktrees], runningAITools: ["codex"])
    #expect(regular.items.first?.isEligible == false)
    let manual = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees], runningAITools: ["codex"])
    let item = try #require(manual.items.first)
    let review = try #require(item.aiMetadata?.worktreeReview)
    #expect(item.isEligible)
    #expect(review.trackedChanges == 1)
    #expect(review.untrackedItems == 1)
    #expect(review.ignoredItems == 1)
    #expect(item.relatedItemCount == 1)
    #expect(await engine.trash([item], manualWorktreeReview: true).moved.isEmpty)
    #expect(await engine.trash([item], allowAIWorktrees: true).moved.isEmpty)
}

@Test func manualTrashPinsDetachedUnmergedHeadAndRestoresTheCompleteGroup() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    try WorktreeFixture.git(["checkout", "--detach"], at: value.worktree)
    try Data("unmerged".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try WorktreeFixture.git(["add", "."], at: value.worktree)
    try WorktreeFixture.git(["commit", "--no-gpg-sign", "-m", "尚未合併的暫存版本"], at: value.worktree)
    let engine = CleanupEngine(home: value.fixture.home, activity: { ["codex"] })
    let result = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    let item = try #require(result.items.first)
    #expect(item.aiMetadata?.worktreeReview?.unmergedCommitCount == 1)
    let report = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(report.failures.isEmpty, "\(report.failures)")
    let recovery = try #require(report.recoveryReferences.first)
    #expect(recovery.headOID == item.aiMetadata?.worktreeReview?.headOID)
    #expect(recovery.refName.hasPrefix("refs/nooksweep/recovery/"))
    try WorktreeFixture.git(["show-ref", "--verify", recovery.refName], at: value.primary)
    let moved = try #require(report.moved.first)
    for related in moved.relatedMoves { try FileManager.default.moveItem(at: related.trashURL, to: related.originalURL) }
    try FileManager.default.moveItem(at: moved.trashURL, to: moved.originalURL)
    try WorktreeFixture.git(["status", "--porcelain"], at: value.worktree)
}

@Test func manualTrashKeepsRecoveryInformationWhenMovingFails() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let engine = CleanupEngine(home: value.fixture.home, activity: { ["codex"] }, trashOperation: { _ in
        throw CleanupError.refused("測試搬移失敗")
    })
    let scan = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    let item = try #require(scan.items.first)
    let report = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(report.moved.isEmpty)
    #expect(!report.failures.isEmpty)
    let recovery = try #require(report.recoveryReferences.first)
    try WorktreeFixture.git(["show-ref", "--verify", recovery.refName], at: value.primary)
    #expect(FileManager.default.fileExists(atPath: value.worktree.path))
}

@Test func manualReviewStillBlocksLocksAndHeadChangesAfterPreview() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let engine = CleanupEngine(home: value.fixture.home, activity: { [] })
    let scan = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    let item = try #require(scan.items.first)
    try WorktreeFixture.git(["worktree", "lock", value.worktree.path], at: value.primary)
    let locked = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    #expect(locked.items.first?.isEligible == false)
    let refused = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(refused.moved.isEmpty)
    #expect(refused.recoveryReferences.isEmpty)
    try WorktreeFixture.git(["worktree", "unlock", value.worktree.path], at: value.primary)
    try Data("new head".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try WorktreeFixture.git(["add", "."], at: value.worktree)
    try WorktreeFixture.git(["commit", "--no-gpg-sign", "-m", "預覽後改變"], at: value.worktree)
    let changed = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(changed.moved.isEmpty)
    #expect(changed.recoveryReferences.isEmpty)
}

@Test(arguments: ["sparse", "in-progress", "submodule", "redirect", "nested-symlink"])
func manualReviewNeverOverridesUnverifiableWorktreeBoundaries(_ boundary: String) async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let git = try GitInspection(repository: value.worktree)
    switch boundary {
    case "sparse":
        try WorktreeFixture.git(["update-index", "--skip-worktree", "source.txt"], at: value.worktree)
    case "in-progress":
        try Data("pending".utf8).write(to: git.administrationDirectory.appendingPathComponent("MERGE_HEAD"))
    case "submodule":
        try WorktreeFixture.git(["update-index", "--add", "--cacheinfo", "160000,\(git.currentHeadOID()),module"],
                                at: value.worktree)
    case "redirect":
        try WorktreeFixture.git(["config", "extensions.worktreeConfig", "true"], at: value.primary)
        try WorktreeFixture.git(["config", "--worktree", "core.worktree", value.primary.path], at: value.worktree)
    default:
        let outside = value.fixture.home.appendingPathComponent("private-data")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: value.worktree.appendingPathComponent("linked"),
                                                  withDestinationURL: outside)
    }
    let engine = CleanupEngine(home: value.fixture.home, activity: { ["codex"] })
    let scan = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    let item = try #require(scan.items.first)
    #expect(!item.isEligible)
    let report = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(report.moved.isEmpty)
    #expect(report.recoveryReferences.isEmpty)
}

@Test func failedSecondGroupMoveRestoresWorktreeAndStillReportsRecoveryPin() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let worktree = value.worktree
    let destination = value.fixture.home.appendingPathComponent("simulated-trash")
    let engine = CleanupEngine(home: value.fixture.home, activity: { [] }, trashOperation: { source in
        guard source.path == worktree.path else { throw CleanupError.refused("第二個關聯項目搬移失敗") }
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    })
    let scan = try await engine.scan(manualWorktreeReview: true, categories: [.aiWorktrees])
    let item = try #require(scan.items.first)
    let report = await engine.trash([item], allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(report.moved.isEmpty)
    #expect(!report.failures.isEmpty)
    #expect(FileManager.default.fileExists(atPath: worktree.path))
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    let recovery = try #require(report.recoveryReferences.first)
    try WorktreeFixture.git(["show-ref", "--verify", recovery.refName], at: value.primary)
}
