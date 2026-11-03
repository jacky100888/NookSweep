import Foundation
import Testing
@testable import NookSweepCore

private let opencodeToolOutput = "tool_0123456789abABCDEFGHIJKLMN"

private func opencodeFixtureEngine(_ fixture: Fixture,
    activity: @escaping @Sendable () -> Set<String> = { [] }) -> CleanupEngine {
    let trash = fixture.home.appendingPathComponent("fixture-trash")
    return CleanupEngine(home: fixture.home, activity: activity, trashOperation: { source in
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    })
}

@Test func opencodeKnownCachesAreGroupedAndRevalidatedWithoutOverlap() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let paths = [".cache/opencode/models.json", ".local/share/opencode/log/dev.log",
        ".local/share/opencode/log/opencode.log", ".local/share/opencode/log/opencode-cli.alpha_1.log",
        ".local/share/opencode/log/2026-11-03T123456.log",
        ".local/share/opencode/tool-output/\(opencodeToolOutput)"]
    let urls = try paths.map { try fixture.aiFile($0) }
    let engine = opencodeFixtureEngine(fixture)
    let result = try await engine.scan(categories: [.aiCaches])
    #expect(Set(result.items.map(\.url.path)) == Set(urls.map(\.path)))
    #expect(result.warnings.isEmpty)
    for item in result.items {
        #expect(item.isEligible)
        #expect(item.aiToolID == "opencode")
        #expect(item.aiMetadata?.kind == .cache)
        let entry = try #require(try await engine.catalogEntry(for: item.url))
        #expect(entry.metadata == item.aiMetadata)
        #expect(entry.category == .aiCaches && entry.preservationReason == nil)
        #expect(!result.items.contains { $0.url != item.url && $0.url.path.hasPrefix(item.url.path + "/") })
    }
}

@Test func opencodeUnknownFormatsStayVisibleWithoutMakingNestedDataDisposable() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let paths = [".cache/opencode/bin", ".cache/opencode/npm", ".cache/opencode/package.json",
        ".cache/opencode/version", ".cache/opencode/auth.json", ".cache/opencode/cache.db",
        ".local/share/opencode/log/notes.txt", ".local/share/opencode/log/opencode-.log",
        ".local/share/opencode/log/2026-11-03T12:34:56.log",
        ".local/share/opencode/log/auth.json", ".local/share/opencode/tool-output/tool_invalid",
        ".local/share/opencode/tool-output/tool_0123456789ABABCDEFGHIJKLMN"]
    let unknown = try paths.map { try fixture.aiFile($0) }
    let nested = try fixture.aiFile(".cache/opencode/node_modules/example/main.js")
    let wrongType = try fixture.aiFile(".cache/opencode/models.json/private.txt")
    let logDirectory = try fixture.aiFile(".local/share/opencode/log/dev.log/private.txt")
    try ageFixtureData([fixture.home])
    let result = try await opencodeFixtureEngine(fixture).scan(categories: [.aiCaches])
    let expected = unknown + [nested.deletingLastPathComponent().deletingLastPathComponent(),
        wrongType.deletingLastPathComponent(), logDirectory.deletingLastPathComponent()]
    #expect(Set(result.items.map(\.url.path)) == Set(expected.map(\.path)))
    #expect(result.items.allSatisfy { !$0.isEligible && $0.state.reason != nil })
    #expect(result.items.allSatisfy { $0.aiToolID == "opencode" && $0.aiMetadata?.kind == .cache })
    #expect(!result.items.contains { [nested, wrongType, logDirectory].contains($0.url) })
}

@Test func opencodeSnapshotsRepositoriesAndDatabasesRemainProtectedAfterOptIn() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let snapshot = try fixture.aiFile(".local/share/opencode/snapshot/project/objects/preserved")
    let repository = try fixture.aiFile(".local/share/opencode/repos/project/source.swift")
    let database = try fixture.aiFile(".local/share/opencode/opencode.db")
    let auth = try fixture.aiFile(".local/share/opencode/auth.json")
    try ageFixtureData([fixture.home])
    let engine = opencodeFixtureEngine(fixture)
    let result = try await engine.scan(includeAIHistory: true, manualWorktreeReview: true)
    let snapshots = try #require(result.items.first { $0.url.lastPathComponent == "snapshot" })
    let repositories = try #require(result.items.first { $0.url.lastPathComponent == "repos" })
    let indexed = try #require(result.items.first { $0.url == database })
    #expect(snapshots.category == .aiHistory && snapshots.aiMetadata?.kind == .localHistory)
    #expect(repositories.category == .aiWorktrees && repositories.aiMetadata?.kind == .worktree)
    #expect([snapshots, repositories, indexed].allSatisfy { !$0.isEligible && $0.state.reason != nil })
    #expect(!result.items.contains { $0.url == auth })
    let report = await engine.trash([snapshots, repositories, indexed], allowAIHistory: true,
        allowAIWorktrees: true, manualWorktreeReview: true)
    #expect(report.moved.isEmpty)
    #expect(report.failures.count == 3)
    #expect([snapshot, repository, database, auth].allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
}

@Test func opencodeRecentAndRunningToolsPreventCleanupIncludingTheFinalActivityGate() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let recent = try fixture.aiFile(".cache/opencode/models.json", days: 2)
    let old = try fixture.aiFile(".local/share/opencode/log/dev.log")
    let engine = opencodeFixtureEngine(fixture)
    let normal = try await engine.scan(categories: [.aiCaches])
    #expect(normal.items.first { $0.url == recent }?.state == .recent)
    let item = try #require(normal.items.first { $0.url == old })
    #expect(item.isEligible)
    let running = try await engine.scan(categories: [.aiCaches], runningAITools: ["opencode"])
    #expect(running.items.count == 2 && running.items.allSatisfy { $0.state == .running })
    let activityEngine = opencodeFixtureEngine(fixture, activity: { ["opencode"] })
    let report = await activityEngine.trash([item])
    #expect(report.moved.isEmpty && report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: old.path))
}

@Test func opencodeChangedFilesAreNotMovedFromAnOutdatedPreview() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let file = try fixture.aiFile(".cache/opencode/models.json")
    let engine = opencodeFixtureEngine(fixture)
    let scan = try await engine.scan(categories: [.aiCaches])
    let item = try #require(scan.items.first { $0.url == file })
    #expect(item.isEligible)
    try Data("changed".utf8).write(to: file)
    let report = await engine.trash([item])
    #expect(report.moved.isEmpty && report.failures.count == 1)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test(arguments: [".cache/opencode", ".local/share/opencode", ".local/share/opencode/log",
    ".local/share/opencode/tool-output"])
func opencodeSymbolicRootsCannotExposeOutsideData(_ rootPath: String) async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let leaf: String
    switch rootPath {
    case ".cache/opencode": leaf = "models.json"
    case ".local/share/opencode": leaf = "log/dev.log"
    case ".local/share/opencode/log": leaf = "dev.log"
    default: leaf = opencodeToolOutput
    }
    let outside = try fixture.aiFile("Documents/important/" + leaf)
    let root = fixture.home.appendingPathComponent(rootPath)
    try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root,
        withDestinationURL: fixture.home.appendingPathComponent("Documents/important"))
    let engine = opencodeFixtureEngine(fixture)
    let result = try await engine.scan(includeAIHistory: true)
    #expect(result.items.allSatisfy { !$0.isEligible })
    #expect(try await engine.catalogEntry(for: root.appendingPathComponent(leaf)) == nil)
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func opencodeSymbolicLeavesCannotBeRevalidatedAsDisposableFiles() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let outside = try fixture.aiFile("Documents/private.txt")
    let paths = [".cache/opencode/models.json", ".local/share/opencode/log/dev.log",
        ".local/share/opencode/tool-output/\(opencodeToolOutput)"]
    let engine = opencodeFixtureEngine(fixture)
    for path in paths {
        let linked = fixture.home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        #expect(try await engine.catalogEntry(for: linked) == nil)
    }
    let result = try await engine.scan(categories: [.aiCaches])
    #expect(result.items.allSatisfy { !$0.isEligible })
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func opencodeCleanupMovesOnlyKnownCachesIntoTheFixtureTrash() async throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let caches = try [".cache/opencode/models.json", ".local/share/opencode/log/dev.log",
        ".local/share/opencode/tool-output/\(opencodeToolOutput)"].map { try fixture.aiFile($0) }
    let preserved = try [".local/share/opencode/auth.json", ".local/share/opencode/opencode.db",
        ".cache/opencode/package.json", ".local/share/opencode/snapshot/project/objects/preserved",
        ".local/share/opencode/repos/project/source.swift"].map { try fixture.aiFile($0) }
    try ageFixtureData([fixture.home])
    let engine = opencodeFixtureEngine(fixture)
    let scan = try await engine.scan(includeAIHistory: true, manualWorktreeReview: true)
    let selected = scan.items.filter(\.isEligible)
    #expect(Set(selected.map(\.url.path)) == Set(caches.map(\.path)))
    let report = await engine.trash(selected)
    #expect(report.failures.isEmpty)
    #expect(Set(report.moved.map(\.originalURL.path)) == Set(caches.map(\.path)))
    #expect(report.moved.allSatisfy { $0.trashURL.deletingLastPathComponent() == fixture.home.appendingPathComponent("fixture-trash") })
    #expect(report.moved.allSatisfy { FileManager.default.fileExists(atPath: $0.trashURL.path) })
    #expect(caches.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    #expect(preserved.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
}
