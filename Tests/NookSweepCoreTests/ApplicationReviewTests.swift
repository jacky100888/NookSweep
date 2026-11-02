import Foundation
import Testing
@testable import NookSweepCore

private actor ApplicationActivitySequence {
    let bundleID: String
    let activatesAt: Int
    private var calls = 0

    init(bundleID: String, activatesAt: Int) {
        self.bundleID = bundleID
        self.activatesAt = activatesAt
    }

    func next() -> ApplicationActivity {
        calls += 1
        return ApplicationActivity(bundleIDs: calls >= activatesAt ? [bundleID] : [])
    }
}

@Test func applicationCaseFoldedNamesCannotClaimSharedUserData() async throws {
    for (name, otherName, otherID) in [("Example", "example", "org.other.editor"),
        ("Straße", "STRASSE", "org.other.editor"), ("Café", "CAFE\u{301}", "org.other.editor"),
        ("Example", "example", "com.apple.fixture")] {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        let appURL = try fixture.app(name)
        let otherApp = try fixture.app("Other", id: otherID)
        let info = ["CFBundleIdentifier": otherID, "CFBundleName": otherName]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: otherApp.appendingPathComponent("Contents/Info.plist"))
        let shared = try fixture.data("Application Support/\(name)")
        let userDatabase = shared.appendingPathComponent("user.db")
        try Data("other app user content".utf8).write(to: userDatabase)
        let engine = fixture.engine()
        let app = try #require(try await engine.scan().applications.first { $0.url.path == appURL.path })
        let related = try await engine.relatedData(for: app)
        let data = try #require(related.first { $0.url.path == shared.path })
        #expect(!data.isSelectable)
        let report = await engine.trash(app, relatedItems: [data])
        #expect(report.movedCount == 1)
        #expect(report.results.last?.succeeded == false)
        #expect(FileManager.default.fileExists(atPath: otherApp.path))
        #expect(FileManager.default.fileExists(atPath: userDatabase.path))
    }
}

@Test func applicationBundleIDPathsOverlappingOtherOwnersArePreserved() async throws {
    for (otherID, otherName) in [("org.other.editor", "ORG.EXAMPLE.EDITOR"),
                                 ("ORG.EXAMPLE.EDITOR", "Other")] {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        try fixture.app()
        let other = try fixture.app("Other", id: otherID)
        let info = ["CFBundleIdentifier": otherID, "CFBundleName": otherName]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: other.appendingPathComponent("Contents/Info.plist"))
        let shared = try fixture.data("Caches/org.example.editor")
        let engine = fixture.engine()
        let app = try #require(try await engine.scan().applications.first { $0.name == "Example" })
        let related = try await engine.relatedData(for: app)
        let data = try #require(related.first { $0.url.path == shared.path })
        #expect(!data.isSelectable)
        let report = await engine.trash(app, relatedItems: [data])
        #expect(report.movedCount == 1)
        #expect(FileManager.default.fileExists(atPath: shared.appendingPathComponent("payload").path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}

@Test func applicationStartedDuringMeasurementIsCheckedBeforeTrash() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let sequence = ApplicationActivitySequence(bundleID: app.bundleID, activatesAt: 2)
    let movedURL = fixture.root.appendingPathComponent("UnexpectedMove")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { await sequence.next() },
        trashOperation: { url in
            try FileManager.default.moveItem(at: url, to: movedURL)
            return movedURL
        })
    let report = await engine.trash(app)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error?.contains("執行中") == true)
    #expect(FileManager.default.fileExists(atPath: appURL.path))
    #expect(!FileManager.default.fileExists(atPath: movedURL.path))
}

@Test func applicationStartedDuringRelatedMeasurementPreservesRelatedData() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let sequence = ApplicationActivitySequence(bundleID: app.bundleID, activatesAt: 4)
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { await sequence.next() },
        trashOperation: { url in
            let destination = url.deletingLastPathComponent().appendingPathComponent("Moved-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 1)
    #expect(report.results.last?.error?.contains("執行中") == true)
    #expect(FileManager.default.fileExists(atPath: dataURL.appendingPathComponent("payload").path))
}
