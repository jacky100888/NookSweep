import Foundation

enum AILegacyHistoryCatalog {
    private static let cursorPath = "Library/Application Support/Cursor/User/History"
    private static let opencodePath = ".local/share/opencode"

    static func candidates(home: URL) throws -> [AICatalogEntry] {
        var result: [AICatalogEntry] = []
        let cursor = home.appendingPathComponent(cursorPath)
        for record in try AICatalogFiles.children(cursor) where isCursorRecord(record.lastPathComponent) {
            if let entry = try cursorEntry(record, home: home) { result.append(entry) }
        }
        let root = home.appendingPathComponent(opencodePath)
        let storage = root.appendingPathComponent("storage")
        for location in [root, storage] {
            for file in try AICatalogFiles.children(location) where isDatabase(file.lastPathComponent) {
                result.append(databaseEntry(file))
            }
        }
        for session in try sessions(storage) {
            if let entry = try opencodeEntry(session, home: home) { result.append(entry) }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    static func entry(for url: URL, home: URL) throws -> AICatalogEntry? {
        let url = url.standardizedFileURL
        let root = home.appendingPathComponent(opencodePath).standardizedFileURL
        if [root.path, root.appendingPathComponent("storage").path].contains(url.deletingLastPathComponent().path),
           isDatabase(url.lastPathComponent), FileManager.default.fileExists(atPath: url.path) {
            return databaseEntry(url)
        }
        if let cursor = try cursorEntry(url, home: home) { return cursor }
        return try opencodeEntry(url, home: home)
    }

    private static func cursorEntry(_ url: URL, home: URL) throws -> AICatalogEntry? {
        let root = home.appendingPathComponent(cursorPath).standardizedFileURL
        guard url.deletingLastPathComponent().path == root.path,
              isCursorRecord(url.lastPathComponent), AICatalogFiles.exists(url) else { return nil }
        var title = "Cursor 本機歷史：\(url.lastPathComponent)"
        var reason = try AICatalogFiles.blockReason(url)
        if reason == nil && !AICatalogFiles.isDirectory(url) { reason = "歷史存檔不是目錄，保留原狀" }
        if reason == nil {
            let children = try AICatalogFiles.children(url)
            if children.contains(where: { !AICatalogFiles.isRegular($0) }) {
                reason = "本機歷史包含未知目錄或檔案類型，保留原狀"
            } else {
                let metadata = url.appendingPathComponent("entries.json")
                if let data = try? AICatalogFiles.smallFile(metadata, limit: 1_048_576),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resource = object["resource"] as? String,
                   let name = URL(string: resource)?.lastPathComponent,
                   !name.isEmpty, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                    title = "Cursor 本機歷史：\(name)"
                }
            }
        }
        return AICatalogEntry(url: url, category: .aiHistory,
            metadata: AIItemMetadata(toolID: "cursor", kind: .localHistory, title: title,
                note: "單一檔案的本機快照；不含工作區原始檔與聊天紀錄"), preservationReason: reason)
    }

    private static func opencodeEntry(_ url: URL, home: URL) throws -> AICatalogEntry? {
        let root = home.appendingPathComponent(opencodePath).standardizedFileURL
        let storage = root.appendingPathComponent("storage")
        let sessionRoot = storage.appendingPathComponent("session")
        guard url.deletingLastPathComponent().deletingLastPathComponent().path == sessionRoot.path,
              isIDFile(url.lastPathComponent, prefix: "ses_"), AICatalogFiles.exists(url) else { return nil }
        var related: [URL] = []
        var reason = try AICatalogFiles.blockReason(url)
        if reason == nil && !AICatalogFiles.isRegular(url) { reason = "非已知的 session JSON 檔案，保留原狀" }
        let id = url.deletingPathExtension().lastPathComponent
        if reason == nil {
            let databasePresent = try [root, storage].contains { location in
                try AICatalogFiles.children(location).contains { isDatabase($0.lastPathComponent) }
            }
            if databasePresent { reason = "opencode 資料庫與舊紀錄並存，無法確認遷移與索引狀態" }
        }
        if reason == nil {
            do {
                try validateSessionNamespace(storage)
                let known = Set(["session", "message", "part", "session_diff", "todo", "project", "tool-output", "migration"])
                if try AICatalogFiles.children(storage).contains(where: { !known.contains($0.lastPathComponent) }) {
                    reason = "opencode 出現未知儲存布局，保留原狀"
                } else if try sessions(storage).filter({
                    $0.lastPathComponent.lowercased() == url.lastPathComponent.lowercased()
                }).count != 1 {
                    reason = "session 識別碼重複，無法安全配對訊息"
                }
            } catch is CancellationError { throw CancellationError() }
            catch { reason = error.localizedDescription }
        }
        if reason == nil {
            do { related = try associatedURLs(id: id, storage: storage) }
            catch is CancellationError { throw CancellationError() }
            catch { reason = error.localizedDescription }
        }
        return AICatalogEntry(url: url, category: .aiHistory,
            metadata: AIItemMetadata(toolID: "opencode", kind: .conversation, title: "opencode 舊對話：\(id)",
                note: "依 session／message／part 檔名配對，未讀取對話正文"),
            preservationReason: reason, relatedURLs: reason == nil ? related : [])
    }

    private static func associatedURLs(id: String, storage: URL) throws -> [URL] {
        var related: [URL] = []
        for namespace in ["message", "part", "session_diff", "todo"] {
            let base = storage.appendingPathComponent(namespace)
            if let reason = try AICatalogFiles.blockReason(base, allowMissing: true) {
                throw CleanupError.refused(reason)
            }
        }
        let message = storage.appendingPathComponent("message/\(id)")
        if AICatalogFiles.exists(message) {
            try requireSafe(message)
            let messages = try AICatalogFiles.children(message)
            guard AICatalogFiles.isDirectory(message), messages.allSatisfy({
                isIDFile($0.lastPathComponent, prefix: "msg_") && AICatalogFiles.isRegular($0)
            }) else { throw CleanupError.refused("訊息目錄包含未知格式，無法完整配對") }
            let names = Set(messages.map { $0.lastPathComponent.lowercased() })
            for peer in try AICatalogFiles.children(storage.appendingPathComponent("message")) where peer != message {
                try requireSafe(peer)
                guard AICatalogFiles.isDirectory(peer),
                      try !AICatalogFiles.children(peer).contains(where: { names.contains($0.lastPathComponent.lowercased()) }) else {
                    throw CleanupError.refused("訊息識別碼重複或布局未知，無法安全配對片段")
                }
            }
            related.append(message)
            for file in messages {
                let part = storage.appendingPathComponent("part/\(file.deletingPathExtension().lastPathComponent)")
                if AICatalogFiles.exists(part) {
                    try requireSafe(part)
                    guard AICatalogFiles.isDirectory(part), try AICatalogFiles.children(part).allSatisfy({
                        isIDFile($0.lastPathComponent, prefix: "prt_") && AICatalogFiles.isRegular($0)
                    }) else { throw CleanupError.refused("訊息片段包含未知格式，保留原狀") }
                    related.append(part)
                }
            }
        }
        for namespace in ["session_diff", "todo"] {
            let file = storage.appendingPathComponent("\(namespace)/\(id).json")
            if AICatalogFiles.exists(file) {
                try requireSafe(file)
                guard AICatalogFiles.isRegular(file) else { throw CleanupError.refused("關聯資料不是一般 JSON 檔案") }
                related.append(file)
            }
        }
        return related.sorted { $0.path < $1.path }
    }

    private static func requireSafe(_ url: URL) throws {
        if let reason = try AICatalogFiles.blockReason(url) { throw CleanupError.refused(reason) }
    }

    private static func sessions(_ storage: URL) throws -> [URL] {
        var result: [URL] = []
        for project in try AICatalogFiles.children(storage.appendingPathComponent("session")) {
            guard AICatalogFiles.isDirectory(project) else { continue }
            do { result += try AICatalogFiles.children(project).filter { isIDFile($0.lastPathComponent, prefix: "ses_") } }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        return result
    }

    private static func validateSessionNamespace(_ storage: URL) throws {
        let root = storage.appendingPathComponent("session")
        try requireSafe(root)
        guard AICatalogFiles.isDirectory(root) else { throw CleanupError.refused("session 命名空間不是目錄") }
        for project in try AICatalogFiles.children(root) {
            try requireSafe(project)
            guard AICatalogFiles.isDirectory(project) else { throw CleanupError.refused("session 專案布局未知，保留全部舊對話") }
            for session in try AICatalogFiles.children(project) {
                try requireSafe(session)
                guard isIDFile(session.lastPathComponent, prefix: "ses_"), AICatalogFiles.isRegular(session) else {
                    throw CleanupError.refused("session 專案包含未知格式，保留全部舊對話")
                }
            }
        }
    }

    private static func databaseEntry(_ url: URL) -> AICatalogEntry {
        AICatalogEntry(url: url, category: .aiHistory,
            metadata: AIItemMetadata(toolID: "opencode", kind: .conversation,
                title: "opencode 資料庫：\(url.lastPathComponent)", note: "新版對話由資料庫管理"),
            preservationReason: "資料庫不支援逐筆安全清理，請在 opencode 中管理對話")
    }

    private static func isDatabase(_ name: String) -> Bool {
        [".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm", ".sqlite-wal", ".sqlite-shm",
         ".sqlite3-wal", ".sqlite3-shm", ".db-journal", ".sqlite-journal", ".sqlite3-journal"]
            .contains(where: name.lowercased().hasSuffix)
    }

    private static func isCursorRecord(_ name: String) -> Bool {
        let digits = name.hasPrefix("-") ? String(name.dropFirst()) : name
        return !digits.isEmpty && digits.count <= 64 && digits.allSatisfy(\.isHexDigit)
    }

    private static func isIDFile(_ name: String, prefix: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return false }
        let id = name.dropFirst(prefix.count).dropLast(5)
        return !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

// 僅檢查已知路徑的中繼資料，禁止透過符號連結離開清理邊界。
enum AICatalogFiles {
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func isRegular(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }

    static func children(_ url: URL) throws -> [URL] {
        guard exists(url), isDirectory(url),
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else { return [] }
        try Task.checkCancellation()
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    static func blockReason(_ url: URL, allowMissing: Bool = false) throws -> String? {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            return "路徑包含符號連結，保留原狀"
        }
        guard exists(url) else { return allowMissing ? nil : "找不到完整中繼資料，保留原狀" }
        let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        return [.typeRegular, .typeDirectory].contains(type) ? nil : "包含非一般檔案，保留原狀"
    }

    static func smallFile(_ url: URL, limit: Int = 4096) throws -> Data {
        guard try blockReason(url) == nil, isRegular(url),
              let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.intValue <= limit else { throw CleanupError.refused("中繼資料格式不安全，保留原狀") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CleanupError.refused("中繼資料過大，保留原狀") }
        return data
    }
}
