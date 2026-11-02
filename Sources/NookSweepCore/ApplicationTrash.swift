import Foundation

extension ApplicationsEngine {
    public func trash(_ app: ApplicationRecord,
                      relatedItems: [ApplicationRelatedItem] = []) async -> ApplicationRemovalReport {
        var results: [ApplicationRemovalResult] = []
        var seen = Set<String>()
        let selected = relatedItems.filter { seen.insert($0.id).inserted }
        let metadata: ApplicationMetadata
        do {
            try Task.checkCancellation()
            guard app.isRemovable else { throw CleanupError.refused(app.blockedReason ?? "請重新掃描") }
            metadata = try await validateRecord(app)
            if let reason = protectionReason(metadata, running: await activity()) {
                throw CleanupError.refused(reason)
            }
            try validateApplicationPath(app.url)
            let destination = try trashOperation(app.url)
            results.append(ApplicationRemovalResult(originalURL: app.url, trashURL: destination,
                                                     bytes: app.bytes, error: nil))
        } catch {
            results.append(failed(app.url, error.localizedDescription))
            results += selected.map { failed($0.url, "App 未移除，相關資料已保留") }
            return ApplicationRemovalReport(results: results)
        }
        for item in selected {
            do {
                try Task.checkCancellation()
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
                let destination = try trashOperation(item.url)
                results.append(ApplicationRemovalResult(originalURL: item.url, trashURL: destination,
                                                         bytes: current.bytes, error: nil))
            } catch { results.append(failed(item.url, error.localizedDescription)) }
        }
        return ApplicationRemovalReport(results: results)
    }

    private func failed(_ url: URL, _ message: String) -> ApplicationRemovalResult {
        ApplicationRemovalResult(originalURL: url, trashURL: nil, bytes: 0, error: message)
    }
}
