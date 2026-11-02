import Foundation

public enum AIDataKind: String, CaseIterable, Sendable {
    case cache = "快取與暫存"
    case conversation = "對話紀錄"
    case localHistory = "本機歷史存檔"
    case oldVersion = "工具版本"
    case worktree = "工作副本"
}

public struct AIItemMetadata: Equatable, Sendable {
    public let toolID: String
    public let kind: AIDataKind
    public let title: String
    public let note: String?

    public init(toolID: String, kind: AIDataKind, title: String, note: String? = nil) {
        self.toolID = toolID
        self.kind = kind
        self.title = title
        self.note = note
    }
}

struct AICatalogEntry: Sendable {
    let url: URL
    let category: CleanupCategory
    let metadata: AIItemMetadata
    let preservationReason: String?
    let relatedURLs: [URL]

    init(url: URL, category: CleanupCategory, metadata: AIItemMetadata,
         preservationReason: String? = nil, relatedURLs: [URL] = []) {
        self.url = url
        self.category = category
        self.metadata = metadata
        self.preservationReason = preservationReason
        self.relatedURLs = relatedURLs
    }
}
