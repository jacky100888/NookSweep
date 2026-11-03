import Foundation
import Testing
@testable import NookSweep
@testable import NookSweepCore

private let listReferenceDate = Date(timeIntervalSince1970: 1_800_000_000)
private let listDay: TimeInterval = 86400

private func listItem(_ name: String, age: TimeInterval, bytes: Int64 = 1024,
    state: ItemState = .eligible, category: CleanupCategory = .aiHistory,
    measured: Bool = true, tool: String = "claude") -> CleanupItem {
    CleanupItem(url: URL(fileURLWithPath: "/NookSweep-List-Fixture/" + name),
        category: category, bytes: bytes, fileCount: 1,
        modified: measured ? listReferenceDate.addingTimeInterval(-age) : .distantPast,
        state: state, fingerprint: measured ? "fixture" : "",
        aiMetadata: category.isAI ? AIItemMetadata(toolID: tool,
            kind: category == .aiHistory ? .conversation : .cache, title: name) : nil)
}

@MainActor
private func listModel(_ items: [CleanupItem]) -> AppModel {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("NookSweep-List-" + UUID().uuidString)
    let model = AppModel(engine: CleanupEngine(home: home, activity: { [] },
        trashOperation: { _ in throw CleanupError.refused("測試禁止搬移") }))
    model.scope = .category(.developer)
    model.setDeveloperMode(.ai)
    model.aiCategory = .aiHistory
    model.eligibleOnly = false
    model.scannedAt = listReferenceDate
    model.result = ScanResult(items: items, warnings: [], inspectedCount: items.count)
    return model
}

@Test @MainActor func historyDateFiltersUseInclusiveFifteenThirtyAndSixtyDayBoundaries() {
    let entries = [
        listItem("future", age: -1, state: .recent),
        listItem("before15", age: 15 * listDay - 1, state: .recent),
        listItem("at15", age: 15 * listDay, state: .recent),
        listItem("before30", age: 30 * listDay - 1, state: .recent),
        listItem("at30", age: 30 * listDay),
        listItem("before60", age: 60 * listDay - 1),
        listItem("at60", age: 60 * listDay),
        listItem("unknown", age: 0, state: .blocked("未取得日期"), measured: false)
    ]
    let model = listModel(entries)
    #expect(model.historyAgeDays == 0)
    #expect(Set(model.visibleItems.map(\.name)) == Set(entries.map(\.name)))
    let expected: [(Int, Set<String>)] = [
        (15, ["at15", "before30", "at30", "before60", "at60"]),
        (30, ["at30", "before60", "at60"]),
        (60, ["at60"])
    ]
    for (days, names) in expected {
        model.historyAgeDays = days
        #expect(Set(model.visibleItems.map(\.name)) == names)
    }
    model.historyAgeDays = 15
    #expect(model.visibleItems.first { $0.name == "at15" }?.state == .recent)
    #expect(CleanupCategory.aiHistory.minimumDays == 30)
}

@Test @MainActor func historyDateFiltersDoNotHideRecentDataInOtherScopes() {
    let history = listItem("recent-history", age: 2 * listDay, state: .recent)
    let old = listItem("old-history", age: 90 * listDay)
    let cache = listItem("recent-cache", age: 2 * listDay, state: .recent, category: .aiCaches)
    let ordinary = listItem("ordinary-log", age: 2 * listDay, state: .recent, category: .logs)
    let model = listModel([history, old, cache, ordinary])
    model.historyAgeDays = 60
    #expect(model.visibleItems.map(\.id) == [old.id])
    model.aiCategory = nil
    #expect(Set(model.visibleItems.map(\.id)) == [history.id, old.id, cache.id])
    model.scope = .all
    model.scopeDidChange()
    model.eligibleOnly = false
    #expect(Set(model.visibleItems.map(\.id)) == [history.id, old.id, cache.id, ordinary.id])
}

@Test @MainActor func listSortingUsesDateDirectionsStableTiesAndUnknownDatesLast() {
    let recent = listItem("recent", age: listDay, bytes: 2000)
    let tieZ = listItem("z-tie", age: 30 * listDay, bytes: 1000)
    let tieA = listItem("a-tie", age: 30 * listDay, bytes: 500)
    let oldest = listItem("oldest", age: 60 * listDay, bytes: 3000)
    let unknown = listItem("unknown", age: 0, bytes: 0, state: .blocked("未取得日期"), measured: false)
    let model = listModel([tieZ, unknown, recent, oldest, tieA])
    let bySize = [oldest.id, recent.id, tieZ.id, tieA.id, unknown.id]
    #expect(model.visibleItems.map(\.id) == bySize)
    #expect(model.dateSortOrder == nil)
    let sizeDescription = model.sortDescription

    model.sortByDate()
    #expect(model.dateSortOrder == .forward)
    #expect(model.visibleItems.map(\.id) == [oldest.id, tieA.id, tieZ.id, recent.id, unknown.id])
    let oldestDescription = model.sortDescription
    #expect(oldestDescription != sizeDescription)
    model.sortByDate()
    #expect(model.dateSortOrder == .reverse)
    #expect(model.visibleItems.map(\.id) == [recent.id, tieA.id, tieZ.id, oldest.id, unknown.id])
    #expect(model.sortDescription != oldestDescription)

    model.sortBySize()
    #expect(model.visibleItems.map(\.id) == bySize)
    #expect(model.dateSortOrder == nil)
    #expect(model.sortDescription == sizeDescription)
    model.sortBySize()
    #expect(model.visibleItems.map(\.id) == [unknown.id, tieA.id, tieZ.id, recent.id, oldest.id])
    #expect(model.sortDescription != sizeDescription)

    model.sortOrder = [KeyPathComparator(\CleanupItem.modified, order: .forward)]
    #expect(model.visibleItems.map(\.id) == [oldest.id, tieA.id, tieZ.id, recent.id, unknown.id])
}

@Test @MainActor func selectingFilteredHistoryKeepsExistingSelectionsAndProtectsIndexedData() {
    let recent = listItem("recent", age: 20 * listDay, state: .recent)
    let middle = listItem("middle", age: 45 * listDay)
    let oldest = listItem("oldest", age: 90 * listDay)
    let indexed = listItem("indexed", age: 120 * listDay,
        state: .blocked("對話受資料庫索引管理"), tool: "codex")
    let unknown = listItem("unknown", age: 0, state: .blocked("未取得日期"), measured: false)
    let model = listModel([recent, middle, oldest, indexed, unknown])
    model.historyAgeDays = 30
    model.selectVisible()
    #expect(model.selected == [middle.id, oldest.id])

    model.historyAgeDays = 60
    #expect(Set(model.visibleItems.map(\.id)) == [oldest.id, indexed.id])
    #expect(Set(model.selectedItems.map(\.id)) == [middle.id, oldest.id])
    model.selected.removeAll()
    model.selectVisible()
    #expect(model.selected == [oldest.id])
    model.query = "沒有符合的項目"
    model.selectVisible()
    #expect(model.selected == [oldest.id])

    model.query = ""
    model.historyAgeDays = 15
    model.selectVisible()
    #expect(model.selected == [middle.id, oldest.id])
    #expect(!model.selected.contains(indexed.id))
    #expect(model.selectedItems.allSatisfy { $0.isEligible })
}
