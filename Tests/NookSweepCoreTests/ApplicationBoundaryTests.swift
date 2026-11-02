import Foundation
import Testing
@testable import NookSweepCore

@Test func applicationRelatedSymlinksAreNeverSelectableOrFollowed() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let outside = try fixture.data("Other/keep")
    let link = fixture.home.appendingPathComponent("Library/Caches/org.example.editor")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)
    #expect(related.count == 1)
    #expect(related.allSatisfy { !$0.isSelectable })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 1)
    #expect(report.results.last?.succeeded == false)
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("payload").path))
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    #expect(target == outside.path)
}

@Test func applicationParentReplacementWithSymlinkIsRefused() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let outside = fixture.root.appendingPathComponent("Preserved")
    try FileManager.default.moveItem(at: fixture.applications, to: outside)
    try FileManager.default.createSymbolicLink(at: fixture.applications, withDestinationURL: outside)
    let report = await engine.trash(app)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error != nil)
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("Example.app").path))
}

@Test func applicationForgedRelatedDataOutsideAllowlistIsPreserved() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let outside = try fixture.data("Group Containers/org.example.editor")
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let forged = ApplicationRelatedItem(url: outside, category: "偽造", bytes: 1,
        blockedReason: nil, fingerprint: "forged", matchedByName: false)
    let report = await engine.trash(app, relatedItems: [forged])
    #expect(report.movedCount == 1)
    #expect(report.results.last?.succeeded == false)
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("payload").path))
}

@Test func applicationNativeTrashMovesOnlyFixtureAndRetainsSymlinkTarget() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let outside = try fixture.data("Other/keep")
    try FileManager.default.createSymbolicLink(at: appURL.appendingPathComponent("Contents/Frameworks"),
                                             withDestinationURL: outside)
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() })
    let app = try #require(try await engine.scan().applications.first)
    let report = await engine.trash(app)
    defer {
        for item in report.results {
            if let trash = item.trashURL { try? FileManager.default.removeItem(at: trash) }
        }
    }
    #expect(report.movedCount == 1)
    let destination = try #require(report.results.first?.trashURL)
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path))
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("payload").path))
    #expect(!FileManager.default.fileExists(atPath: appURL.path))
}

@Test func applicationInitialAncestorSymlinkCannotRedefineAllowedRoot() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let linkedParent = fixture.root.appendingPathComponent("Linked")
    try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: fixture.root)
    let engine = ApplicationsEngine(applicationRoots: [linkedParent.appendingPathComponent("Applications")],
        home: fixture.home, ownBundleID: nil, ownApplicationURL: nil,
        activity: { ApplicationActivity() })
    let result = try await engine.scan()
    #expect(result.applications.isEmpty)
    #expect(!result.warnings.isEmpty)
}
