import Darwin
import Foundation

private func applicationOwnershipKey(_ value: String) -> String {
    value.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .precomposedStringWithCanonicalMapping
}

extension ApplicationsEngine {
    public func relatedData(for app: ApplicationRecord) async throws -> [ApplicationRelatedItem] {
        try validateApplicationPath(app.url)
        let metadata = try readMetadata(app.url)
        guard metadata.bundleID == app.bundleID else {
            throw CleanupError.refused("App 已改變，請重新掃描")
        }
        return try relatedCandidates(metadata)
    }

    func relatedCandidates(_ metadata: ApplicationMetadata) throws -> [ApplicationRelatedItem] {
        let installed = try inventory(includeApple: true)
        let roots = [("Caches", "快取"), ("Preferences", "偏好設定"),
                     ("Application Support", "應用程式資料"), ("Logs", "記錄檔"),
                     ("Containers", "沙盒資料"), ("Saved Application State", "視窗狀態")]
        let genericNames: Set<String> = ["app", "application", "applications", "helper", "electron",
            "google", "microsoft", "adobe", "apple", "openai", "jetbrains", "shared", "common"]
        var result: [ApplicationRelatedItem] = []
        var seen = Set<String>()
        for (rootName, label) in roots {
            let root = home.appendingPathComponent("Library/\(rootName)")
            let suffix = rootName == "Preferences" ? ".plist" :
                (rootName == "Saved Application State" ? ".savedState" : "")
            var owners: [String: Set<String>] = [:]
            for app in installed.applications + [metadata] {
                let tokens = rootName == "Containers" ? [app.bundleID] : app.names.union([app.bundleID])
                for token in tokens {
                    owners[applicationOwnershipKey(token + suffix), default: []].insert(app.bundleID)
                }
            }
            let sharedReason = "多個 App 的識別碼或名稱對應此路徑，無法證明資料專用，已保留"
            let identifier = metadata.bundleID + suffix
            let identifierReason = (owners[applicationOwnershipKey(identifier)]?.count ?? 0) > 1
                ? sharedReason : nil
            var matches = [(identifier, false, identifierReason)]
            if rootName != "Containers" {
                for name in metadata.names.sorted() where !name.isEmpty &&
                    name != "." && name != ".." && !name.contains("/") && !name.contains("\\") {
                    let otherIDs = owners[applicationOwnershipKey(name + suffix)] ?? []
                    let reason: String?
                    if otherIDs.count > 1 { reason = sharedReason }
                    else if !installed.warnings.isEmpty { reason = "無法完整確認名稱唯一性，已保留" }
                    else if name.count < 3 || genericNames.contains(applicationOwnershipKey(name)) {
                        reason = "名稱可能由多個 App 共用，無法證明專用，已保留"
                    } else { reason = nil }
                    matches.append((name + suffix, true, reason))
                }
            }
            for (name, byName, reason) in matches {
                let url = root.appendingPathComponent(name)
                guard seen.insert(applicationOwnershipKey(url.path)).inserted else { continue }
                do { _ = try applicationStat(url) }
                catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
                    continue
                } catch {
                    result.append(ApplicationRelatedItem(url: url, category: label, bytes: 0,
                        blockedReason: error.localizedDescription, fingerprint: "", matchedByName: byName))
                    continue
                }
                do {
                    try validateRelatedPath(url, metadata: metadata)
                    let measurement = try applicationMeasure(url)
                    result.append(ApplicationRelatedItem(url: url, category: label,
                        bytes: measurement.bytes, blockedReason: reason,
                        fingerprint: measurement.fingerprint, matchedByName: byName))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    result.append(ApplicationRelatedItem(url: url, category: label, bytes: 0,
                        blockedReason: error.localizedDescription, fingerprint: "", matchedByName: byName))
                }
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    func validateRelatedPath(_ url: URL, metadata: ApplicationMetadata) throws {
        let allowedRoots = ["Caches", "Preferences", "Application Support", "Logs", "Containers",
                            "Saved Application State"].map { home.appendingPathComponent("Library/\($0)") }
        guard url.path == url.standardizedFileURL.path,
              let root = allowedRoots.first(where: { url.deletingLastPathComponent().path == $0.path }) else {
            throw CleanupError.refused("相關資料不在允許範圍，已保留")
        }
        let suffix = root.lastPathComponent == "Preferences" ? ".plist" :
            (root.lastPathComponent == "Saved Application State" ? ".savedState" : "")
        let name = url.lastPathComponent
        let exactID = name == metadata.bundleID + suffix
        let exactName = root.lastPathComponent != "Containers" && metadata.names.contains {
            !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && name == $0 + suffix
        }
        guard exactID || exactName else {
            throw CleanupError.refused("相關資料未精確對應此 App，已保留")
        }
        try applicationValidateAncestors(url)
    }
}
