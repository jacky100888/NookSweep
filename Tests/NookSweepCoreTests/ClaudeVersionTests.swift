import Foundation
import Testing
@testable import NookSweepCore

private func installClaudeLink(_ fixture: Fixture, target: String) throws {
    let link = fixture.home.appendingPathComponent(".local/bin/claude")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: link.path) { try FileManager.default.removeItem(at: link) }
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
}

@Test func claudeVersionsKeepCurrentAndOnlyOfferOlderRegularVersions() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    for version in ["2.1.9", "2.1.10", "2.2.0", "2.1.10-rc.1", "unknown"] {
        try fixture.aiFile(".local/share/claude/versions/\(version)")
    }
    try installClaudeLink(fixture, target: "../share/claude/versions/2.1.10")
    let entries = try ClaudeVersionCatalog.candidates(home: fixture.home)
    #expect(entries.count == 5)
    #expect(entries.allSatisfy { $0.category == .aiVersions && $0.metadata.kind == .oldVersion && $0.metadata.toolID == "claude" })
    #expect(Set(entries.filter { $0.preservationReason == nil }.map(\.url.lastPathComponent)) == ["2.1.9", "2.1.10-rc.1"])
    #expect(entries.first { $0.url.lastPathComponent == "2.1.10" }?.preservationReason?.contains("目前") == true)
}

@Test func claudeVersionsPreserveEverythingWhenCurrentLinkIsUnknownOrOutside() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.aiFile(".local/share/claude/versions/2.1.1")
    #expect(try ClaudeVersionCatalog.candidates(home: fixture.home).allSatisfy { $0.preservationReason != nil })
    let external = try fixture.aiFile("Documents/2.2.0")
    try installClaudeLink(fixture, target: external.path)
    #expect(try ClaudeVersionCatalog.candidates(home: fixture.home).allSatisfy { $0.preservationReason != nil })
}

@Test func claudeVersionsRecheckCurrentLinkBeforeCleanup() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let old = try fixture.aiFile(".local/share/claude/versions/2.1.1")
    try fixture.aiFile(".local/share/claude/versions/2.1.2")
    try fixture.aiFile(".local/share/claude/versions/2.1.3")
    try installClaudeLink(fixture, target: "../share/claude/versions/2.1.2")
    let scanned = try #require(try ClaudeVersionCatalog.entry(for: old, home: fixture.home))
    #expect(scanned.preservationReason == nil)
    try installClaudeLink(fixture, target: "../share/claude/versions/2.1.3")
    let changed = try #require(try ClaudeVersionCatalog.entry(for: old, home: fixture.home))
    #expect(changed.preservationReason == nil)
    #expect(changed.metadata != scanned.metadata)
    try installClaudeLink(fixture, target: "../share/claude/versions/2.1.1")
    #expect(try ClaudeVersionCatalog.entry(for: old, home: fixture.home)?.preservationReason != nil)
}

@Test func claudeVersionCatalogRejectsSymlinkedVersionFilesAndParents() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let external = try fixture.aiFile("Documents/2.1.0")
    let versionRoot = fixture.home.appendingPathComponent(".local/share/claude/versions")
    try FileManager.default.createDirectory(at: versionRoot, withIntermediateDirectories: true)
    let version = versionRoot.appendingPathComponent("2.1.0")
    try FileManager.default.createSymbolicLink(at: version, withDestinationURL: external)
    #expect(try ClaudeVersionCatalog.entry(for: version, home: fixture.home) == nil)
    #expect(try ClaudeVersionCatalog.candidates(home: fixture.home).isEmpty)
    try FileManager.default.removeItem(at: versionRoot)
    try FileManager.default.createSymbolicLink(at: versionRoot, withDestinationURL: external.deletingLastPathComponent())
    #expect(try ClaudeVersionCatalog.entry(for: version, home: fixture.home) == nil)
    #expect(try ClaudeVersionCatalog.candidates(home: fixture.home).isEmpty)
}
