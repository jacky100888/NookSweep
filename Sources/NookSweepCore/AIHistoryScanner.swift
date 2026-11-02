import Foundation

extension CleanupEngine {
    func aiHistoryCandidates(warnings: inout [String]) throws -> [URL] {
        let manager = FileManager.default
        var candidates: [URL] = []
        for layout in [AIHistoryLayout.claude, .codex, .codexArchived, .gemini] {
            let root = home.appendingPathComponent(layout.path).standardizedFileURL
            guard manager.fileExists(atPath: root.path) else { continue }
            guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
                warnings.append("\(root.path)：對話根目錄包含符號連結，已略過")
                continue
            }
            var pending: [(URL, [String])] = [(root, [])]
            while let (directory, parts) = pending.popLast() {
                try Task.checkCancellation()
                do {
                    let children = try manager.contentsOfDirectory(at: directory,
                        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                    for var child in children {
                        try Task.checkCancellation()
                        child.removeAllCachedResourceValues()
                        let childParts = parts + [child.lastPathComponent]
                        let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                        if values.isSymbolicLink == true {
                            if layout.acceptsFile(childParts) || layout.acceptsDirectory(childParts) {
                                warnings.append("\(child.path)：對話路徑包含符號連結，已略過")
                            }
                        } else if values.isDirectory == true, layout.acceptsDirectory(childParts) {
                            guard child.resolvingSymlinksInPath().standardizedFileURL.path == child.standardizedFileURL.path else {
                                warnings.append("\(child.path)：對話路徑已改變，已略過")
                                continue
                            }
                            pending.append((child, childParts))
                        } else if values.isRegularFile == true, layout.acceptsFile(childParts) {
                            candidates.append(child)
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { warnings.append("\(directory.path)：\(error.localizedDescription)") }
            }
        }
        return candidates.sorted { $0.path < $1.path }
    }
}
