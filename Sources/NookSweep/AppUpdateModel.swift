import Foundation
import NookSweepCore
import SwiftUI

@MainActor
final class AppUpdateModel: ObservableObject {
    @Published var automaticallyChecks = true {
        didSet { defaults.set(automaticallyChecks, forKey: "updates.automaticallyChecks") }
    }
    @Published private(set) var isChecking = false
    @Published private(set) var status = "尚未檢查更新"
    @Published private(set) var latestRelease: AppRelease?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var dismissedVersion: String?
    let currentVersion: String
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let fetchOperation: @Sendable () async throws -> AppRelease
    private var operation: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         now: @escaping @Sendable () -> Date = Date.init,
         fetchOperation: (@Sendable () async throws -> AppRelease)? = nil) {
        self.defaults = defaults
        self.currentVersion = currentVersion ?? "開發版本"
        self.now = now
        self.fetchOperation = fetchOperation ?? { try await fetchLatestRelease() }
        automaticallyChecks = defaults.object(forKey: "updates.automaticallyChecks") as? Bool ?? true
        lastCheckedAt = defaults.object(forKey: "updates.lastCheckedAt") as? Date
        dismissedVersion = defaults.string(forKey: "updates.dismissedVersion")
        latestRelease = defaults.string(forKey: "updates.latestTag").flatMap { AppRelease(tag: $0) }
        if availableRelease != nil { status = "有新版本可下載" }
    }

    deinit { operation?.cancel() }

    var availableRelease: AppRelease? {
        guard let installed = ReleaseVersion(currentVersion), let latestRelease,
              latestRelease.version > installed else { return nil }
        return latestRelease
    }
    var showsUpdateNotice: Bool {
        guard let release = availableRelease else { return false }
        return release.version.description != dismissedVersion
    }

    func checkForUpdates(automatic: Bool = false) {
        guard !isChecking else { return }
        guard let installed = ReleaseVersion(currentVersion) else {
            if !automatic { status = "開發版本不比較公開更新" }
            return
        }
        let date = now()
        if automatic {
            guard automaticallyChecks else { return }
            if let lastCheckedAt {
                let elapsed = date.timeIntervalSince(lastCheckedAt)
                guard elapsed < 0 || elapsed >= 86400 else { return }
            }
        }
        let previousStatus = status
        isChecking = true
        status = "正在檢查更新…"
        lastCheckedAt = date
        defaults.set(date, forKey: "updates.lastCheckedAt")
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await fetchOperation()
                latestRelease = value
                defaults.set(value.tag, forKey: "updates.latestTag")
                status = value.version > installed ? "有新版本 \(value.version) 可下載" : "目前沒有較新版本"
                if !automatic {
                    dismissedVersion = nil
                    defaults.removeObject(forKey: "updates.dismissedVersion")
                }
            } catch {
                status = automatic ? previousStatus : "無法檢查更新，請確認網路連線後再試。"
            }
            isChecking = false
            operation = nil
        }
    }

    func dismissNotice() {
        guard let release = availableRelease else { return }
        dismissedVersion = release.version.description
        defaults.set(dismissedVersion, forKey: "updates.dismissedVersion")
    }
}
