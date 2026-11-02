import Foundation

enum AICacheCatalog {
    private static let applications = [("Codex", "codex"), ("Claude", "claude"),
                                       ("Cursor", "cursor"), ("ChatGPT", "chatgpt")]
    private static let cacheLeaves = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache",
                                      "DawnWebGPUCache", "GraphiteDawnCache", "component_crx_cache",
                                      "extensions_crx_cache", "Shared Dictionary/cache",
                                      "Service Worker/CacheStorage", "Service Worker/ScriptCache"]
    private static let codexCaches = Set(["bundled_plugin_exclusions", "codex_app_directory",
                                         "codex_apps_server_info", "codex_apps_tools", "remote_plugin_catalog"])

    static func candidates(home: URL) throws -> [AICatalogEntry] {
        let home = home.resolvingSymlinksInPath().standardizedFileURL
        var entries: [AICatalogEntry] = []
        for relative in [".codex/cache", ".codex/.tmp"] {
            for child in try AICatalogFileSystem.children(of: home.appendingPathComponent(relative), home: home) {
                if let entry = try entry(for: child, home: home) { entries.append(entry) }
            }
        }
        for (application, _) in applications {
            for parent in ["Library/Caches", "Library/Application Support"] {
                let root = home.appendingPathComponent(parent + "/" + application)
                var containers = [root]
                let children = try AICatalogFileSystem.children(of: root, home: home)
                for child in children where isProfile(child.lastPathComponent) ||
                    (application == "Codex" && child.lastPathComponent == "codex-browser-app") {
                    if try AICatalogFileSystem.type(of: child, home: home) == .typeDirectory {
                        containers.append(child)
                    }
                }
                for container in containers {
                    for partition in try AICatalogFileSystem.children(of: container.appendingPathComponent("Partitions"), home: home) {
                        if try AICatalogFileSystem.type(of: partition, home: home) == .typeDirectory {
                            for leaf in cacheLeaves {
                                if let item = try entry(for: partition.appendingPathComponent(leaf), home: home) { entries.append(item) }
                            }
                        }
                    }
                    for leaf in cacheLeaves {
                        if let item = try entry(for: container.appendingPathComponent(leaf), home: home) { entries.append(item) }
                    }
                }
                if parent == "Library/Caches" {
                    for child in children where !isContainerName(child.lastPathComponent, application: application) &&
                        !cacheLeaves.contains(child.lastPathComponent) && !["Shared Dictionary", "Service Worker"].contains(child.lastPathComponent) {
                        if let item = try entry(for: child, home: home) { entries.append(item) }
                    }
                }
            }
        }
        return entries.sorted { $0.url.path < $1.url.path }
    }

    static func entry(for url: URL, home: URL) throws -> AICatalogEntry? {
        guard let parts = AICatalogFileSystem.relativeParts(of: url, home: home),
              let canonical = AICatalogFileSystem.canonicalURL(url, home: home),
              let type = try AICatalogFileSystem.type(of: canonical, home: home),
              [.typeDirectory, .typeRegular].contains(type) else { return nil }
        if parts.count == 3, parts[0] == ".codex", ["cache", ".tmp"].contains(parts[1]) {
            let known = parts[1] == "cache" ? codexCaches.contains(parts[2]) && type == .typeDirectory :
                try isGitStaging(canonical, home: home)
            return makeEntry(canonical, tool: "codex", title: "Codex \(parts[2])",
                             reason: known ? nil : "無法確認可重建的快取或暫存格式，保留原狀")
        }
        guard parts.count > 3, parts[0] == "Library",
              ["Caches", "Application Support"].contains(parts[1]),
              let (application, tool) = applications.first(where: { $0.0 == parts[2] }) else { return nil }
        let remainder = Array(parts.dropFirst(3))
        for leaf in cacheLeaves {
            let suffix = leaf.split(separator: "/").map(String.init)
            guard remainder.suffix(suffix.count).elementsEqual(suffix),
                  isContainer(Array(remainder.dropLast(suffix.count)), application: application) else { continue }
            return makeEntry(canonical, tool: tool, title: "\(application) \(leaf)",
                             reason: type == .typeDirectory ? nil : "預期為快取目錄，格式不符而保留原狀")
        }
        if parts[1] == "Caches", remainder.count == 1,
           !isContainerName(remainder[0], application: application),
           !["Shared Dictionary", "Service Worker"].contains(remainder[0]) {
            return makeEntry(canonical, tool: tool, title: "\(application) \(remainder[0])",
                             reason: "不在已確認的快取葉節點清單，保留原狀")
        }
        return nil
    }

    static func replacesGenericCache(_ url: URL, home: URL) -> Bool {
        guard let parts = AICatalogFileSystem.relativeParts(of: url, home: home),
              parts.count == 3, parts[0] == "Library", parts[1] == "Caches" else { return false }
        return applications.contains { $0.0 == parts[2] }
    }

    private static func isContainer(_ parts: [String], application: String) -> Bool {
        if parts.isEmpty { return true }
        if parts.count == 1 {
            return isProfile(parts[0]) || (application == "Codex" && parts[0] == "codex-browser-app")
        }
        guard parts.count >= 2, parts[parts.count - 2] == "Partitions" else { return false }
        return isContainer(Array(parts.dropLast(2)), application: application) && parts.count <= 3
    }

    private static func isContainerName(_ name: String, application: String) -> Bool {
        name == "Partitions" || isProfile(name) || (application == "Codex" && name == "codex-browser-app")
    }

    private static func isProfile(_ name: String) -> Bool {
        name == "Default" || (name.hasPrefix("Profile ") && !name.dropFirst(8).isEmpty &&
            name.dropFirst(8).allSatisfy { $0.isASCII && $0.isNumber })
    }

    private static func isGitStaging(_ url: URL, home: URL) throws -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("git-"), name.count == 10,
              name.dropFirst(4).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              try AICatalogFileSystem.type(of: url, home: home) == .typeDirectory else { return false }
        let children = try AICatalogFileSystem.children(of: url, home: home)
        guard Set(children.map(\.lastPathComponent)) == ["HEAD", "objects", "refs"],
              try AICatalogFileSystem.type(of: url.appendingPathComponent("HEAD"), home: home) == .typeRegular else { return false }
        for name in ["objects", "refs"] {
            guard try AICatalogFileSystem.type(of: url.appendingPathComponent(name), home: home) == .typeDirectory else { return false }
        }
        var pending = children.filter { $0.lastPathComponent != "HEAD" }
        while let child = pending.popLast() {
            try Task.checkCancellation()
            guard let type = try AICatalogFileSystem.type(of: child, home: home),
                  [.typeDirectory, .typeRegular].contains(type) else { return false }
            let parts = Array(child.pathComponents.dropFirst(url.pathComponents.count))
            let lower = child.lastPathComponent.lowercased()
            if lower == "lock" || lower.hasSuffix(".lock") { return false }
            if parts[0] == "objects", !isGitObject(parts, isDirectory: type == .typeDirectory) { return false }
            if type == .typeDirectory {
                pending.append(contentsOf: try AICatalogFileSystem.children(of: child, home: home))
            }
        }
        return true
    }

    private static func isGitObject(_ parts: [String], isDirectory: Bool) -> Bool {
        if parts.count == 1 { return isDirectory }
        if parts.count == 2 {
            return isDirectory && (["pack", "info"].contains(parts[1]) || isHex(parts[1], lengths: [2]))
        }
        guard parts.count == 3, !isDirectory else { return false }
        if isHex(parts[1], lengths: [2]) { return isHex(parts[2], lengths: [38, 62]) }
        if parts[1] == "pack" {
            let file = URL(fileURLWithPath: parts[2])
            let stem = file.deletingPathExtension().lastPathComponent
            return ["pack", "idx", "rev"].contains(file.pathExtension) && stem.hasPrefix("pack-") &&
                isHex(String(stem.dropFirst(5)), lengths: [40, 64])
        }
        return false
    }

    private static func isHex(_ value: String, lengths: [Int]) -> Bool {
        lengths.contains(value.count) && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func makeEntry(_ url: URL, tool: String, title: String, reason: String?) -> AICatalogEntry {
        AICatalogEntry(url: url, category: .aiCaches,
                       metadata: AIItemMetadata(toolID: tool, kind: .cache, title: title), preservationReason: reason)
    }
}
