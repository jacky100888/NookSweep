import CryptoKit
import Foundation

struct GroupMeasurement {
    let total: Measurement
    let paths: [(url: URL, bytes: Int64)]
}

func measureGroup(_ url: URL, relatedURLs: [URL], progress: (Int) -> Void = { _ in }) throws -> GroupMeasurement {
    let urls = [url] + relatedURLs.sorted { $0.path < $1.path }
    var digest = SHA256()
    var bytes: Int64 = 0
    var count = 0
    var modified = Date.distantPast
    var paths: [(url: URL, bytes: Int64)] = []
    var primaryFingerprint = ""
    for target in urls {
        let base = count
        let result = try measure(target) { progress(base + $0) }
        if paths.isEmpty { primaryFingerprint = result.fingerprint }
        digest.update(data: Data("\(target.standardizedFileURL.path)\u{0}\(result.fingerprint)".utf8))
        bytes += result.bytes
        count += result.fileCount
        modified = max(modified, result.modified)
        paths.append((target, result.bytes))
    }
    let fingerprint = relatedURLs.isEmpty ? primaryFingerprint :
        digest.finalize().map { String(format: "%02x", $0) }.joined()
    return GroupMeasurement(total: Measurement(bytes: bytes, fileCount: count, modified: modified,
                                               fingerprint: fingerprint), paths: paths)
}

struct GroupTrashFailure: LocalizedError {
    let cause: String
    let remaining: [CleanupMovedPath]
    var errorDescription: String? {
        let recovery = remaining.map { "\($0.trashURL.path) → \($0.originalURL.path)" }.joined(separator: "；")
        return remaining.isEmpty ? "\(cause)；已回復先前移動的關聯項目" :
            "\(cause)；部分項目仍在垃圾桶，請回復：\(recovery)"
    }
}

func systemTrash(_ url: URL) throws -> URL {
    var destination: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
    guard let destination else { throw CleanupError.refused("系統未回傳垃圾桶位置，請到 Finder 確認") }
    return destination as URL
}

func trashGroup(_ paths: [(url: URL, bytes: Int64)],
                move: (URL) throws -> URL = systemTrash) throws -> [CleanupMovedPath] {
    let components = paths.map { $0.url.standardizedFileURL.pathComponents }
        .sorted { $0.lexicographicallyPrecedes($1) }
    for pair in zip(components, components.dropFirst()) {
        guard !pair.1.starts(with: pair.0) else { throw CleanupError.refused("關聯路徑重疊，請重新掃描") }
    }
    var moved: [CleanupMovedPath] = []
    do {
        for path in paths {
            try Task.checkCancellation()
            let physical = path.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard physical == path.url.standardizedFileURL.path else {
                throw CleanupError.refused("關聯路徑已改變，已停止移動")
            }
            moved.append(CleanupMovedPath(originalURL: path.url, trashURL: try move(path.url), bytes: path.bytes))
        }
        return moved
    } catch {
        var remaining: [CleanupMovedPath] = []
        for path in moved.reversed() {
            do { try FileManager.default.moveItem(at: path.trashURL, to: path.originalURL) }
            catch { remaining.append(path) }
        }
        throw GroupTrashFailure(cause: error.localizedDescription, remaining: remaining)
    }
}
