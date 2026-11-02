import Foundation
import Testing
@testable import NookSweepCore

struct ApplicationFixture {
    let root: URL
    let home: URL
    let applications: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("NookSweep-AppTests-\(UUID().uuidString)")
        home = root.appendingPathComponent("Home")
        applications = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    @discardableResult
    func app(_ name: String = "Example", id: String = "org.example.editor") throws -> URL {
        let app = applications.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": id, "CFBundleName": name,
                     "CFBundleShortVersionString": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data("fixture executable".utf8).write(to: contents.appendingPathComponent("binary"))
        return app
    }

    @discardableResult
    func data(_ path: String) throws -> URL {
        let url = home.appendingPathComponent("Library/\(path)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("user settings".utf8).write(to: url.appendingPathComponent("payload"))
        return url
    }

    func engine(ownID: String? = nil, running: Set<String> = []) -> ApplicationsEngine {
        ApplicationsEngine(applicationRoots: [applications], home: home, ownBundleID: ownID,
                           ownApplicationURL: nil, activity: { ApplicationActivity(bundleIDs: running) },
                           trashOperation: { url in
            let trash = url.deletingLastPathComponent().appendingPathComponent("Trashed-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: url, to: trash)
            return trash
        })
    }

    func dispose() throws { try FileManager.default.removeItem(at: root) }
}

@Test func applicationScanProtectsOwnAppleAndRunningApps() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app("Own", id: "org.nooksweep.app")
    try fixture.app("Running", id: "org.example.running")
    try fixture.app("Apple", id: "com.apple.TextEdit")
    let result = try await fixture.engine(ownID: "org.nooksweep.app", running: ["org.example.running"]).scan()
    #expect(result.applications.count == 2)
    #expect(result.applications.allSatisfy { !$0.isRemovable })
    #expect(result.applications.allSatisfy { $0.bytes > 0 && $0.version == "1.2.3" })
}

@Test func applicationRelatedDataMatchesExactNamesAndProtectsSharedNames() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    try fixture.data("Caches/org.example.editor")
    try fixture.data("Caches/org.example.editor.unrelated")
    try fixture.data("Application Support/Example")
    try fixture.data("Group Containers/org.example.editor")
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)
    #expect(Set(related.map { $0.url.lastPathComponent }) == ["org.example.editor", "Example"])
    #expect(related.allSatisfy { $0.isSelectable })
    let utilities = fixture.applications.appendingPathComponent("Utilities")
    try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
    let duplicate = try fixture.app("Other", id: "org.other.editor")
    try FileManager.default.moveItem(at: duplicate, to: utilities.appendingPathComponent("Example.app"))
    let info = utilities.appendingPathComponent("Example.app/Contents/Info.plist")
    let plist = ["CFBundleIdentifier": "org.other.editor", "CFBundleName": "Example"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: info)
    let ambiguous = try await engine.relatedData(for: app)
    #expect(ambiguous.first { $0.url.lastPathComponent == "Example" }?.isSelectable == false)
    #expect(ambiguous.first { $0.url.lastPathComponent == "org.example.editor" }?.isSelectable == true)
}

@Test func applicationInternalSymlinksDoNotFollowExternalTargets() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let external = try fixture.data("Caches/keep")
    let link = appURL.appendingPathComponent("Contents/Frameworks")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    try Data("outside changed and must not affect fingerprint".utf8)
        .write(to: external.appendingPathComponent("payload"))
    let report = await engine.trash(app, relatedItems: [])
    #expect(report.results.count == 1)
    #expect(report.results.allSatisfy { $0.succeeded })
    #expect(FileManager.default.fileExists(atPath: external.appendingPathComponent("payload").path))
}

@Test func applicationChangesAndStartedProcessesPreventRemoval() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let url = try fixture.app()
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    try Data("modified executable".utf8).write(to: url.appendingPathComponent("Contents/binary"))
    let changed = await engine.trash(app, relatedItems: [])
    #expect(changed.results.allSatisfy { !$0.succeeded })
    let refreshed = try #require(try await engine.scan().applications.first)
    let running = fixture.engine(running: ["org.example.editor"])
    let report = await running.trash(refreshed, relatedItems: [])
    #expect(report.results.allSatisfy { !$0.succeeded })
    #expect(report.results.first?.error?.contains("執行中") == true)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func applicationRootSymlinksAndForgedPathsAreRefused() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let moved = fixture.home.appendingPathComponent("Example.app")
    try FileManager.default.moveItem(at: original, to: moved)
    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: moved)
    let linked = await engine.trash(app, relatedItems: [])
    #expect(linked.results.allSatisfy { !$0.succeeded })
    let forged = ApplicationRecord(url: moved, name: app.name, bundleID: app.bundleID,
        version: app.version, bytes: app.bytes, fileCount: app.fileCount,
        blockedReason: nil, fingerprint: app.fingerprint)
    let outside = await engine.trash(forged, relatedItems: [])
    #expect(outside.results.allSatisfy { !$0.succeeded })
    #expect(FileManager.default.fileExists(atPath: moved.path))
}

@Test func applicationRemovalReportsIndividualRelatedDataFailures() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let relatedURL = try fixture.data("Caches/org.example.editor")
    let engine = fixture.engine()
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)
    try Data("changed user data".utf8).write(to: relatedURL.appendingPathComponent("payload"))
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.results.count == 2)
    #expect(report.results.first { $0.originalURL.path == appURL.path }?.succeeded == true)
    #expect(report.results.first { $0.originalURL.path == relatedURL.path }?.succeeded == false)
    #expect(FileManager.default.fileExists(atPath: relatedURL.path))
}
