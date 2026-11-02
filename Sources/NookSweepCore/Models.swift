import Foundation

public enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case caches = "應用程式快取"
    case logs = "舊記錄檔"
    case developer = "開發工具快取"
    case aiCaches = "AI 工具快取"
    case aiHistory = "AI 舊對話"
    case aiVersions = "AI 工具版本"
    case aiWorktrees = "AI 工作副本"

    public var id: String { rawValue }
    public var minimumDays: Int { self == .logs || self == .aiHistory ? 30 : 7 }
    public var isAI: Bool { [.aiCaches, .aiHistory, .aiVersions, .aiWorktrees].contains(self) }
    public var symbol: String {
        switch self {
        case .caches: "square.stack.3d.up"
        case .logs: "doc.text"
        case .developer: "hammer"
        case .aiCaches: "sparkles"
        case .aiHistory: "bubble.left.and.bubble.right"
        case .aiVersions: "shippingbox"
        case .aiWorktrees: "arrow.triangle.branch"
        }
    }
}

public enum ItemState: Equatable, Sendable {
    case eligible
    case recent
    case running
    case blocked(String)

    public var reason: String? {
        switch self {
        case .eligible: nil
        case .recent: "最近仍有使用，暫不清理"
        case .running: "應用程式執行中，請結束後重新掃描"
        case .blocked(let reason): reason
        }
    }
}

public struct CleanupItem: Identifiable, Sendable {
    public var id: String { url.path }
    public var name: String { aiMetadata?.title ?? url.lastPathComponent }
    public let url: URL
    public let category: CleanupCategory
    public let bytes: Int64
    public let fileCount: Int
    public let modified: Date
    public let state: ItemState
    let fingerprint: String
    public let aiMetadata: AIItemMetadata?
    let relatedURLs: [URL]
    public var relatedItemCount: Int { relatedURLs.count }
    public var measurementAvailable: Bool { !fingerprint.isEmpty }
    public var isEligible: Bool { state == .eligible }
    public var aiToolID: String? { aiMetadata?.toolID ?? aiToolIdentifier(for: url) }
    public var aiToolName: String? {
        switch aiToolID {
        case "codex": "Codex"
        case "claude": "Claude"
        case "gemini": "Gemini"
        case "chatgpt": "ChatGPT"
        case "cursor": "Cursor"
        case "opencode": "opencode"
        default: nil
        }
    }
    public var isAIHistory: Bool { category == .aiHistory }

    init(url: URL, category: CleanupCategory, bytes: Int64, fileCount: Int, modified: Date,
         state: ItemState, fingerprint: String, aiMetadata: AIItemMetadata? = nil,
         relatedURLs: [URL] = []) {
        self.url = url
        self.category = category
        self.bytes = bytes
        self.fileCount = fileCount
        self.modified = modified
        self.state = state
        self.fingerprint = fingerprint
        self.aiMetadata = aiMetadata
        self.relatedURLs = relatedURLs
    }
}

public struct ScanProgress: Sendable {
    public let path: String
    public let fileCount: Int
}

public struct ScanResult: Sendable {
    public let items: [CleanupItem]
    public let warnings: [String]
    public let inspectedCount: Int

    public init(items: [CleanupItem], warnings: [String], inspectedCount: Int) {
        self.items = items
        self.warnings = warnings
        self.inspectedCount = inspectedCount
    }
}

public struct CleanupMovedPath: Sendable {
    public let originalURL: URL
    public let trashURL: URL
    public let bytes: Int64
}

public struct TrashedItem: Sendable {
    public let originalURL: URL
    public let trashURL: URL
    public let bytes: Int64
    public let relatedMoves: [CleanupMovedPath]

    init(originalURL: URL, trashURL: URL, bytes: Int64, relatedMoves: [CleanupMovedPath] = []) {
        self.originalURL = originalURL
        self.trashURL = trashURL
        self.bytes = bytes
        self.relatedMoves = relatedMoves
    }
}

public struct CleanupReport: Sendable {
    public let moved: [TrashedItem]
    public let failures: [String]
    public let recoveryReferences: [WorktreeRecoveryReference]
    public var bytes: Int64 { moved.reduce(0) { $0 + $1.bytes } }

    init(moved: [TrashedItem], failures: [String], recoveryReferences: [WorktreeRecoveryReference] = []) {
        self.moved = moved
        self.failures = failures
        self.recoveryReferences = recoveryReferences
    }
}

public enum CleanupError: LocalizedError {
    case refused(String)

    public var errorDescription: String? {
        switch self { case .refused(let message): message }
    }
}

public actor CleanupEngine {
    let home: URL
    let activity: @Sendable () -> Set<String>
    let trashOperation: @Sendable (URL) throws -> URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                activity: @escaping @Sendable () -> Set<String> = { AIProcessActivity.runningToolIDs() },
                trashOperation: (@Sendable (URL) throws -> URL)? = nil) {
        self.home = home.standardizedFileURL
        self.activity = activity
        self.trashOperation = trashOperation ?? { try systemTrash($0) }
    }

}
