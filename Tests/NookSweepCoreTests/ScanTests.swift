import Foundation
import Testing
@testable import NookSweepCore

struct Fixture {
    let home: URL
    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookSweepTests-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    func dispose() throws { try FileManager.default.removeItem(at: home) }
    @discardableResult
    func cache(_ path: String = "Library/Caches/example", days: Int = 10) throws -> URL {
        let directory = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("payload")
        try Data(repeating: 65, count: 4096).write(to: file)
        let date = Date().addingTimeInterval(-Double(days) * 86400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
        return directory
    }
}

@Test func oldCachesAreEligibleAndMeasured() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache()
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.warnings.isEmpty, "\(result.warnings)")
    #expect(result.items.count == 1)
    let item = try #require(result.items.first)
    #expect(item.isEligible)
    #expect(item.bytes >= 4096)
    #expect(item.fileCount == 1)
}

@Test func recentNestedFilesProtectTheWholeFolder() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let directory = try fixture.cache()
    try Data("new".utf8).write(to: directory.appendingPathComponent("recent"))
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.first?.state == .recent)
}

@Test func logsRequireThirtyDays() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache("Library/Logs/recent", days: 10)
    try fixture.cache("Library/Logs/old", days: 40)
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.first(where: { $0.name == "recent" })?.state == .recent)
    #expect(result.items.first(where: { $0.name == "old" })?.isEligible == true)
}

@Test func protectedCachesAndRunningAppsCannotBeSelected() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache("Library/Caches/com.apple.systempreferences")
    try fixture.cache("Library/Caches/com.example.running")
    let result = try await CleanupEngine(home: fixture.home)
        .scan(runningBundleIDs: ["com.example.running"])
    #expect(result.items.allSatisfy { !$0.isEligible })
    #expect(result.items.contains(where: { $0.state == .running }))
}

@Test func symbolicLinksAreNeverFollowed() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let outside = try fixture.cache("Documents/important")
    let root = fixture.home.appendingPathComponent("Library/Caches")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"),
                                             withDestinationURL: outside)
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.isEmpty)
    #expect(!result.warnings.isEmpty)
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("payload").path))
}

@Test func symlinkedRootsAreRefused() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let outside = try fixture.cache("Documents/important")
    let library = fixture.home.appendingPathComponent("Library")
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Caches"),
                                             withDestinationURL: outside)
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.isEmpty)
    #expect(!result.warnings.isEmpty)
}

@Test func developerCachesAreRecognized() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    try fixture.cache(".npm/_cacache/content-v2")
    let result = try await CleanupEngine(home: fixture.home).scan()
    #expect(result.items.first?.category == .developer)
}

@Test func cancellationStopsScanning() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let task = Task {
        return try await CleanupEngine(home: fixture.home).scan()
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
