import Foundation
import Testing
@testable import NookSweep
@testable import NookSweepCore

private let updateReferenceDate = Date(timeIntervalSince1970: 1_800_000_000)

private actor UpdateCallCount {
    var count = 0
    func fetch(_ tag: String = "v1.8.0") -> AppRelease {
        count += 1
        return AppRelease(tag: tag)!
    }
}

private func updateDefaults() -> (String, UserDefaults) {
    let name = "NookSweep-UpdateTests-" + UUID().uuidString
    return (name, UserDefaults(suiteName: name)!)
}

@MainActor
private func awaitUpdate(_ model: AppUpdateModel) async throws {
    let deadline = Date().addingTimeInterval(60)
    while model.isChecking && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(!model.isChecking, "更新檢查未於一分鐘內完成")
}

@Test @MainActor func updateModelCachesNewReleaseAndRemembersDismissalUntilManualCheck() async throws {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let calls = UpdateCallCount()
    let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: { await calls.fetch() })
    model.checkForUpdates()
    try await awaitUpdate(model)
    #expect(model.availableRelease?.tag == "v1.8.0")
    #expect(model.showsUpdateNotice)
    #expect(model.lastCheckedAt == updateReferenceDate)
    #expect(defaults.string(forKey: "updates.latestTag") == "v1.8.0")
    model.dismissNotice()
    #expect(!model.showsUpdateNotice)

    let reopened = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: { await calls.fetch() })
    #expect(reopened.availableRelease?.tag == "v1.8.0")
    #expect(!reopened.showsUpdateNotice)
    reopened.checkForUpdates(automatic: true)
    try await awaitUpdate(reopened)
    #expect(await calls.count == 1)
    reopened.checkForUpdates()
    try await awaitUpdate(reopened)
    #expect(reopened.showsUpdateNotice)
    #expect(await calls.count == 2)
}

@Test @MainActor func updateModelAutomaticChecksUseTwentyFourHourBoundaryAndHandleClockRollback() async throws {
    for elapsed: TimeInterval in [-1, 0, 86399, 86400] {
        let (name, defaults) = updateDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(updateReferenceDate.addingTimeInterval(-elapsed), forKey: "updates.lastCheckedAt")
        let calls = UpdateCallCount()
        let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
            fetchOperation: { await calls.fetch() })
        model.checkForUpdates(automatic: true)
        try await awaitUpdate(model)
        #expect(await calls.count == (elapsed < 0 || elapsed >= 86400 ? 1 : 0))
    }
}

@Test @MainActor func updateModelManualChecksWorkWhenAutomaticChecksAreDisabled() async throws {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(false, forKey: "updates.automaticallyChecks")
    defaults.set(updateReferenceDate, forKey: "updates.lastCheckedAt")
    let calls = UpdateCallCount()
    let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: { await calls.fetch() })
    #expect(!model.automaticallyChecks)
    model.checkForUpdates(automatic: true)
    try await awaitUpdate(model)
    #expect(await calls.count == 0)
    model.checkForUpdates()
    try await awaitUpdate(model)
    #expect(await calls.count == 1)
    model.automaticallyChecks = true
    #expect(defaults.bool(forKey: "updates.automaticallyChecks"))
}

@Test @MainActor func updateModelFailuresKeepCachedReleaseAndAutomaticChecksStayQuiet() async throws {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("v1.8.0", forKey: "updates.latestTag")
    let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: { throw URLError(.notConnectedToInternet) })
    let previousStatus = model.status
    model.checkForUpdates(automatic: true)
    try await awaitUpdate(model)
    #expect(model.status == previousStatus)
    #expect(model.availableRelease?.tag == "v1.8.0")
    model.checkForUpdates()
    try await awaitUpdate(model)
    #expect(model.status.contains("無法"))
    #expect(model.availableRelease?.tag == "v1.8.0")
}

@Test @MainActor func updateModelNeverPromptsForEqualOrOlderRelease() async throws {
    for tag in ["v1.7.0", "v1.7.1"] {
        let (name, defaults) = updateDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let calls = UpdateCallCount()
        let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
            fetchOperation: { await calls.fetch(tag) })
        model.checkForUpdates()
        try await awaitUpdate(model)
        #expect(model.availableRelease == nil)
        #expect(!model.showsUpdateNotice)
        #expect(model.status.contains("沒有較新版本"))
    }
}

@Test @MainActor func updateModelCoalescesChecksWhileARequestIsRunning() async throws {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    let calls = UpdateCallCount()
    let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: {
            try await Task.sleep(for: .milliseconds(20))
            return await calls.fetch()
        })
    model.checkForUpdates()
    model.checkForUpdates()
    try await awaitUpdate(model)
    #expect(await calls.count == 1)
}

@Test @MainActor func updateModelDoesNotCompareDevelopmentBuildsOrTrustMalformedCache() {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("https://example.com", forKey: "updates.latestTag")
    let model = AppUpdateModel(defaults: defaults, currentVersion: nil,
        fetchOperation: { Issue.record("開發版本不應讀取公開更新"); return AppRelease(tag: "v1.8.0")! })
    model.checkForUpdates()
    #expect(!model.isChecking)
    #expect(model.availableRelease == nil)
}

@Test @MainActor func updateModelPromptsAgainForANewerVersionAfterDismissingThePreviousOne() async throws {
    let (name, defaults) = updateDefaults()
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("1.8.0", forKey: "updates.latestTag")
    defaults.set("1.8.0", forKey: "updates.dismissedVersion")
    let calls = UpdateCallCount()
    let model = AppUpdateModel(defaults: defaults, currentVersion: "1.7.1", now: { updateReferenceDate },
        fetchOperation: { await calls.fetch("v1.9.0") })
    #expect(!model.showsUpdateNotice)
    model.checkForUpdates(automatic: true)
    try await awaitUpdate(model)
    #expect(model.availableRelease?.tag == "v1.9.0")
    #expect(model.showsUpdateNotice)
}
