import Foundation
import Testing
@testable import NookSweepCore

@Test func changedDirectFilesArePreservedDespiteURLResourceCaching() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let logs = fixture.home.appendingPathComponent("Library/Logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let file = logs.appendingPathComponent("direct.log")
    try Data("old".utf8).write(to: file)
    try FileManager.default.setAttributes([
        .modificationDate: Date().addingTimeInterval(-40 * 86400)
    ], ofItemAtPath: file.path)
    let engine = CleanupEngine(home: fixture.home)
    let scanned = try await engine.scan()
    let item = try #require(scanned.items.first)
    #expect(item.isEligible)
    // 同一個 inode 內改寫，避免 atomic write 換 inode 遮住 URL 的中繼資料快取問題。
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("changed after scan".utf8))
    try handle.close()
    let report = await engine.trash([item])
    defer { for moved in report.moved { try? FileManager.default.removeItem(at: moved.trashURL) } }
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func cacheMarkersAndLocksAreNotCleanupTargets() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let root = fixture.home.appendingPathComponent(".cache/uv")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for name in [".lock", "build.lock", "CACHEDIR.TAG", ".gitignore", ".DS_Store"] {
        let file = root.appendingPathComponent(name)
        try Data(repeating: 65, count: 4096).write(to: file)
        try FileManager.default.setAttributes([
            .modificationDate: Date().addingTimeInterval(-10 * 86400)
        ], ofItemAtPath: file.path)
    }
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.count == 5)
    #expect(result.items.allSatisfy { !$0.isEligible })
}

@Test func emptyFoldersAreVisibleButNotSelectable() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache()
    try FileManager.default.removeItem(at: directory.appendingPathComponent("payload"))
    try FileManager.default.setAttributes([
        .modificationDate: Date().addingTimeInterval(-10 * 86400)
    ], ofItemAtPath: directory.path)
    let result = try await CleanupEngine(home: fixture.home).scan()
    let item = try #require(result.items.first)
    #expect(item.bytes == 0)
    #expect(!item.isEligible)
}
