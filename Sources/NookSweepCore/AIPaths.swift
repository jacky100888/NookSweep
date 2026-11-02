import Foundation

func aiToolIdentifier(for url: URL) -> String? {
    let components = url.standardizedFileURL.pathComponents
    for (directory, tool) in [(".claude", "claude"), (".codex", "codex"), (".gemini", "gemini")] {
        if components.contains(directory) { return tool }
    }
    if let index = components.firstIndex(of: "Caches"), index > 0,
       components[index - 1] == "Library", components.count > index + 1 {
        let name = components[index + 1].lowercased()
        for (prefix, tool) in [("com.openai.codex", "codex"), ("com.openai.chat", "chatgpt"),
                               ("com.anthropic.claude", "claude"), ("com.anthropic.claudefordesktop", "claude"),
                               ("com.google.gemini", "gemini"), ("claude", "claude"),
                               ("codex", "codex"), ("chatgpt", "chatgpt"), ("gemini", "gemini"),
                               ("cursor", "cursor"), ("com.todesktop.230313mzl4w4u92", "cursor"),
                               ("opencode", "opencode")] {
            if name == prefix || name.hasPrefix(prefix + ".") { return tool }
        }
    }
    return nil
}

enum AIHistoryLayout: Sendable {
    case claude, codex, codexArchived, gemini

    var path: String {
        switch self {
        case .claude: ".claude/projects"
        case .codex: ".codex/sessions"
        case .codexArchived: ".codex/archived_sessions"
        case .gemini: ".gemini/tmp"
        }
    }

    func acceptsFile(_ parts: [String]) -> Bool {
        guard let name = parts.last else { return false }
        switch self {
        case .claude:
            if parts.count == 2, name.hasSuffix(".jsonl") {
                return UUID(uuidString: String(name.dropLast(6))) != nil
            }
            return parts.count == 4 && UUID(uuidString: parts[1]) != nil &&
                parts[2] == "subagents" && name.hasPrefix("agent-") && name.hasSuffix(".jsonl")
        case .codex:
            return parts.count == 4 && parts.prefix(3).allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) } &&
                name.hasPrefix("rollout-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zst"))
        case .codexArchived:
            return parts.count == 1 && name.hasPrefix("rollout-") &&
                (name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zst"))
        case .gemini:
            return parts.count == 3 && parts[1] == "chats" &&
                name.hasPrefix("session-") && name.hasSuffix(".json")
        }
    }

    func acceptsDirectory(_ parts: [String]) -> Bool {
        switch self {
        case .claude:
            return parts.count == 1 ||
                (parts.count == 2 && UUID(uuidString: parts[1]) != nil) ||
                (parts.count == 3 && UUID(uuidString: parts[1]) != nil && parts[2] == "subagents")
        case .codex:
            return parts.count <= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        case .codexArchived: return false
        case .gemini: return parts.count == 1 || (parts.count == 2 && parts[1] == "chats")
        }
    }
}

extension CleanupEngine {
    var aiCacheRoots: [ScanRoot] {
        [".claude/debug", ".claude/paste-cache", ".claude/shell-snapshots",
         ".codex/log", ".codex/shell_snapshots", ".gemini/logs"]
            .map { ScanRoot(url: home.appendingPathComponent($0), category: .aiCaches) }
    }

    func aiHistoryRoot(for url: URL) -> ScanRoot? {
        let path = url.standardizedFileURL
        for layout in [AIHistoryLayout.claude, .codex, .codexArchived, .gemini] {
            let base = home.appendingPathComponent(layout.path).standardizedFileURL
            let prefix = base.pathComponents
            let components = path.pathComponents
            guard components.starts(with: prefix) else { continue }
            if layout.acceptsFile(Array(components.dropFirst(prefix.count))) {
                return ScanRoot(url: path.deletingLastPathComponent(), category: .aiHistory)
            }
        }
        return nil
    }

    func acceptsAICacheFile(_ url: URL, root: URL) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        if root.lastPathComponent == "shell-snapshots" || root.lastPathComponent == "shell_snapshots" {
            return url.pathExtension.lowercased() == "sh"
        }
        if root.lastPathComponent == "debug" || root.lastPathComponent == "paste-cache" {
            return ["txt", "log"].contains(url.pathExtension.lowercased())
        }
        return url.pathExtension.lowercased() == "log"
    }

    func aiContentBlockReason(_ url: URL) throws -> String? {
        var pending = [url]
        let reserved = Set(["auth.json", "config.toml", "settings.json", "settings.local.json",
                            "credentials.json", "oauth_creds.json", "credentials", "cookies",
                            "local storage", "session storage", "indexeddb", "memory", "memories",
                            "skills", "rules", "projects", "sessions"])
        while var current = pending.popLast() {
            try Task.checkCancellation()
            current.removeAllCachedResourceValues()
            let name = current.lastPathComponent.lowercased()
            if reserved.contains(name) || [".sqlite", ".sqlite3", ".db", "-wal", "-shm", "-journal"].contains(where: name.hasSuffix) {
                return "包含設定、記憶、憑證或資料庫，保留原狀"
            }
            let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { return "包含符號連結，保留原狀" }
            if values.isDirectory == true {
                pending.append(contentsOf: try FileManager.default.contentsOfDirectory(at: current,
                    includingPropertiesForKeys: nil))
            }
        }
        return nil
    }
}
