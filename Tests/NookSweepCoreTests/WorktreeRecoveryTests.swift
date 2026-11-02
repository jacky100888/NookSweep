import Foundation
import Testing
@testable import NookSweepCore

@Test func recoveryReferencesNeverOverwriteExistingDirectOrSymbolicReferences() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let git = try GitInspection(repository: value.worktree)
    let review = try git.review()
    for kind in ["direct", "symbolic", "dangling"] {
        let name = "refs/nooksweep/recovery/" + UUID().uuidString.lowercased()
        if kind == "direct" {
            try WorktreeFixture.git(["update-ref", name, review.headOID], at: value.primary)
        } else {
            let target = kind == "symbolic" ? "refs/heads/main" : "refs/heads/does-not-exist"
            try WorktreeFixture.git(["symbolic-ref", name, target], at: value.primary)
        }
        let file = git.commonDirectory.appendingPathComponent(name)
        let before = try Data(contentsOf: file)
        #expect(throws: (any Error).self) { try git.createRecoveryReference(expectedHead: review.headOID, refName: name) }
        #expect(try Data(contentsOf: file) == before)
    }
    let absent = "refs/nooksweep/recovery/" + UUID().uuidString.lowercased()
    #expect(throws: (any Error).self) {
        try git.createRecoveryReference(expectedHead: String(repeating: "0", count: 40), refName: absent)
    }
    #expect(!FileManager.default.fileExists(atPath: git.commonDirectory.appendingPathComponent(absent).path))
}

@Test func recoveryReferenceNamespaceCannotFollowParentSymlinks() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let git = try GitInspection(repository: value.worktree)
    let outside = value.fixture.home.appendingPathComponent("private-ref-directory")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: git.commonDirectory.appendingPathComponent("refs/nooksweep"),
                                              withDestinationURL: outside)
    #expect(throws: (any Error).self) { try git.createRecoveryReference(expectedHead: git.currentHeadOID()) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

@Test func recoveryReferenceLeafCannotReplaceDanglingFilesystemSymlink() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let git = try GitInspection(repository: value.worktree)
    let name = "refs/nooksweep/recovery/" + UUID().uuidString.lowercased()
    let leaf = git.commonDirectory.appendingPathComponent(name)
    let outside = value.fixture.home.appendingPathComponent("missing-private-reference")
    try FileManager.default.createDirectory(at: leaf.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: outside)
    let before = try FileManager.default.destinationOfSymbolicLink(atPath: leaf.path)
    #expect(throws: (any Error).self) { try git.createRecoveryReference(expectedHead: git.currentHeadOID(), refName: name) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: leaf.path) == before)
    #expect(!FileManager.default.fileExists(atPath: outside.path))
}

@Test func recoveryPinsDoNotRunHooksOrCreateReflogs() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    let git = try GitInspection(repository: value.worktree)
    let marker = value.fixture.home.appendingPathComponent("hook-was-run")
    let hook = git.commonDirectory.appendingPathComponent("hooks/reference-transaction")
    try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: hook)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
    try WorktreeFixture.git(["config", "core.logAllRefUpdates", "always"], at: value.primary)
    let recovery = try git.createRecoveryReference(expectedHead: git.currentHeadOID())
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(!FileManager.default.fileExists(atPath: git.commonDirectory.appendingPathComponent("logs/" + recovery.refName).path))
    try WorktreeFixture.git(["show-ref", "--verify", recovery.refName], at: value.primary)
}

@Test func recoveryPinPreservesDetachedCommitsThroughFixtureGarbageCollection() throws {
    let value = try WorktreeFixture()
    defer { try? value.fixture.dispose() }
    try WorktreeFixture.git(["checkout", "--detach"], at: value.worktree)
    try Data("detached commit".utf8).write(to: value.worktree.appendingPathComponent("source.txt"))
    try WorktreeFixture.git(["add", "."], at: value.worktree)
    try WorktreeFixture.git(["commit", "--no-gpg-sign", "-m", "測試復原參照保護"], at: value.worktree)
    let git = try GitInspection(repository: value.worktree)
    let recovery = try git.createRecoveryReference(expectedHead: git.currentHeadOID())
    let savedWorktree = value.fixture.home.appendingPathComponent("saved-worktree")
    let savedAdmin = value.fixture.home.appendingPathComponent("saved-admin")
    try FileManager.default.moveItem(at: value.worktree, to: savedWorktree)
    try FileManager.default.moveItem(at: git.administrationDirectory, to: savedAdmin)
    try WorktreeFixture.git(["reflog", "expire", "--expire=now", "--all"], at: value.primary)
    try WorktreeFixture.git(["gc", "--prune=now"], at: value.primary)
    try WorktreeFixture.git(["cat-file", "-e", recovery.headOID + "^{commit}"], at: value.primary)
    // GC 可能移除空的 worktrees 父目錄，還原時須先重建原路徑。
    try FileManager.default.createDirectory(at: git.administrationDirectory.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: savedAdmin, to: git.administrationDirectory)
    try FileManager.default.moveItem(at: savedWorktree, to: value.worktree)
    let restored = try GitInspection(repository: value.worktree)
    #expect(try restored.currentHeadOID() == recovery.headOID)
}
