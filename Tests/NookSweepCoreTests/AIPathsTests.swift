import Foundation
import Testing
@testable import NookSweepCore

extension Fixture {
    @discardableResult
    func aiFile(_ path: String, days: Int = 40) throws -> URL {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try Data(repeating: 65, count: 4096).write(to: file)
        try FileManager.default.setAttributes([
            .modificationDate: Date().addingTimeInterval(-Double(days) * 86400)
        ], ofItemAtPath: file.path)
        return file
    }
}

private let conversationID = "11111111-2222-4333-8444-555555555555"

@Test func knownAppCacheNamesAreRecognizedWithoutMatchingUnrelatedApps() {
    let root = URL(fileURLWithPath: "/tmp/test-home/Library/Caches")
    #expect(aiToolIdentifier(for: root.appendingPathComponent("Claude")) == "claude")
    #expect(aiToolIdentifier(for: root.appendingPathComponent("ChatGPT")) == "chatgpt")
    #expect(aiToolIdentifier(for: root.appendingPathComponent("ClaudePlugin")) == nil)
}

@Test func aiConversationsRequireScanOptIn() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".claude/projects/project/\(conversationID).jsonl")
    try fixture.aiFile(".gemini/tmp/project/chats/session-old.json")
    let engine = CleanupEngine(home: fixture.home)
    let regular = try await engine.scan()
    #expect(regular.items.isEmpty)
    let optedIn = try await engine.scan(includeAIHistory: true)
    #expect(optedIn.items.count == 2)
    #expect(optedIn.items.allSatisfy { $0.isAIHistory && $0.isEligible })
    #expect(Set(optedIn.items.compactMap(\.aiToolID)) == ["claude", "gemini"])
}

@Test func aiConversationAgeIsThirtyDays() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".gemini/tmp/project/chats/session-recent.json", days: 10)
    let result = try await CleanupEngine(home: fixture.home).scan(includeAIHistory: true)
    #expect(result.items.first?.state == .recent)
}

@Test func codexIndexedConversationsRemainProtected() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".codex/sessions/2026/01/01/rollout-old.jsonl")
    try fixture.aiFile(".codex/state_5.sqlite")
    try fixture.aiFile(".codex/state_5.sqlite-wal")
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan(includeAIHistory: true)
    let item = try #require(result.items.first)
    #expect(result.items.count == 1)
    #expect(!item.isEligible)
    #expect(item.state.reason?.contains("資料庫索引") == true)
    let report = await engine.trash([item], allowAIHistory: true)
    #expect(report.moved.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func aiSettingsMemoryAndUnknownFilesAreNotConversationCandidates() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    for path in [".claude/auth.json", ".claude/settings.json", ".claude/history.jsonl",
                 ".claude/projects/project/memory/\(conversationID).jsonl",
                 ".claude/projects/project/readme.jsonl", ".claude/skills/tool/\(conversationID).jsonl",
                 ".gemini/tmp/project/auth.json", ".gemini/tmp/project/chats/memory.json",
                 ".gemini/oauth_creds.json", ".codex/auth.json"] {
        try fixture.aiFile(path)
    }
    let result = try await CleanupEngine(home: fixture.home).scan(includeAIHistory: true)
    #expect(result.items.isEmpty)
}

@Test func claudeSubagentsAreIndividualConversationFiles() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".claude/projects/project/\(conversationID)/subagents/agent-test.jsonl")
    try fixture.aiFile(".claude/projects/project/\(conversationID)/memory/agent-private.jsonl")
    let result = try await CleanupEngine(home: fixture.home).scan(includeAIHistory: true)
    #expect(result.items.count == 1)
    #expect(result.items.first?.name == "agent-test.jsonl")
}

@Test func symbolicAIProjectCannotEscapeIntoDocuments() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let important = try fixture.aiFile("Documents/project/\(conversationID).jsonl")
    let root = fixture.home.appendingPathComponent(".claude/projects")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"),
                                             withDestinationURL: important.deletingLastPathComponent())
    let result = try await CleanupEngine(home: fixture.home).scan(includeAIHistory: true)
    #expect(result.items.isEmpty)
    #expect(!result.warnings.isEmpty)
    #expect(FileManager.default.fileExists(atPath: important.path))
}

@Test func aiCacheClassificationProtectsRunningTools() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".claude/debug/old.txt", days: 10)
    try fixture.aiFile(".codex/shell_snapshots/old.sh", days: 10)
    try fixture.aiFile("Library/Caches/com.openai.codex/old.cache", days: 10)
    try fixture.aiFile("Library/Caches/com.anthropic.claudefordesktop/old.cache", days: 10)
    let result = try await CleanupEngine(home: fixture.home)
        .scan(runningAITools: ["claude", "codex"])
    #expect(result.items.count == 4)
    #expect(result.items.allSatisfy { $0.category == .aiCaches && $0.state == .running })
}

@Test func aiCacheDatabaseContentsStayProtected() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let database = try fixture.aiFile("Library/Caches/com.anthropic.claudefordesktop/data/cache.sqlite")
    let old = Date().addingTimeInterval(-40 * 86400)
    for directory in [database.deletingLastPathComponent(), database.deletingLastPathComponent().deletingLastPathComponent()] {
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: directory.path)
    }
    let credentials = try fixture.aiFile(".codex/log/auth.json")
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.count == 1)
    #expect(result.items.first?.category == .aiCaches)
    #expect(result.items.first?.state.reason?.contains("資料庫") == true)
    #expect(result.items.allSatisfy { !$0.isEligible })
    #expect(FileManager.default.fileExists(atPath: credentials.path))
}

@Test func aiCacheRootsDoNotTreatUnknownDirectoriesAsDisposable() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let source = try fixture.aiFile(".claude/debug/project/main.swift")
    try fixture.aiFile(".codex/shell_snapshots/unknown.json")
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.isEmpty)
    #expect(FileManager.default.fileExists(atPath: source.path))
}
