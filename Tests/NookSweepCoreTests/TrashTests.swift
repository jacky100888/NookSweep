import Foundation
import Testing
@testable import NookSweepCore

@Test func cleanupUsesSystemTrashAndReportsTheDestination() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache()
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan()
    let report = await engine.trash(result.items)
    defer { for item in report.moved { try? FileManager.default.removeItem(at: item.trashURL) } }
    #expect(report.failures.isEmpty)
    #expect(report.moved.count == 1)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    let moved = try #require(report.moved.first)
    #expect(FileManager.default.fileExists(atPath: moved.trashURL.appendingPathComponent("payload").path))
    #expect(report.bytes >= 4096)
}

@Test func changedContentsArePreserved() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache()
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan()
    try Data("changed".utf8).write(to: directory.appendingPathComponent("payload"))
    let report = await engine.trash(result.items)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: directory.path))
}

@Test func forgedPathsOutsideTheAllowlistAreRefused() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache("Documents/important")
    let item = CleanupItem(url: directory, category: .caches, bytes: 4096, fileCount: 1,
                           modified: .distantPast, state: .eligible, fingerprint: "forged")
    let report = await CleanupEngine(home: fixture.home).trash([item])
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: directory.path))
}

@Test func rootReplacementWithASymlinkIsRefused() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache()
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan()
    let root = fixture.home.appendingPathComponent("Library/Caches")
    let outside = fixture.home.appendingPathComponent("Documents")
    try FileManager.default.moveItem(at: root, to: outside)
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
    let report = await engine.trash(result.items)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("example/payload").path))
}

@Test func appsStartedAfterScanningAreProtected() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache("Library/Caches/com.example.running")
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan()
    let report = await engine.trash(result.items, runningBundleIDs: ["com.example.running"])
    #expect(report.moved.isEmpty)
    #expect(FileManager.default.fileExists(atPath: directory.path))
}

@Test func partialFailureReportsOnlyActualMoves() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache("Library/Caches/success")
    let changed = try fixture.cache("Library/Caches/changed")
    let engine = CleanupEngine(home: fixture.home)
    let result = try await engine.scan()
    try Data("new".utf8).write(to: changed.appendingPathComponent("payload"))
    let report = await engine.trash(result.items)
    defer { for item in report.moved { try? FileManager.default.removeItem(at: item.trashURL) } }
    #expect(report.moved.count == 1)
    #expect(report.failures.count == 1)
    #expect(report.moved.first?.originalURL.lastPathComponent == "success")
    #expect(FileManager.default.fileExists(atPath: changed.path))
}
