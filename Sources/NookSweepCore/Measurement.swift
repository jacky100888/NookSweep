import CryptoKit
import Foundation

struct Measurement: Equatable {
    let bytes: Int64
    let fileCount: Int
    let modified: Date
    let fingerprint: String
}

func measure(_ url: URL, progress: (Int) -> Void = { _ in }) throws -> Measurement {
    let manager = FileManager.default
    var pending = [url]
    var bytes: Int64 = 0
    var fileCount = 0
    var inspected = 0
    var modified = Date.distantPast
    var digest = SHA256()
    let keys: Set<URLResourceKey> = [
        .isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey,
        .fileSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey, .isAliasFileKey
    ]
    while var current = pending.popLast() {
        try Task.checkCancellation()
        // URL 可能保留上次掃描的中繼資料，重新驗證前必須清除快取。
        current.removeAllCachedResourceValues()
        let values = try current.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true, values.isAliasFile != true,
              values.isUbiquitousItem != true else {
            throw CleanupError.refused("包含連結或雲端項目，已略過")
        }
        guard let date = values.contentModificationDate else {
            throw CleanupError.refused("無法確認修改時間，已略過")
        }
        modified = max(modified, date)
        let attributes = try manager.attributesOfItem(atPath: current.path)
        let identity = "\(attributes[.systemNumber] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
        let record = "\(current.path)\u{0}\(identity)\u{0}\(values.fileSize ?? 0)\u{0}\(date.timeIntervalSince1970)\n"
        digest.update(data: Data(record.utf8))
        if values.isDirectory == true {
            let children = try manager.contentsOfDirectory(at: current,
                includingPropertiesForKeys: Array(keys)).sorted { $0.path < $1.path }
            pending.append(contentsOf: children.reversed())
        } else if values.isRegularFile == true {
            bytes += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
            fileCount += 1
        } else {
            throw CleanupError.refused("包含非一般檔案，已略過")
        }
        inspected += 1
        if inspected.isMultiple(of: 128) { progress(fileCount) }
    }
    return Measurement(bytes: bytes, fileCount: fileCount, modified: modified,
                       fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined())
}
