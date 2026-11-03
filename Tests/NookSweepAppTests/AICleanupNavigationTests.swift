import Foundation
import Testing
@testable import NookSweep
@testable import NookSweepCore

private func navigationItem(_ name: String, category: CleanupCategory, bytes: Int64,
    state: ItemState = .eligible) -> CleanupItem {
    CleanupItem(url: URL(fileURLWithPath: "/NookSweep-Navigation-Fixture/" + name),
        category: category, bytes: bytes, fileCount: 1,
        modified: Date().addingTimeInterval(-90 * 86400), state: state, fingerprint: "fixture")
}

private func navigationEngine(home: URL) -> CleanupEngine {
    CleanupEngine(home: home, activity: { [] },
        trashOperation: { _ in throw CleanupError.refused("測試禁止搬移") })
}

private func navigationHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("NookSweep-Navigation-" + UUID().uuidString)
        .resolvingSymlinksInPath()
}

private func populateNavigationHome(_ home: URL) throws {
    let manager = FileManager.default
    let oldDate = Date().addingTimeInterval(-40 * 86400)
    for relative in [".npm/_cacache/fixture/payload", ".codex/log/fixture.log"] {
        let file = home.appendingPathComponent(relative)
        let parent = file.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data("測試資料".utf8).write(to: file)
        try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
        try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: parent.path)
    }
}

@MainActor
private func awaitNavigationScan(_ model: AppModel) async throws {
    let deadline = Date().addingTimeInterval(10)
    while model.isScanning && Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try #require(!model.isScanning, "測試掃描未於十秒內完成")
}

@Test @MainActor func developerAndAIFiltersKeepListTotalsAndSelectionsConsistent() {
    let developer = navigationItem("developer", category: .developer, bytes: 100)
    let cache = navigationItem("cache", category: .aiCaches, bytes: 200)
    let history = navigationItem("history", category: .aiHistory, bytes: 300)
    let indexed = navigationItem("indexed", category: .aiHistory, bytes: 400,
        state: .blocked("對話受資料庫索引管理"))
    let version = navigationItem("version", category: .aiVersions, bytes: 500)
    let worktree = navigationItem("worktree", category: .aiWorktrees, bytes: 600)
    let entries = [developer, cache, history, indexed, version, worktree]
    let result = ScanResult(items: entries, warnings: [], inspectedCount: entries.count)
    let model = AppModel(engine: navigationEngine(home: navigationHome()))
    model.scope = .category(.developer)
    model.result = result

    #expect(model.developerMode == .caches)
    #expect(!model.isAIScope)
    #expect(model.scopedItems.map(\.id) == [developer.id])
    #expect(model.visibleItems.map(\.id) == [developer.id])
    #expect(model.scopeEligibleBytes == developer.bytes)

    model.result = nil
    model.setDeveloperMode(.ai)
    model.result = result
    model.eligibleOnly = false
    #expect(model.isAIScope)
    #expect(model.activeCategory == nil)
    #expect(Set(model.scopedItems.map(\.id)) == Set(entries.dropFirst().map(\.id)))
    #expect(model.scopeEligibleBytes == cache.bytes + history.bytes + version.bytes + worktree.bytes)

    for item in [cache, history, version, worktree] {
        model.aiCategory = item.category
        let expected = item.category == .aiHistory ? [history.id, indexed.id] : [item.id]
        #expect(Set(model.scopedItems.map(\.id)) == Set(expected))
        #expect(Set(model.visibleItems.map(\.id)) == Set(expected))
        #expect(model.activeCategory == item.category)
        #expect(model.scopeEligibleBytes == item.bytes)
        model.selectVisible()
        #expect(model.selected.contains(item.id))
        #expect(!model.selected.contains(indexed.id))
    }
    #expect(model.selected == [cache.id, history.id, version.id, worktree.id])
    model.aiCategory = nil
    #expect(model.selectedBytes == cache.bytes + history.bytes + version.bytes + worktree.bytes)
    #expect(model.selectedItems.allSatisfy { $0.isEligible })
}

@Test @MainActor func changingDeveloperModeRescansAndResetsOldSelection() async throws {
    let home = navigationHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try populateNavigationHome(home)
    let model = AppModel(engine: navigationEngine(home: home))
    model.scope = .category(.developer)
    model.startScan()
    try await awaitNavigationScan(model)
    let ordinary = try #require(model.items.first { $0.category == .developer })
    #expect(model.items.contains { $0.category == .aiCaches })
    model.selected = [ordinary.id]
    model.focusedID = ordinary.id
    model.showDetails = true

    model.setDeveloperMode(.ai)
    #expect(model.developerMode == .ai)
    #expect(model.selected.isEmpty)
    #expect(model.focusedID == nil)
    #expect(!model.showDetails)
    #expect(model.result == nil)
    #expect(model.scannedAt == nil)
    #expect(model.isScanning)
    try await awaitNavigationScan(model)
    #expect(!model.items.isEmpty)
    #expect(model.items.allSatisfy { $0.category.isAI })
    #expect(model.scannedAt != nil)

    model.setDeveloperMode(.caches)
    #expect(model.isScanning)
    try await awaitNavigationScan(model)
    #expect(model.items.contains { $0.id == ordinary.id })
    #expect(model.visibleItems.map(\.id) == [ordinary.id])
}

@Test @MainActor func AIOnlyScanCannotPopulateGeneralPagesDuringOrAfterScanning() async throws {
    let home = navigationHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try populateNavigationHome(home)
    let model = AppModel(engine: navigationEngine(home: home))
    model.scope = .category(.developer)
    model.setDeveloperMode(.ai)
    model.startScan()
    model.scope = .all
    model.scopeDidChange()
    try await awaitNavigationScan(model)
    #expect(model.result == nil)
    #expect(model.scannedAt == nil)
    #expect(model.visibleItems.isEmpty)

    model.scope = .category(.developer)
    model.scopeDidChange()
    model.startScan()
    try await awaitNavigationScan(model)
    #expect(!model.items.isEmpty)
    #expect(model.items.allSatisfy { $0.category.isAI })
    model.selected = Set(model.items.map(\.id))
    model.scope = .all
    model.scopeDidChange()
    #expect(model.result == nil)
    #expect(model.scannedAt == nil)
    #expect(model.selected.isEmpty)
    #expect(model.visibleItems.isEmpty)
}

@Test @MainActor func developerModeCannotChangeWhileAnOperationIsBusy() {
    let item = navigationItem("developer", category: .developer, bytes: 100)
    let model = AppModel(engine: navigationEngine(home: navigationHome()))
    model.scope = .category(.developer)
    model.result = ScanResult(items: [item], warnings: [], inspectedCount: 1)
    model.selected = [item.id]
    for scanning in [true, false] {
        model.isScanning = scanning
        model.isCleaning = !scanning
        model.setDeveloperMode(.ai)
        #expect(model.developerMode == .caches)
        #expect(model.items.map(\.id) == [item.id])
        #expect(model.selected == [item.id])
    }
    model.isScanning = false
    model.isCleaning = false
}
