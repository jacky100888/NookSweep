import AppKit
import Foundation

public struct ApplicationActivity: Sendable {
    public let bundleIDs: Set<String>
    public let applicationPaths: Set<String>

    public init(bundleIDs: Set<String> = [], applicationPaths: Set<String> = []) {
        self.bundleIDs = bundleIDs
        self.applicationPaths = applicationPaths
    }

    public static func current() async -> ApplicationActivity {
        await MainActor.run {
            let applications = NSWorkspace.shared.runningApplications
            return ApplicationActivity(bundleIDs: Set(applications.compactMap(\.bundleIdentifier)),
                applicationPaths: Set(applications.compactMap { $0.bundleURL?.standardizedFileURL.path }))
        }
    }
}

public struct ApplicationRecord: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public let bytes: Int64
    public let fileCount: Int
    public let blockedReason: String?
    public var isRemovable: Bool { blockedReason == nil }
    let fingerprint: String
}

public struct ApplicationRelatedItem: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let category: String
    public let bytes: Int64
    public let blockedReason: String?
    public var isSelectable: Bool { blockedReason == nil }
    let fingerprint: String
    let matchedByName: Bool
}

public struct ApplicationScanResult: Sendable {
    public let applications: [ApplicationRecord]
    public let warnings: [String]
}

public struct ApplicationRemovalResult: Identifiable, Sendable {
    public var id: String { originalURL.path }
    public let originalURL: URL
    public let trashURL: URL?
    public let bytes: Int64
    public let error: String?
    public var succeeded: Bool { trashURL != nil && error == nil }
}

public struct ApplicationRemovalReport: Sendable {
    public let results: [ApplicationRemovalResult]
    public var movedCount: Int { results.filter(\.succeeded).count }
    public var movedBytes: Int64 { results.filter(\.succeeded).reduce(0) { $0 + $1.bytes } }
}

struct ApplicationMetadata {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var names: Set<String> { [name, url.deletingPathExtension().lastPathComponent] }
}

public actor ApplicationsEngine {
    let applicationRoots: [URL]
    let home: URL
    let ownBundleID: String?
    let ownApplicationURL: URL?
    let activity: @Sendable () async -> ApplicationActivity
    let trashOperation: @Sendable (URL) throws -> URL

    public init(applicationRoots: [URL]? = nil,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                ownBundleID: String? = Bundle.main.bundleIdentifier,
                ownApplicationURL: URL? = Bundle.main.bundleURL,
                activity: @escaping @Sendable () async -> ApplicationActivity = { await .current() },
                trashOperation: (@Sendable (URL) throws -> URL)? = nil) {
        self.home = home.standardizedFileURL
        self.applicationRoots = (applicationRoots ?? [URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")]).map(\.standardizedFileURL)
        self.ownBundleID = ownBundleID
        self.ownApplicationURL = ownApplicationURL?.standardizedFileURL
        self.activity = activity
        self.trashOperation = trashOperation ?? { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            guard let destination else {
                throw CleanupError.refused("系統未回傳垃圾桶位置，請到 Finder 確認")
            }
            return destination as URL
        }
    }
}
