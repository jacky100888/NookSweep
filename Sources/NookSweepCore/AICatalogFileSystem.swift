import Foundation

enum AICatalogFileSystem {
    static func relativeParts(of url: URL, home: URL) -> [String]? {
        let components = url.standardizedFileURL.pathComponents
        for root in [home.resolvingSymlinksInPath().standardizedFileURL, home.standardizedFileURL] {
            let prefix = root.pathComponents
            if components.starts(with: prefix) { return Array(components.dropFirst(prefix.count)) }
        }
        return nil
    }

    static func canonicalURL(_ url: URL, home: URL) -> URL? {
        guard let parts = relativeParts(of: url, home: home) else { return nil }
        return parts.reduce(home.resolvingSymlinksInPath().standardizedFileURL) {
            $0.appendingPathComponent($1)
        }
    }

    static func type(of url: URL, home: URL) throws -> FileAttributeType? {
        guard let parts = relativeParts(of: url, home: home) else { return nil }
        var current = home.resolvingSymlinksInPath().standardizedFileURL
        guard try attributes(at: current)?[.type] as? FileAttributeType == .typeDirectory else { return nil }
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            current.appendPathComponent(part)
            guard let type = try attributes(at: current)?[.type] as? FileAttributeType,
                  type != .typeSymbolicLink else { return nil }
            if index == parts.count - 1 { return type }
            guard type == .typeDirectory else { return nil }
        }
        return .typeDirectory
    }

    static func children(of url: URL, home: URL) throws -> [URL] {
        guard try type(of: url, home: home) == .typeDirectory,
              let canonical = canonicalURL(url, home: home) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: canonical, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) { return nil }
            throw error
        }
    }
}
