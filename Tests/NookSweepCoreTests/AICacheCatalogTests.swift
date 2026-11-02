import Foundation
import Testing
@testable import NookSweepCore

@Test func aiCacheCatalogUsesNonOverlappingKnownLeaves() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let paths = [
        ".codex/cache/codex_apps_tools",
        "Library/Caches/Codex/Default/Cache",
        "Library/Caches/Codex/Default/Code Cache",
        "Library/Caches/Codex/Default/Partitions/codex-browser-app/Cache",
        "Library/Caches/Codex/codex-browser-app/Code Cache",
        "Library/Application Support/Codex/Cache",
        "Library/Application Support/Codex/Default/GPUCache",
        "Library/Application Support/Codex/Default/Shared Dictionary/cache",
        "Library/Application Support/Codex/Default/Service Worker/CacheStorage",
        "Library/Application Support/Codex/codex-browser-app/Shared Dictionary/cache",
        "Library/Application Support/Claude/Partitions/cowork-file-preview/Cache",
        "Library/Application Support/Cursor/Profile 2/DawnWebGPUCache",
        "Library/Application Support/ChatGPT/extensions_crx_cache"
    ]
    for path in paths { try fixture.cache(path) }
    let entries = try AICacheCatalog.candidates(home: fixture.home)
    #expect(Set(entries.map(\.url.path)) == Set(paths.map { fixture.home.appendingPathComponent($0).path }))
    #expect(entries.allSatisfy { $0.category == .aiCaches && $0.metadata.kind == .cache && $0.preservationReason == nil })
    for entry in entries {
        #expect(try AICacheCatalog.entry(for: entry.url, home: fixture.home)?.metadata == entry.metadata)
        #expect(!entries.contains { $0.url != entry.url && $0.url.path.hasPrefix(entry.url.path + "/") })
    }
}

@Test func aiCacheCatalogNeverClaimsProfileDataOrSimilarNames() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let paths = [
        "Library/Application Support/Codex/Cookies",
        "Library/Application Support/Codex/Default/Session Storage/state",
        "Library/Application Support/Codex/Default/Local Storage/leveldb/000001.log",
        "Library/Application Support/Codex/Default/IndexedDB/data.db",
        "Library/Application Support/Codex/Shared Dictionary/db",
        "Library/Application Support/Codex/memory/Cache/data",
        "Library/Application Support/CodexBackup/Cache/data",
        "Library/Application Support/Cursor/User/Cache/data",
        "Library/Caches/CodexPlugin/Cache/data",
        ".codex/auth.json"
    ]
    for path in paths {
        let file = try fixture.aiFile(path)
        #expect(try AICacheCatalog.entry(for: file, home: fixture.home) == nil)
        #expect(try AICacheCatalog.entry(for: file.deletingLastPathComponent(), home: fixture.home) == nil)
    }
    #expect(try AICacheCatalog.candidates(home: fixture.home).isEmpty)
    #expect(AICacheCatalog.replacesGenericCache(fixture.home.appendingPathComponent("Library/Caches/Codex"), home: fixture.home))
    #expect(!AICacheCatalog.replacesGenericCache(fixture.home.appendingPathComponent("Library/Caches/CodexPlugin"), home: fixture.home))
    #expect(!AICacheCatalog.replacesGenericCache(fixture.home.appendingPathComponent("Library/Caches/com.openai.codex"), home: fixture.home))
}

@Test func aiCacheCatalogPreservesUnknownCodexCacheAndTemporaryItems() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let unknown = try fixture.cache(".codex/cache/unknown-cache")
    let temporary = try fixture.cache(".codex/.tmp/unknown-task")
    let lock = try fixture.aiFile(".codex/.tmp/plugins.sync.lock")
    let entries = try AICacheCatalog.candidates(home: fixture.home)
    #expect(Set(entries.map { $0.url.standardizedFileURL.path }) ==
        Set([unknown, temporary, lock].map { $0.standardizedFileURL.path }))
    #expect(entries.allSatisfy { $0.preservationReason != nil })
}

@Test func codexGitStagingRequiresExactMetadataAndNoCheckoutOrLocks() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    for name in ["git-ABC123", "git-DEF456", "git-GHI789", "git-NOT-STAGING"] {
        let root = ".codex/.tmp/\(name)"
        try fixture.aiFile(root + "/HEAD")
        for directory in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: fixture.home.appendingPathComponent(root + "/" + directory),
                                                    withIntermediateDirectories: true)
        }
    }
    try fixture.aiFile(".codex/.tmp/git-DEF456/source.swift")
    try fixture.aiFile(".codex/.tmp/git-GHI789/objects/pack/pack.lock")
    let root = fixture.home.appendingPathComponent(".codex/.tmp")
    #expect(try AICacheCatalog.entry(for: root.appendingPathComponent("git-ABC123"), home: fixture.home)?.preservationReason == nil)
    for name in ["git-DEF456", "git-GHI789", "git-NOT-STAGING"] {
        #expect(try AICacheCatalog.entry(for: root.appendingPathComponent(name), home: fixture.home)?.preservationReason != nil)
    }
}

@Test func aiCacheCatalogRejectsSymlinkedAncestorsAndLeaves() throws {
    let fixture = try Fixture()
    defer { try? fixture.dispose() }
    let external = try fixture.cache("Documents/important")
    let app = fixture.home.appendingPathComponent("Library/Application Support/Codex")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Cache"), withDestinationURL: external)
    try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Default"), withDestinationURL: external)
    #expect(try AICacheCatalog.candidates(home: fixture.home).isEmpty)
    #expect(try AICacheCatalog.entry(for: app.appendingPathComponent("Cache"), home: fixture.home) == nil)
    #expect(try AICacheCatalog.entry(for: app.appendingPathComponent("Default/GPUCache"), home: fixture.home) == nil)
}
