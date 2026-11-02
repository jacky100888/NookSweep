import CryptoKit
import Darwin
import Foundation

struct ApplicationMeasurement {
    let bytes: Int64
    let fileCount: Int
    let fingerprint: String
}

func applicationStat(_ url: URL) throws -> stat {
    var information = stat()
    guard lstat(url.path, &information) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                      userInfo: [NSFilePathErrorKey: url.path])
    }
    return information
}

func applicationFileType(_ information: stat) -> mode_t { information.st_mode & S_IFMT }

func applicationValidateAncestors(_ url: URL) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    for component in url.standardizedFileURL.pathComponents.dropFirst() {
        current.appendPathComponent(component)
        let type = applicationFileType(try applicationStat(current))
        if type == S_IFLNK {
            // Foundation 會把 /private/var 正規化成 /var；只接受 macOS 固定的系統別名。
            let aliases = ["/var": "private/var", "/tmp": "private/tmp", "/etc": "private/etc"]
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: current.path)
            guard current.path != url.path, aliases[current.path] == target else {
                throw CleanupError.refused("路徑含符號連結，已保留")
            }
            continue
        }
        if current.path != url.standardizedFileURL.path, type != S_IFDIR {
            throw CleanupError.refused("上層路徑不是資料夾，已保留")
        }
    }
}

func applicationMeasure(_ root: URL) throws -> ApplicationMeasurement {
    try applicationValidateAncestors(root)
    var pending = [root]
    var bytes: Int64 = 0
    var count = 0
    var digest = SHA256()
    while let current = pending.popLast() {
        try Task.checkCancellation()
        let information = try applicationStat(current)
        let type = applicationFileType(information)
        let relative = String(current.path.dropFirst(root.path.count))
        var record = "\(relative)\u{0}\(information.st_dev):\(information.st_ino):\(information.st_mode)"
        record += ":\(information.st_size):\(information.st_mtimespec.tv_sec):\(information.st_mtimespec.tv_nsec)"
        record += ":\(information.st_ctimespec.tv_sec):\(information.st_ctimespec.tv_nsec)"
        switch type {
        case S_IFDIR:
            let children = try FileManager.default.contentsOfDirectory(at: current,
                includingPropertiesForKeys: nil).map(\.standardizedFileURL).sorted { $0.path < $1.path }
            pending.append(contentsOf: children.reversed())
        case S_IFREG:
            bytes += Int64(information.st_blocks) * 512
            count += 1
        case S_IFLNK:
            // 只記錄連結本身；App 的 Frameworks 常用連結，外部目標不得追蹤。
            record += "\u{0}" + (try FileManager.default.destinationOfSymbolicLink(atPath: current.path))
            bytes += Int64(information.st_blocks) * 512
            count += 1
        default:
            throw CleanupError.refused("包含非一般檔案，已保留")
        }
        digest.update(data: Data((record + "\n").utf8))
    }
    return ApplicationMeasurement(bytes: bytes, fileCount: count,
        fingerprint: digest.finalize().map { String(format: "%02x", $0) }.joined())
}
