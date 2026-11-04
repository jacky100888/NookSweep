import Foundation
import Testing
@testable import NookSweep
@testable import NookSweepCore

private let groupDate = Date(timeIntervalSince1970: 1_800_000_000)

private func groupItem(_ name: String, tool: String = "claude", kind: AIDataKind = .cache,
                       state: ItemState = .eligible, days: Int = 90) -> CleanupItem {
    let category: CleanupCategory = switch kind {
    case .cache: .aiCaches
    case .conversation, .localHistory: .aiHistory
    case .oldVersion: .aiVersions
    case .worktree: .aiWorktrees
    }
    return CleanupItem(url: URL(fileURLWithPath: "/AI-Group-Fixture/" + name), category: category,
        bytes: 1024, fileCount: 1, modified: groupDate.addingTimeInterval(-Double(days) * 86400),
        state: state, fingerprint: "fixture",
        aiMetadata: AIItemMetadata(toolID: tool, kind: kind, title: name))
}

@MainActor
private func groupModel(_ items: [CleanupItem]) -> AppModel {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("NookSweep-Groups-" + UUID().uuidString)
    let model = AppModel(engine: CleanupEngine(home: home, activity: { [] },
        trashOperation: { _ in throw CleanupError.refused("測試禁止搬移") }))
    model.scope = .category(.developer)
    model.setDeveloperMode(.ai)
    model.cancelScan()
    model.isScanning = false
    model.eligibleOnly = false
    model.scannedAt = groupDate
    model.result = ScanResult(items: items, warnings: [], inspectedCount: items.count)
    return model
}

@Test @MainActor func aiGroupSelectionRespectsToolKindSearchAndEligibility() {
    let match = groupItem("match-cache")
    let other = groupItem("other-cache")
    let codex = groupItem("match-codex", tool: "codex")
    let history = groupItem("match-history", kind: .conversation)
    let running = groupItem("match-running", state: .running)
    let recent = groupItem("match-recent", state: .recent)
    let blocked = groupItem("match-blocked", state: .blocked("保留"))
    let model = groupModel([match, other, codex, history, running, recent, blocked])
    model.aiCategory = .aiCaches
    model.query = "match"
    model.selected = [history.id]
    model.selectVisibleAIGroup(toolID: "claude", kind: .cache)
    #expect(model.selected == [match.id, history.id])
    #expect(model.hiddenSelectionCount == 1)
}

@Test @MainActor func aiToolGroupSelectionIncludesAllItsVisibleKinds() {
    let cache = groupItem("cache")
    let history = groupItem("history", kind: .conversation)
    let local = groupItem("local", kind: .localHistory)
    let version = groupItem("version", kind: .oldVersion)
    let worktree = groupItem("worktree", kind: .worktree)
    let codex = groupItem("codex", tool: "codex")
    let model = groupModel([cache, history, local, version, worktree, codex])
    model.selectVisibleAIGroup(toolID: "claude")
    #expect(model.selected == Set([cache, history, local, version, worktree].map(\.id)))
    #expect(model.hiddenSelectionCount == 0)
}

@Test @MainActor func aiHistoryGroupSelectionHonorsDatesAndSeparatesLocalHistory() {
    let old = groupItem("old-local", kind: .localHistory, days: 60)
    let newer = groupItem("newer-local", kind: .localHistory, days: 45)
    let conversation = groupItem("conversation", kind: .conversation)
    let model = groupModel([old, newer, conversation])
    model.aiCategory = .aiHistory
    model.historyAgeDays = 60
    model.selectVisibleAIGroup(toolID: "claude", kind: .localHistory)
    #expect(model.selected == [old.id])
}

@Test @MainActor func hiddenSelectionCountsOnlyEligibleItemsOutsideTheCurrentFilter() {
    let cache = groupItem("cache")
    let history = groupItem("history", kind: .conversation)
    let running = groupItem("running", state: .running)
    let model = groupModel([cache, history, running])
    model.selected = [cache.id, history.id, running.id, "missing"]
    model.aiCategory = .aiCaches
    #expect(model.hiddenSelectionCount == 1)
    model.query = "no-matches"
    #expect(model.hiddenSelectionCount == 2)
    model.query = ""
    model.aiCategory = nil
    #expect(model.hiddenSelectionCount == 0)
    model.selected.removeAll()
    #expect(model.hiddenSelectionCount == 0)
}

@Test func aiDataKindKeepsMetadataAndFallsBackToTheCategory() {
    #expect(groupItem("local", kind: .localHistory).aiDataKind == .localHistory)
    let categories: [(CleanupCategory, AIDataKind)] = [(.aiCaches, .cache), (.aiHistory, .conversation),
        (.aiVersions, .oldVersion), (.aiWorktrees, .worktree)]
    for (category, expected) in categories {
        let item = CleanupItem(url: URL(fileURLWithPath: "/AI-Group-Fixture/legacy"), category: category,
            bytes: 1, fileCount: 1, modified: groupDate, state: .eligible, fingerprint: "fixture")
        #expect(item.aiDataKind == expected)
    }
}
