import Darwin
import Foundation

extension ApplicationsEngine {
    public func trash(_ app: ApplicationRecord,
                      relatedItems: [ApplicationRelatedItem] = [],
                      terminationMode: ApplicationTerminationMode = .none) async -> ApplicationRemovalReport {
        var results: [ApplicationRemovalResult] = []
        var seen = Set<String>()
        let selected = relatedItems.filter { seen.insert($0.id).inserted }
        let metadata: ApplicationMetadata
        do {
            try Task.checkCancellation()
            guard app.isRemovable else { throw CleanupError.refused(app.blockedReason ?? "請重新掃描") }
            if terminationMode != .none {
                _ = try await validateRecord(app, allowRunning: true)
                try await terminateOperation(app.url, terminationMode)
                try Task.checkCancellation()
            }
            metadata = try await validateRemovalRecord(app)
            try Task.checkCancellation()
            let destination = try await moveApplicationItem(app.url) {
                _ = try await validateRemovalRecord(app)
            }
            results.append(ApplicationRemovalResult(originalURL: app.url, trashURL: destination,
                                                     bytes: app.bytes, error: nil, needsPermissionHelp: false,
                                                     finderAutomationDenied: false))
        } catch {
            results.append(failed(app.url, error))
            results += selected.map { failed($0.url, CleanupError.refused("App 未移除，相關資料已保留")) }
            return ApplicationRemovalReport(results: results)
        }
        for item in selected {
            do {
                try Task.checkCancellation()
                let current = try await validateRelatedRecord(item, metadata: metadata)
                try Task.checkCancellation()
                let destination = try await moveApplicationItem(item.url) {
                    _ = try await validateRelatedRecord(item, metadata: metadata)
                }
                results.append(ApplicationRemovalResult(originalURL: item.url, trashURL: destination,
                                                         bytes: current.bytes, error: nil, needsPermissionHelp: false,
                                                         finderAutomationDenied: false))
            } catch { results.append(failed(item.url, error)) }
        }
        return ApplicationRemovalReport(results: results)
    }

    private func moveApplicationItem(_ url: URL, revalidate: () async throws -> Void) async throws -> URL {
        do { return try await trashOperation(url) }
        catch {
            guard applicationPermissionFailure(error) != nil, let finderOperation else { throw error }
            try Task.checkCancellation()
            try await revalidate()
            try Task.checkCancellation()
            return try await finderOperation(url)
        }
    }

    private func validateRemovalRecord(_ app: ApplicationRecord) async throws -> ApplicationMetadata {
        let metadata = try await validateRecord(app)
        if let reason = protectionReason(metadata, running: await activity()) {
            throw CleanupError.refused(reason)
        }
        try validateApplicationPath(app.url)
        return metadata
    }

    private func validateRelatedRecord(_ item: ApplicationRelatedItem,
                                       metadata: ApplicationMetadata) async throws -> ApplicationRelatedItem {
        if let reason = protectionReason(metadata, running: await activity()) {
            throw CleanupError.refused(reason)
        }
        try validateRelatedPath(item.url, metadata: metadata)
        let current = try relatedCandidates(metadata).first { $0.id == item.id }
        guard item.isSelectable, let current, current.isSelectable else {
            throw CleanupError.refused(current?.blockedReason ?? "無法確認資料專用，已保留")
        }
        guard current.fingerprint == item.fingerprint else {
            throw CleanupError.refused("掃描後相關資料已改變，請重新掃描")
        }
        if let reason = protectionReason(metadata, running: await activity()) {
            throw CleanupError.refused(reason)
        }
        try validateRelatedPath(item.url, metadata: metadata)
        return current
    }

    private func failed(_ url: URL, _ error: Error) -> ApplicationRemovalResult {
        let details = applicationPermissionFailure(error)
        let message = details?.message ?? error.localizedDescription
        return ApplicationRemovalResult(originalURL: url, trashURL: nil, bytes: 0, error: message,
                                        needsPermissionHelp: details != nil,
                                        finderAutomationDenied: details?.finderAutomationDenied ?? false)
    }
}

func applicationPermissionFailure(_ error: Error) -> (message: String, finderAutomationDenied: Bool)? {
    var current: NSError? = error as NSError
    var visited = Set<ObjectIdentifier>()
    var denied = false
    var finderAutomationDenied = false
    var details: [String] = []
    while let value = current, visited.insert(ObjectIdentifier(value)).inserted {
        details.append("\(value.domain) (\(value.code))：\(value.localizedDescription)")
        if value.domain == NSCocoaErrorDomain &&
            [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(value.code) { denied = true }
        if value.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(value.code) { denied = true }
        if value.domain == NSOSStatusErrorDomain && [-54, -5000, -1743].contains(value.code) { denied = true }
        if value.domain == NSOSStatusErrorDomain && value.code == -1743 { finderAutomationDenied = true }
        current = value.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return denied ? ("權限不足，macOS 拒絕移動此項目。\n" + details.joined(separator: "\n"), finderAutomationDenied) : nil
}
