import Foundation
import Testing
@testable import NookSweepCore

@Test func cursorHistoryGroupsTheRecordWithoutReadingSnapshots() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let record = fixture.home.appendingPathComponent("Library/Application Support/Cursor/User/History/-abc123")
    try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
    try Data(#"{"resource":"file:///private/project/Example.swift","entries":[]}"#.utf8)
        .write(to: record.appendingPathComponent("entries.json"))
    try Data([0xff, 0x00]).write(to: record.appendingPathComponent("snapshot.swift"))
    let entry = try #require(try AILegacyHistoryCatalog.entry(for: record, home: fixture.home))
    #expect(entry.metadata.toolID == "cursor")
    #expect(entry.metadata.kind == .localHistory)
    #expect(entry.metadata.title.contains("Example.swift"))
    #expect(entry.preservationReason == nil)
    #expect(entry.relatedURLs.isEmpty)
    #expect(try AILegacyHistoryCatalog.entry(for: record.appendingPathComponent("snapshot.swift"),
                                           home: fixture.home) == nil)
}

@Test func legacyOpencodeIncludesEveryAssociatedNamespaceWithoutParsingMessages() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let paths = ["session/project/ses_abc.json", "message/ses_abc/msg_one.json",
                 "message/ses_abc/msg_two.json", "part/msg_one/prt_a.json",
                 "part/msg_two/prt_b.json", "session_diff/ses_abc.json", "todo/ses_abc.json"]
    for path in paths { try fixture.aiFile(".local/share/opencode/storage/" + path) }
    let session = fixture.home.appendingPathComponent(".local/share/opencode/storage/session/project/ses_abc.json")
    let entry = try #require(try AILegacyHistoryCatalog.entry(for: session, home: fixture.home))
    #expect(entry.preservationReason == nil)
    #expect(Set(entry.relatedURLs.map(\.lastPathComponent)) ==
            ["ses_abc", "msg_one", "msg_two", "ses_abc.json"])
    #expect(entry.relatedURLs.count == 5)
    #expect(try AILegacyHistoryCatalog.candidates(home: fixture.home).count == 1)
}

@Test func opencodeDatabaseAndUnknownLayoutsPreserveLegacySessions() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let session = try fixture.aiFile(".local/share/opencode/storage/session/project/ses_abc.json")
    try fixture.aiFile(".local/share/opencode/opencode.db")
    let entries = try AILegacyHistoryCatalog.candidates(home: fixture.home)
    #expect(entries.count == 2)
    #expect(entries.allSatisfy { $0.preservationReason != nil })
    #expect(entries.first(where: { $0.url == session })?.relatedURLs.isEmpty == true)
    try FileManager.default.removeItem(at: fixture.home.appendingPathComponent(".local/share/opencode/opencode.db"))
    try fixture.aiFile(".local/share/opencode/storage/message/ses_abc/unknown.bin")
    #expect(try AILegacyHistoryCatalog.entry(for: session, home: fixture.home)?.preservationReason != nil)
}

@Test func legacyHistoryRejectsSymlinkedNamespacesAndDuplicateSessionIDs() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let session = try fixture.aiFile(".local/share/opencode/storage/session/project/ses_abc.json")
    let duplicate = try fixture.aiFile(".local/share/opencode/storage/session/other/ses_abc.json")
    let entries = try AILegacyHistoryCatalog.candidates(home: fixture.home)
    #expect(entries.count == 2)
    #expect(entries.allSatisfy { $0.preservationReason != nil })
    try FileManager.default.removeItem(at: duplicate)
    let messageRoot = fixture.home.appendingPathComponent(".local/share/opencode/storage/message")
    try FileManager.default.createSymbolicLink(at: messageRoot, withDestinationURL: fixture.home)
    #expect(try AILegacyHistoryCatalog.entry(for: session, home: fixture.home)?
        .preservationReason?.contains("符號連結") == true)
}

@Test func opencodeSharedMessageIdentifiersCannotRemoveAnotherSessionsParts() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let session = try fixture.aiFile(".local/share/opencode/storage/session/project/ses_abc.json")
    try fixture.aiFile(".local/share/opencode/storage/message/ses_abc/msg_shared.json")
    try fixture.aiFile(".local/share/opencode/storage/message/ses_other/msg_SHARED.json")
    try fixture.aiFile(".local/share/opencode/storage/part/msg_shared/prt_shared.json")
    let entry = try #require(try AILegacyHistoryCatalog.entry(for: session, home: fixture.home))
    #expect(entry.preservationReason != nil)
    #expect(entry.relatedURLs.isEmpty)
}

@Test func symbolicSessionProjectProtectsNormalSessionWithoutHidingCursorInventory() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let base = ".local/share/opencode/storage"
    let normal = try fixture.aiFile("\(base)/session/normal/ses_abc.json")
    try fixture.aiFile("\(base)/message/ses_abc/msg_one.json")
    try fixture.aiFile("\(base)/part/msg_one/prt_one.json")
    let outside = try fixture.aiFile("preserved-project/ses_abc.json")
    try FileManager.default.createSymbolicLink(at: fixture.home.appendingPathComponent("\(base)/session/linked"),
                                              withDestinationURL: outside.deletingLastPathComponent())
    try fixture.aiFile("Library/Application Support/Cursor/User/History/-a/snapshot.txt")
    let entries = try AILegacyHistoryCatalog.candidates(home: fixture.home)
    #expect(entries.count == 2)
    #expect(entries.contains { $0.metadata.toolID == "cursor" && $0.preservationReason == nil })
    let entry = try #require(entries.first { $0.url.path == normal.path })
    #expect(entry.preservationReason?.contains("符號連結") == true)
    #expect(entry.relatedURLs.isEmpty)
    #expect(try AILegacyHistoryCatalog.entry(for: normal, home: fixture.home)?.preservationReason != nil)
}

@Test(arguments: ["session/unknown-file.json", "session/other/nested/ses_abc.json", "session/other/unrecognized.json"])
func unknownSessionNamespaceProtectsEveryDiscoveredLegacySession(_ unexpectedPath: String) throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let base = ".local/share/opencode/storage"
    let normal = try fixture.aiFile("\(base)/session/normal/ses_abc.json")
    try fixture.aiFile("\(base)/\(unexpectedPath)")
    let entries = try AILegacyHistoryCatalog.candidates(home: fixture.home)
    let entry = try #require(entries.first { $0.url.path == normal.path })
    #expect(entry.preservationReason != nil)
    #expect(entry.relatedURLs.isEmpty)
}
