import Foundation
import Testing
@testable import NookSweepCore

func ageFixtureData(_ roots: [URL], days: Int = 40) throws {
    var pending = roots
    let date = Date().addingTimeInterval(-Double(days) * 86400)
    while let url = pending.popLast() {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { continue }
        if values.isDirectory == true {
            pending += try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

@Test func legacyConversationMovesItsWholeGroupOnlyAfterConfirmation() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let base = ".local/share/opencode/storage"
    let session = try fixture.aiFile("\(base)/session/project/ses_example.json")
    try fixture.aiFile("\(base)/message/ses_example/msg_example.json")
    try fixture.aiFile("\(base)/part/msg_example/prt_example.json")
    try ageFixtureData([fixture.home])
    let engine = CleanupEngine(home: fixture.home, activity: { [] })
    let scan = try await engine.scan(includeAIHistory: true, categories: [.aiHistory])
    let item = try #require(scan.items.first { $0.url.path == session.path })
    #expect(item.isEligible)
    #expect(item.relatedItemCount == 2)
    let denied = await engine.trash([item])
    #expect(denied.moved.isEmpty)
    let report = await engine.trash([item], allowAIHistory: true)
    defer {
        for moved in report.moved {
            try? FileManager.default.removeItem(at: moved.trashURL)
            for related in moved.relatedMoves { try? FileManager.default.removeItem(at: related.trashURL) }
        }
    }
    #expect(report.failures.isEmpty, "\(report.failures)")
    let moved = try #require(report.moved.first)
    #expect(moved.relatedMoves.count == 2)
    #expect(!FileManager.default.fileExists(atPath: session.path))
    #expect(moved.relatedMoves.allSatisfy { !FileManager.default.fileExists(atPath: $0.originalURL.path) })
}

@Test func claudeCurrentVersionChangeInvalidatesAnOlderVersionSelection() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let old = try fixture.aiFile(".local/share/claude/versions/2.1.1")
    let current = try fixture.aiFile(".local/share/claude/versions/2.1.2")
    let newer = try fixture.aiFile(".local/share/claude/versions/2.1.3")
    let link = fixture.home.appendingPathComponent(".local/bin/claude")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: current)
    let engine = CleanupEngine(home: fixture.home, activity: { [] })
    let result = try await engine.scan(categories: [.aiVersions])
    let item = try #require(result.items.first { $0.url.path == old.path })
    #expect(item.isEligible)
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: newer)
    let report = await engine.trash([item])
    #expect(report.moved.isEmpty)
    #expect(FileManager.default.fileExists(atPath: old.path))
}

@Test func aiOnlyScanDoesNotMeasureUnrelatedDeveloperCaches() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache("Library/Caches/go-build")
    try fixture.aiFile(".codex/log/example.log")
    let result = try await CleanupEngine(home: fixture.home, activity: { [] }).scan(categories: [.aiCaches])
    #expect(result.items.count == 1)
    #expect(result.inspectedCount == 1)
    #expect(result.items.first?.category == .aiCaches)
}

@Test func toolStartedDuringValidationIsCheckedAgainBeforeMoving() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".claude/debug/example.txt")
    let engine = CleanupEngine(home: fixture.home, activity: { ["claude"] })
    let result = try await engine.scan()
    let item = try #require(result.items.first)
    #expect(item.isEligible)
    let report = await engine.trash([item])
    defer { for moved in report.moved { try? FileManager.default.removeItem(at: moved.trashURL) } }
    #expect(report.moved.isEmpty)
    #expect(FileManager.default.fileExists(atPath: file.path))
}
