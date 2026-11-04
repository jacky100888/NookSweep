import Darwin
import Foundation

extension ApplicationsEngine {
    public func scan(progress: @escaping @Sendable ([ApplicationRecord], String) -> Void = { _, _ in })
        async throws -> ApplicationScanResult {
        let inventory = try inventory()
        let running = await activity()
        var applications: [ApplicationRecord] = []
        var warnings = inventory.warnings
        let previews = inventory.applications.map { metadata in
            ApplicationRecord(url: metadata.url, name: metadata.name, bundleID: metadata.bundleID,
                version: metadata.version, bytes: 0, fileCount: 0,
                isRunning: running.isRunning(metadata),
                blockedReason: protectionReason(metadata, running: running, allowRunning: true) ?? "正在量測大小，請稍候",
                fingerprint: "")
        }
        progress(previews, "正在量測應用程式大小…")
        for metadata in inventory.applications {
            try Task.checkCancellation()
            do {
                let size = try applicationMeasure(metadata.url)
                applications.append(ApplicationRecord(url: metadata.url, name: metadata.name,
                    bundleID: metadata.bundleID, version: metadata.version, bytes: size.bytes,
                    fileCount: size.fileCount, isRunning: running.isRunning(metadata),
                    blockedReason: protectionReason(metadata, running: running, allowRunning: true),
                    fingerprint: size.fingerprint))
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(metadata.url.path)：\(error.localizedDescription)") }
            let completed = Set(applications.map(\.id))
            progress(applications + previews.filter { !completed.contains($0.id) }, metadata.name)
        }
        return ApplicationScanResult(applications: applications.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }, warnings: warnings)
    }

    func inventory(includeApple: Bool = false) throws -> (applications: [ApplicationMetadata], warnings: [String]) {
        var applications: [ApplicationMetadata] = []
        var warnings: [String] = []
        var visited = Set<String>()
        for root in applicationRoots {
            try Task.checkCancellation()
            do {
                if !FileManager.default.fileExists(atPath: root.path) { continue }
                try applicationValidateAncestors(root)
                let children = try FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: nil).map(\.standardizedFileURL).sorted { $0.path < $1.path }
                var candidates: [URL] = []
                for child in children {
                    do {
                        let type = applicationFileType(try applicationStat(child))
                        guard type == S_IFDIR else { continue }
                        if child.pathExtension.lowercased() == "app" { candidates.append(child) }
                        else {
                            let nested = try FileManager.default.contentsOfDirectory(at: child,
                                includingPropertiesForKeys: nil).map(\.standardizedFileURL)
                            candidates += nested.filter { $0.pathExtension.lowercased() == "app" }
                        }
                    } catch { warnings.append("\(child.path)：\(error.localizedDescription)") }
                }
                for candidate in candidates where visited.insert(candidate.path).inserted {
                    do {
                        try validateApplicationPath(candidate)
                        let metadata = try readMetadata(candidate)
                        if includeApple || !metadata.bundleID.lowercased().hasPrefix("com.apple.") {
                            applications.append(metadata)
                        }
                    } catch { warnings.append("\(candidate.path)：\(error.localizedDescription)") }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("\(root.path)：\(error.localizedDescription)") }
        }
        return (applications, warnings)
    }

    func validateApplicationPath(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard normalized.path == url.path, normalized.pathExtension.lowercased() == "app",
              applicationRoots.contains(where: { root in
                  guard normalized.path.hasPrefix(root.path + "/") else { return false }
                  let relative = normalized.path.dropFirst(root.path.count + 1).split(separator: "/")
                  return relative.count == 1 || (relative.count == 2 &&
                      !relative[0].lowercased().hasSuffix(".app"))
              }) else {
            throw CleanupError.refused("App 不在允許的應用程式目錄，已保留")
        }
        try applicationValidateAncestors(normalized)
        guard applicationFileType(try applicationStat(normalized)) == S_IFDIR else {
            throw CleanupError.refused("App 不是一般資料夾，已保留")
        }
    }

    func readMetadata(_ url: URL) throws -> ApplicationMetadata {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        try applicationValidateAncestors(plistURL)
        guard applicationFileType(try applicationStat(plistURL)) == S_IFREG,
              let dictionary = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: plistURL), options: [], format: nil) as? [String: Any],
              let bundleID = dictionary["CFBundleIdentifier"] as? String,
              bundleID.contains("."), bundleID.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]+$",
                  options: .regularExpression) != nil else {
            throw CleanupError.refused("無法確認有效的 App bundle ID，已保留")
        }
        let fallback = url.deletingPathExtension().lastPathComponent
        let name = (dictionary["CFBundleDisplayName"] as? String) ??
            (dictionary["CFBundleName"] as? String) ?? fallback
        let version = (dictionary["CFBundleShortVersionString"] as? String) ??
            (dictionary["CFBundleVersion"] as? String) ?? "未提供版本"
        return ApplicationMetadata(url: url, name: name.isEmpty ? fallback : name,
                                   bundleID: bundleID, version: version)
    }

    func protectionReason(_ app: ApplicationMetadata, running: ApplicationActivity,
                          allowRunning: Bool = false) -> String? {
        if app.bundleID.lowercased().hasPrefix("com.apple.") { return "Apple 系統應用程式受保護" }
        if app.bundleID == ownBundleID || app.url.path == ownApplicationURL?.path {
            return "NookSweep 無法移除自身"
        }
        if !allowRunning && running.isRunning(app) {
            return "應用程式仍在執行中，請重新掃描後選擇結束或強制結束並移除"
        }
        return nil
    }

    func validateRecord(_ app: ApplicationRecord, allowRunning: Bool = false) async throws -> ApplicationMetadata {
        try validateApplicationPath(app.url)
        let metadata = try readMetadata(app.url)
        guard metadata.bundleID == app.bundleID else {
            throw CleanupError.refused("App 的 bundle ID 已改變，請重新掃描")
        }
        if let reason = protectionReason(metadata, running: await activity(), allowRunning: allowRunning) {
            throw CleanupError.refused(reason)
        }
        guard try applicationMeasure(app.url).fingerprint == app.fingerprint else {
            throw CleanupError.refused("掃描後 App 內容已改變，請重新掃描")
        }
        return metadata
    }
}
