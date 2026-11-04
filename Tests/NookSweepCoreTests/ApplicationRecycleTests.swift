import Foundation
import Testing
@testable import NookSweepCore

@Test func recycleUsesTheConfirmedDestinationEvenWhenTheSystemAlsoReportsAnError() throws {
    let source = URL(fileURLWithPath: "/Applications/Example.app")
    let destination = URL(fileURLWithPath: "/Users/example/.Trash/Example 2.app")
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    #expect(try applicationTrashDestination(for: source, destinations: [source: destination], error: error) == destination)
}

@Test func recyclePreservesTheSystemErrorWhenNoDestinationIsReturned() {
    let source = URL(fileURLWithPath: "/Applications/Example.app")
    let errors = [NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError),
                  NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError),
                  NSError(domain: NSOSStatusErrorDomain, code: -128)]
    for expected in errors {
        do {
            _ = try applicationTrashDestination(for: source, destinations: [:], error: expected)
            Issue.record("未回傳搬移結果時，必須保留系統錯誤")
        } catch { #expect((error as NSError) === expected) }
    }
}

@Test func recycleDoesNotMistakeMissingOrUnrelatedDestinationsForSuccess() {
    let source = URL(fileURLWithPath: "/Applications/Example.app")
    let other = URL(fileURLWithPath: "/Applications/Other.app")
    for destinations in [[:], [other: URL(fileURLWithPath: "/Users/example/.Trash/Other.app")]] {
        do {
            _ = try applicationTrashDestination(for: source, destinations: destinations, error: nil)
            Issue.record("缺少指定 App 的目的地時不得回報成功")
        } catch { #expect(error.localizedDescription.contains("系統未回傳垃圾桶位置")) }
    }
}

@Test func permissionFailureIncludesUnderlyingDomainsAndCodes() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
        userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { _ in throw error })
    let report = await engine.trash(app)
    let message = try #require(report.results.first?.error)
    #expect(message.contains("NSCocoaErrorDomain (513)"))
    #expect(message.contains("NSPOSIXErrorDomain (13)"))
}

@Test func asynchronousRecycleMovesTheAppBeforeSelectedRelatedData() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let moved = fixture.root.appendingPathComponent("Moved.app")
    let movedData = fixture.root.appendingPathComponent("MovedData")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { url in
            await Task.yield()
            if url.path == dataURL.path { #expect(FileManager.default.fileExists(atPath: moved.path)) }
            let destination = url.path == appURL.path ? moved : movedData
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 2)
    #expect(report.results.map(\.originalURL.path) == [appURL.path, dataURL.path])
    #expect(report.results.map(\.trashURL) == [moved, movedData])
}

@Test func cancelledSystemRecycleKeepsTheAppAndSelectedRelatedData() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { url in
            #expect(url.path == appURL.path)
            await Task.yield()
            throw cancelled
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error == cancelled.localizedDescription)
    #expect(report.results.allSatisfy { !$0.needsPermissionHelp })
    #expect(report.results.last?.error == "App 未移除，相關資料已保留")
    #expect(FileManager.default.fileExists(atPath: appURL.path))
    #expect(FileManager.default.fileExists(atPath: dataURL.path))
}

@Test func cancellationAfterTheSystemMovedTheAppStillReportsItsDestination() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let moved = fixture.root.appendingPathComponent("Moved.app")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { url in
            #expect(url.path == appURL.path)
            await Task.yield()
            withUnsafeCurrentTask { $0?.cancel() }
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        })
    let report = await Task { await engine.trash(app, relatedItems: related) }.value
    #expect(report.movedCount == 1)
    #expect(report.results.first?.trashURL == moved)
    #expect(report.results.last?.succeeded == false)
    #expect(FileManager.default.fileExists(atPath: moved.path))
    #expect(FileManager.default.fileExists(atPath: dataURL.path))
}

@Test func finderRefusalDistinguishesAutomationPermissionFromCancellation() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    for code in [-1743, -5000, -54, -128] {
        let error = NSError(domain: NSOSStatusErrorDomain, code: code,
            userInfo: [NSLocalizedDescriptionKey: "Finder 測試結果"])
        let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
            ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
            trashOperation: { _ in throw error })
        let result = try #require(await engine.trash(app).results.first)
        #expect(result.finderAutomationDenied == (code == -1743))
        #expect(result.needsPermissionHelp == (code != -128))
        #expect(!result.succeeded)
        #expect(FileManager.default.fileExists(atPath: appURL.path))
        if code != -128 { #expect(result.error?.contains("NSOSStatusErrorDomain (\(code))") == true) }
    }
}
