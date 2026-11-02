import Foundation

struct GitInspection {
    let repository: URL
    let commonDirectory: URL
    let administrationDirectory: URL
    private var filterOverrides: [String] = []

    init(repository: URL) throws {
        self.repository = repository.standardizedFileURL
        let marker = repository.appendingPathComponent(".git")
        guard AICatalogFiles.isRegular(marker) else {
            throw CleanupError.refused("主儲存庫或缺少 linked worktree 中繼資料，保留原狀")
        }
        let pointer = try Self.text(marker)
        guard pointer.hasPrefix("gitdir: ") else { throw CleanupError.refused("無法辨識 Git 中繼資料") }
        administrationDirectory = Self.path(String(pointer.dropFirst(8)), relativeTo: repository)
        let common = administrationDirectory.appendingPathComponent("commondir")
        commonDirectory = Self.path(try Self.text(common), relativeTo: administrationDirectory)
        let expected = commonDirectory.appendingPathComponent("worktrees")
            .appendingPathComponent(administrationDirectory.lastPathComponent).standardizedFileURL
        guard administrationDirectory.path == expected.path,
              AICatalogFiles.isDirectory(commonDirectory), AICatalogFiles.isDirectory(administrationDirectory),
              try AICatalogFiles.blockReason(commonDirectory) == nil,
              try AICatalogFiles.blockReason(administrationDirectory) == nil,
              Self.path(try Self.text(administrationDirectory.appendingPathComponent("gitdir")),
                        relativeTo: administrationDirectory).path == marker.standardizedFileURL.path else {
            throw CleanupError.refused("Git 管理目錄與工作副本的對應不完整，保留原狀")
        }
        try verifyAdministration()
        let filters = try run(["config", "--includes", "--null", "--name-only", "--get-regexp",
                               "^filter\\..*\\.(clean|smudge|process|required)$"])
        guard [0, 1].contains(filters.status), let filterNames = String(data: filters.data, encoding: .utf8) else {
            throw CleanupError.refused("無法停用 Git filter，保留原狀")
        }
        for name in filterNames.components(separatedBy: "\0") where !name.isEmpty {
            guard !name.contains("="), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw CleanupError.refused("Git filter 名稱格式不明，保留原狀")
            }
            filterOverrides += ["-c", name + "=" + (name.hasSuffix(".required") ? "false" : "")]
        }
        guard Self.path(try output(["rev-parse", "--absolute-git-dir"]).trimmingCharacters(in: .newlines),
                        relativeTo: repository).path == administrationDirectory.path,
              Self.path(try output(["rev-parse", "--git-common-dir"]).trimmingCharacters(in: .newlines),
                        relativeTo: repository).path == commonDirectory.path else {
            throw CleanupError.refused("Git 回報的管理目錄不一致，保留原狀")
        }
        let topLevel = Self.path(try output(["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .newlines),
                                 relativeTo: repository).resolvingSymlinksInPath().standardizedFileURL
        guard topLevel.path == repository.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw CleanupError.refused("Git 工作目錄被設定導向其他位置，無法確認本工作副本是否乾淨")
        }
    }

    func review() throws -> AIWorktreeReview {
        let initialHead = try currentHeadOID()
        let records = try output(["worktree", "list", "--porcelain", "-z"])
            .components(separatedBy: "\0\0").filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "\0").filter { !$0.isEmpty } }
        guard let primary = records.first,
              let primaryPath = primary.first?.stripPrefix("worktree "),
              !primary.contains("bare"), Self.path(primaryPath, relativeTo: repository).path != repository.path else {
            throw CleanupError.refused("主工作副本或無法確認主儲存庫，保留原狀")
        }
        let matching = records.filter {
            guard let path = $0.first?.stripPrefix("worktree ") else { return false }
            return Self.path(path, relativeTo: repository).path == repository.path
        }
        let primaryURL = URL(fileURLWithPath: primaryPath).standardizedFileURL
        guard matching.count == 1, let record = matching.first,
              AICatalogFiles.isDirectory(primaryURL),
              try AICatalogFiles.blockReason(primaryURL) == nil else {
            throw CleanupError.refused("無法證實工作副本仍已註冊，保留原狀")
        }
        if record.contains(where: { $0 == "locked" || $0.hasPrefix("locked ") || $0.hasPrefix("prunable") }) {
            throw CleanupError.refused("Git 工作副本已鎖定或註冊失效，保留原狀")
        }
        let flags = try output(["ls-files", "-v", "-z"]).components(separatedBy: "\0")
        if flags.contains(where: { $0.first == "S" || $0.first?.isLowercase == true }) {
            throw CleanupError.refused("含略過檢查或 sparse checkout 的索引項目，無法證實檔案乾淨")
        }
        if try output(["ls-files", "--stage", "-z"]).components(separatedBy: "\0")
            .contains(where: { $0.hasPrefix("160000 ") }) {
            throw CleanupError.refused("含 submodule，無法確認子儲存庫資料可還原")
        }
        if AICatalogFiles.exists(commonDirectory.appendingPathComponent("info/grafts")) {
            throw CleanupError.refused("Git 歷史有 graft 覆寫，無法確認原始合併狀態")
        }
        guard try output(["ls-files", "--unmerged", "-z"]).isEmpty else {
            throw CleanupError.refused("Git 索引仍有未解決衝突，保留原狀")
        }
        let state = try run(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching",
                             "--ignore-submodules=none"])
        guard state.status == 0 else { throw CleanupError.refused("無法確認工作副本狀態，保留原狀") }
        var counts = [0, 0, 0]
        let statusRecords = state.data.split(separator: 0)
        var index = 0
        while index < statusRecords.count {
            let code = Array(statusRecords[index].prefix(2))
            index += 1
            if code == [63, 63] { counts[1] += 1 }
            else if code == [33, 33] { counts[2] += 1 }
            else {
                counts[0] += 1
                if code.contains(82) || code.contains(67) { index += 1 }
            }
        }
        var main: String?
        for branch in ["main", "master"] {
            if try run(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"]).status == 0 {
                main = branch
                break
            }
        }
        guard let main else { throw CleanupError.refused("找不到主儲存庫的 main／master，保留原狀") }
        let merged = try run(["merge-base", "--is-ancestor", "HEAD", "refs/heads/\(main)"])
        guard [0, 1].contains(merged.status),
              let ahead = Int(try output(["rev-list", "--count", "refs/heads/\(main)..HEAD"])
                .trimmingCharacters(in: .newlines)), ahead >= 0,
              (merged.status == 0) == (ahead == 0), try currentHeadOID() == initialHead else {
            throw CleanupError.refused("無法確認 HEAD 與合併狀態一致，請重新掃描")
        }
        return AIWorktreeReview(headOID: initialHead, commonGitDirectory: commonDirectory,
            trackedChanges: counts[0], untrackedItems: counts[1], ignoredItems: counts[2],
            unmergedCommitCount: ahead, comparisonBranch: main)
    }

    func currentHeadOID() throws -> String {
        let head = try output(["rev-parse", "--verify", "HEAD^{commit}"]).trimmingCharacters(in: .newlines)
        guard [40, 64].contains(head.count), head.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw CleanupError.refused("HEAD 不是可確認的提交，保留原狀")
        }
        return head
    }

    private func verifyAdministration() throws {
        var pending = [administrationDirectory]
        while let current = pending.popLast() {
            try Task.checkCancellation()
            if let reason = try AICatalogFiles.blockReason(current) { throw CleanupError.refused(reason) }
            if current.lastPathComponent == "locked" || current.lastPathComponent.hasSuffix(".lock") {
                throw CleanupError.refused("Git 管理目錄包含鎖定狀態，保留原狀")
            }
            if ["rebase-merge", "rebase-apply", "sequencer", "MERGE_HEAD", "CHERRY_PICK_HEAD",
                "REVERT_HEAD", "BISECT_LOG", "BISECT_START"].contains(current.lastPathComponent) {
                throw CleanupError.refused("Git 操作尚未完成，保留原狀")
            }
            if AICatalogFiles.isDirectory(current) { pending += try AICatalogFiles.children(current) }
        }
    }

    private func output(_ arguments: [String]) throws -> String {
        let result = try run(arguments)
        guard result.status == 0, let text = String(data: result.data, encoding: .utf8) else {
            throw CleanupError.refused("Git 唯讀檢查失敗，保留原狀")
        }
        return text
    }

    func run(_ arguments: [String], checkCancellationAfterExit: Bool = true) throws -> (status: Int32, data: Data) {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
                             "-c", "submodule.recurse=false"] + filterOverrides + ["-C", repository.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // 清除呼叫端的 Git 路徑覆寫，避免檢查到另一個儲存庫。
        for key in environment.keys where key.hasPrefix("GIT_") { environment.removeValue(forKey: key) }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        environment["GIT_NO_REPLACE_OBJECTS"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // 先持續排空唯一的 pipe，避免大量未追蹤檔名塞滿 pipe 而互相等待。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if checkCancellationAfterExit { try Task.checkCancellation() }
        return (process.terminationStatus, data)
    }

    private static func text(_ url: URL) throws -> String {
        let data = try AICatalogFiles.smallFile(url)
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw CleanupError.refused("Git 中繼資料不是可辨識的路徑")
        }
        let value = text.trimmingCharacters(in: .newlines)
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else {
            throw CleanupError.refused("Git 中繼資料路徑不完整")
        }
        return value
    }

    private static func path(_ text: String, relativeTo base: URL) -> URL {
        text.hasPrefix("/") ? URL(fileURLWithPath: text).standardizedFileURL :
            base.appendingPathComponent(text).standardizedFileURL
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
