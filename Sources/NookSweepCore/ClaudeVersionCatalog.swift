import Foundation

enum ClaudeVersionCatalog {
    private static let directory = ".local/share/claude/versions"

    static func candidates(home: URL) throws -> [AICatalogEntry] {
        let root = home.resolvingSymlinksInPath().appendingPathComponent(directory)
        return try AICatalogFileSystem.children(of: root, home: home).compactMap { try entry(for: $0, home: home) }
    }

    static func entry(for url: URL, home: URL) throws -> AICatalogEntry? {
        guard let parts = AICatalogFileSystem.relativeParts(of: url, home: home),
              parts.count == 5, Array(parts.prefix(4)) == [".local", "share", "claude", "versions"],
              let canonical = AICatalogFileSystem.canonicalURL(url, home: home),
              try AICatalogFileSystem.type(of: canonical, home: home) == .typeRegular else { return nil }
        let current = try currentVersion(home: home)
        let version = ClaudeSemanticVersion(parts[4])
        let reason: String?
        if current?.url == canonical { reason = "目前使用中的 Claude 版本，保留原狀" }
        else if version == nil { reason = "無法辨識版本檔名，保留原狀" }
        else if current == nil { reason = "無法確認目前使用中的 Claude 版本，全部保留" }
        else if let version, let current, version < current.version { reason = nil }
        else { reason = "版本不早於目前使用中的版本，保留原狀" }
        return AICatalogEntry(url: canonical, category: .aiVersions,
                              metadata: AIItemMetadata(toolID: "claude", kind: .oldVersion,
                                                       title: "Claude Code \(parts[4])",
                                                       note: "目前版本：\(current?.url.lastPathComponent ?? "無法確認")"),
                              preservationReason: reason)
    }

    private static func currentVersion(home: URL) throws -> (url: URL, version: ClaudeSemanticVersion)? {
        let root = home.resolvingSymlinksInPath().standardizedFileURL
        let bin = root.appendingPathComponent(".local/bin")
        guard try AICatalogFileSystem.type(of: bin, home: root) == .typeDirectory else { return nil }
        let link = bin.appendingPathComponent("claude")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: link.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) { return nil }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else { return nil }
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        let target = destination.hasPrefix("/") ? URL(fileURLWithPath: destination) : bin.appendingPathComponent(destination)
        guard let parts = AICatalogFileSystem.relativeParts(of: target, home: root),
              parts.count == 5, Array(parts.prefix(4)) == [".local", "share", "claude", "versions"],
              let version = ClaudeSemanticVersion(parts[4]),
              let canonical = AICatalogFileSystem.canonicalURL(target, home: root),
              try AICatalogFileSystem.type(of: canonical, home: root) == .typeRegular else { return nil }
        return (canonical, version)
    }
}

private struct ClaudeSemanticVersion: Comparable {
    let numbers: [String]
    let prerelease: [String]

    init?(_ name: String) {
        let build = name.split(separator: "+", omittingEmptySubsequences: false)
        guard build.count <= 2, build.count == 1 || Self.validIdentifiers(String(build[1]), prerelease: false) else { return nil }
        let components = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = components[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard numbers.count == 3, numbers.allSatisfy(Self.validNumber),
              components.count == 1 || Self.validIdentifiers(String(components[1]), prerelease: true) else { return nil }
        self.numbers = numbers
        self.prerelease = components.count == 1 ? [] : components[1].split(separator: ".").map(String.init)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.numbers, rhs.numbers) where left != right {
            return numberLess(left, right)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumber = left.allSatisfy { $0.isASCII && $0.isNumber }
            let rightNumber = right.allSatisfy { $0.isASCII && $0.isNumber }
            if leftNumber && rightNumber { return numberLess(left, right) }
            if leftNumber != rightNumber { return leftNumber }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func validNumber(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber } && (value == "0" || !value.hasPrefix("0"))
    }

    private static func numberLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    private static func validIdentifiers(_ value: String, prerelease: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } &&
                (!prerelease || !part.allSatisfy { $0.isNumber } || validNumber(String(part)))
        }
    }
}
