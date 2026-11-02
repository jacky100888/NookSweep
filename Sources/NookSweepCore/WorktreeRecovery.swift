import Foundation

extension GitInspection {
    func createRecoveryReference(expectedHead: String, refName: String = "refs/nooksweep/recovery/" + UUID().uuidString.lowercased())
        throws -> WorktreeRecoveryReference {
        guard refName.hasPrefix("refs/nooksweep/recovery/"),
              UUID(uuidString: String(refName.dropFirst("refs/nooksweep/recovery/".count))) != nil,
              try currentHeadOID() == expectedHead else {
            throw CleanupError.refused("復原參照或 HEAD 已改變，未移動工作副本")
        }
        let storage = try run(["config", "--get", "extensions.refStorage"])
        guard storage.status == 1 || (storage.status == 0 &&
            String(decoding: storage.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "files") else {
            throw CleanupError.refused("不支援此 Git 參照儲存格式，未移動工作副本")
        }
        for relative in ["refs", "refs/nooksweep", "refs/nooksweep/recovery"] {
            let directory = commonDirectory.appendingPathComponent(relative)
            if let reason = try AICatalogFiles.blockReason(directory, allowMissing: true) {
                throw CleanupError.refused(reason)
            }
            if AICatalogFiles.exists(directory), !AICatalogFiles.isDirectory(directory) {
                throw CleanupError.refused("復原參照的上層不是一般目錄，未移動工作副本")
            }
        }
        let leaf = commonDirectory.appendingPathComponent(refName)
        if let reason = try AICatalogFiles.blockReason(leaf, allowMissing: true) {
            throw CleanupError.refused(reason)
        }
        guard !AICatalogFiles.exists(leaf) else {
            throw CleanupError.refused("復原參照路徑已存在，禁止覆寫")
        }
        // 空的 old-value 配合 no-deref，只允許建立全新參照，禁止覆寫現有或符號參照。
        let result = try run(["-c", "core.logAllRefUpdates=false", "update-ref", "--no-deref",
                              refName, expectedHead, ""], checkCancellationAfterExit: false)
        guard result.status == 0 else { throw CleanupError.refused("無法建立 Git 復原參照，未移動工作副本") }
        // 寫入成功後先交回參照；呼叫端記錄結果後才能再次檢查取消。
        return WorktreeRecoveryReference(worktreeURL: repository, commonGitDirectory: commonDirectory,
                                         refName: refName, headOID: expectedHead)
    }
}
