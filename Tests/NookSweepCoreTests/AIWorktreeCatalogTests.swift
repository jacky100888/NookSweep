import Foundation
import Testing
@testable import NookSweepCore

struct WorktreeFixture {
    let fixture: Fixture
    let primary: URL
    let worktree: URL

    init(primaryInCatalog: Bool = false) throws {
        fixture = try Fixture()
        primary = fixture.home.appendingPathComponent(primaryInCatalog ? ".codex/worktrees/main/repo" : "primary")
        worktree = fixture.home.appendingPathComponent(".codex/worktrees/one/repo")
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: true)
        try Self.git(["init", "-b", "main", primary.path], at: fixture.home)
        try Data("initial".utf8).write(to: primary.appendingPathComponent("source.txt"))
        try Data("ignored/\n".utf8).write(to: primary.appendingPathComponent(".gitignore"))
        try Self.git(["add", "."], at: primary)
        try Self.git(["commit", "--no-gpg-sign", "-m", "測試初始版本"], at: primary)
        if !primaryInCatalog {
            try FileManager.default.createDirectory(at: worktree.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try Self.git(["worktree", "add", "-b", "topic", worktree.path], at: primary)
        }
    }

    static func git(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
                             "-c", "user.name=Jacky", "-c", "user.email=fixture@example.invalid"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CleanupError.refused(String(decoding: data, as: UTF8.self))
        }
    }
}

@Test func cleanMergedLinkedWorktreeIncludesItsGitAdministrationBackup() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let entry = try #require(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home))
    #expect(entry.preservationReason == nil)
    #expect(entry.category == .aiWorktrees)
    #expect(entry.relatedURLs.count == 1)
    #expect(entry.relatedURLs.first?.deletingLastPathComponent().lastPathComponent == "worktrees")
    #expect(try AIWorktreeCatalog.candidates(home: value.fixture.home).count == 1)
}

@Test func worktreeCleanupCanRestoreTheGitRegistrationFromTrash() async throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let entry = try #require(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home))
    try ageFixtureData([value.worktree] + entry.relatedURLs)
    let engine = CleanupEngine(home: value.fixture.home, activity: { [] })
    let result = try await engine.scan(categories: [.aiWorktrees])
    let item = try #require(result.items.first)
    #expect(item.isEligible, "\(item.state.reason ?? "")")
    #expect(await engine.trash([item]).moved.isEmpty)
    let report = await engine.trash([item], allowAIWorktrees: true)
    defer {
        for moved in report.moved {
            try? FileManager.default.removeItem(at: moved.trashURL)
            for related in moved.relatedMoves { try? FileManager.default.removeItem(at: related.trashURL) }
        }
    }
    #expect(report.failures.isEmpty, "\(report.failures)")
    let moved = try #require(report.moved.first)
    #expect(moved.relatedMoves.count == 1)
    #expect(!FileManager.default.fileExists(atPath: value.worktree.path))
    for related in moved.relatedMoves {
        try FileManager.default.moveItem(at: related.trashURL, to: related.originalURL)
    }
    try FileManager.default.moveItem(at: moved.trashURL, to: moved.originalURL)
    try WorktreeFixture.git(["status", "--porcelain"], at: value.worktree)
}

@Test func dirtyIgnoredAndUntrackedWorktreeDataStayProtected() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    for path in ["source.txt", "untracked.txt", "ignored/payload.txt"] {
        let file = value.worktree.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("changed".utf8).write(to: file)
        #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?.preservationReason != nil)
        if path == "source.txt" {
            try WorktreeFixture.git(["restore", "source.txt"], at: value.worktree)
        } else { try FileManager.default.removeItem(at: file) }
    }
}

@Test func lockedAndUnmergedWorktreesStayProtected() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    try WorktreeFixture.git(["worktree", "lock", value.worktree.path], at: value.primary)
    #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?.preservationReason != nil)
    try WorktreeFixture.git(["worktree", "unlock", value.worktree.path], at: value.primary)
    let clean = try #require(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home))
    let admin = try #require(clean.relatedURLs.first)
    let merging = admin.appendingPathComponent("MERGE_HEAD")
    try Data("in-progress".utf8).write(to: merging)
    #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?
        .preservationReason?.contains("尚未完成") == true)
    try FileManager.default.removeItem(at: merging)
    try Data("new commit".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try WorktreeFixture.git(["add", "."], at: value.worktree)
    try WorktreeFixture.git(["commit", "--no-gpg-sign", "-m", "尚未合併"], at: value.worktree)
    #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?.preservationReason != nil)
}

@Test func primaryRepositoryAndEscapingMetadataStayProtected() throws {
    let primary = try WorktreeFixture(primaryInCatalog: true)
    defer { try? primary.fixture.dispose() }
    #expect(try AIWorktreeCatalog.entry(for: primary.primary, home: primary.fixture.home)?.preservationReason != nil)
    let linked = try WorktreeFixture()
    defer { try? linked.fixture.dispose() }
    let entry = try #require(try AIWorktreeCatalog.entry(for: linked.worktree, home: linked.fixture.home))
    let admin = try #require(entry.relatedURLs.first)
    let metadata = admin.appendingPathComponent("gitdir")
    let outside = linked.fixture.home.appendingPathComponent("private-metadata")
    try Data((linked.worktree.appendingPathComponent(".git").path + "\n").utf8).write(to: outside)
    try FileManager.default.removeItem(at: metadata)
    try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: outside)
    let protected = try #require(try AIWorktreeCatalog.entry(for: linked.worktree, home: linked.fixture.home))
    #expect(protected.preservationReason != nil)
    #expect(protected.relatedURLs.isEmpty)
}

@Test func worktreeIndexFlagsCannotHideChangedFiles() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    for flag in ["--assume-unchanged", "--skip-worktree"] {
        try WorktreeFixture.git(["update-index", flag, "source.txt"], at: value.worktree)
        #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?.preservationReason != nil)
        try WorktreeFixture.git(["update-index", "--no-assume-unchanged", "--no-skip-worktree", "source.txt"],
                                at: value.worktree)
    }
}

@Test func gitInspectionDoesNotExecuteConfiguredFiltersOrFSMonitor() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let marker = value.fixture.home.appendingPathComponent("unexpected-script-execution")
    try Data("source.txt filter=probe\n".utf8).write(to: value.worktree.appendingPathComponent(".gitattributes"))
    try WorktreeFixture.git(["add", ".gitattributes"], at: value.worktree)
    try WorktreeFixture.git(["commit", "--no-gpg-sign", "-m", "測試 filter 屬性"], at: value.worktree)
    try WorktreeFixture.git(["config", "filter.probe.clean", "touch \(marker.path); cat"], at: value.worktree)
    try WorktreeFixture.git(["config", "filter.probe.process", "touch \(marker.path)"], at: value.worktree)
    try WorktreeFixture.git(["config", "filter.probe.required", "true"], at: value.worktree)
    try WorktreeFixture.git(["config", "core.fsmonitor", "touch \(marker.path)"], at: value.worktree)
    try Data("modified".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    #expect(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home)?.preservationReason != nil)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func worktreeConfigurationCannotRedirectInspectionToCleanPrimary() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    try Data("linked worktree has private changes".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try WorktreeFixture.git(["config", "extensions.worktreeConfig", "true"], at: value.primary)
    try WorktreeFixture.git(["config", "--worktree", "core.worktree", value.primary.path], at: value.worktree)
    let entry = try #require(try AIWorktreeCatalog.entry(for: value.worktree, home: value.fixture.home))
    #expect(entry.preservationReason != nil)
    #expect(entry.relatedURLs.isEmpty)
}
