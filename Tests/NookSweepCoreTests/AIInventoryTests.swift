import Foundation
import Testing
@testable import NookSweepCore

@Test func conversationInventoryListsRetainedDataWithoutAllowingCleanup() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".claude/projects/project/11111111-2222-4333-8444-555555555555.jsonl")
    let engine = CleanupEngine(home: fixture.home, activity: { [] })
    let result = try await engine.scan(inventoryAIHistory: true)
    let item = try #require(result.items.first)
    #expect(item.isAIHistory)
    #expect(!item.isEligible)
    let report = await engine.trash([item])
    #expect(report.moved.isEmpty)
}

@Test func compressedCodexConversationsAreListedAndRemainProtected() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".codex/sessions/2026/01/01/rollout-old.jsonl.zst")
    try fixture.aiFile(".codex/archived_sessions/rollout-archive.jsonl.zst")
    let result = try await CleanupEngine(home: fixture.home, activity: { [] }).scan(includeAIHistory: true)
    #expect(result.items.count == 2)
    #expect(result.items.allSatisfy { !$0.isEligible && $0.state.reason?.contains("索引") == true })
}

@Test func relatedConversationFilesAffectTheFingerprint() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let session = try fixture.aiFile("session.json")
    let related = try fixture.aiFile("message.json")
    let before = try measureGroup(session, relatedURLs: [related])
    try Data("changed".utf8).write(to: related)
    let after = try measureGroup(session, relatedURLs: [related])
    #expect(before.total.fingerprint != after.total.fingerprint)
}

@Test func failedGroupMoveRestoresPreviouslyTrashedPaths() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let first = try fixture.aiFile("first.json")
    let second = try fixture.aiFile("second.json")
    var calls = 0
    #expect(throws: GroupTrashFailure.self) {
        try trashGroup([(first, 4096), (second, 4096)]) { url in
            calls += 1
            if calls == 2 { throw CleanupError.refused("測試第二項失敗") }
            return try systemTrash(url)
        }
    }
    #expect(calls == 2)
    #expect(FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
}
