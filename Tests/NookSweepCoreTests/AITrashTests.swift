import Foundation
import Testing
@testable import NookSweepCore

@Test func conversationTrashRequiresSeparateConfirmation() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".gemini/tmp/project/chats/session-old.json")
    let engine = CleanupEngine(home: fixture.home)
    let scanned = try await engine.scan(includeAIHistory: true)
    let report = await engine.trash(scanned.items)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func confirmedConversationMovePreservesAdjacentMemory() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".gemini/tmp/project/chats/session-old.json")
    let memory = try fixture.aiFile(".gemini/tmp/project/memory.md")
    let engine = CleanupEngine(home: fixture.home)
    let scanned = try await engine.scan(includeAIHistory: true)
    let report = await engine.trash(scanned.items, allowAIHistory: true)
    defer { for moved in report.moved { try? FileManager.default.removeItem(at: moved.trashURL) } }
    #expect(report.moved.count == 1)
    #expect(report.failures.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(FileManager.default.fileExists(atPath: memory.path))
}

@Test func aiToolStartedAfterScanProtectsItsConversations() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".gemini/tmp/project/chats/session-old.json")
    let engine = CleanupEngine(home: fixture.home)
    let scanned = try await engine.scan(includeAIHistory: true)
    let report = await engine.trash(scanned.items, runningAITools: ["gemini"], allowAIHistory: true)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func forgedMemoryPathCannotUseConversationCleanup() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".claude/projects/project/memory/11111111-2222-4333-8444-555555555555.jsonl")
    let item = CleanupItem(url: file, category: .aiHistory, bytes: 4096, fileCount: 1,
                           modified: .distantPast, state: .eligible, fingerprint: "forged")
    let report = await CleanupEngine(home: fixture.home).trash([item], allowAIHistory: true)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: file.path))
}
