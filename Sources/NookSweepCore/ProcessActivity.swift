import Darwin
import Foundation

public enum AIProcessActivity {
    public static func toolID(processName: String, executablePath: String) -> String? {
        let name = processName.lowercased()
        let components = executablePath.lowercased().split(separator: "/")
        if name == "codex" || name.hasPrefix("codex-") || name.hasPrefix("codexcli") ||
            components.contains("codex.app") || components.contains("codex-cli") { return "codex" }
        if name == "claude" || components.contains("claude.app") { return "claude" }
        if name == "gemini" || components.contains("gemini-cli") { return "gemini" }
        if name == "chatgpt" || components.contains("chatgpt.app") { return "chatgpt" }
        return nil
    }

    public static func runningToolIDs(bundleIdentifiers: Set<String> = []) -> Set<String> {
        var tools = Set<String>()
        for identifier in bundleIdentifiers {
            let lower = identifier.lowercased()
            if lower.hasPrefix("com.anthropic.claude") { tools.insert("claude") }
            if lower.contains("openai") && lower.contains("codex") { tools.insert("codex") }
            if lower == "com.openai.chat" { tools.insert("chatgpt") }
        }
        let capacity = max(0, Int(proc_listallpids(nil, 0))) + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return tools }
        for pid in pids.prefix(min(Int(count), capacity)) where pid > 0 {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard nameLength > 0 || pathLength > 0 else { continue }
            let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let path = String(decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if let tool = toolID(processName: name, executablePath: path) { tools.insert(tool) }
        }
        return tools
    }
}
