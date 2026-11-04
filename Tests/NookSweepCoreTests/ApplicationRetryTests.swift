import Foundation
import Testing
@testable import NookSweepCore

@Test func finderRetryMovesOnlyAnUnchangedApp() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let destination = fixture.root.appendingPathComponent("FinderTrash.app")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { _ in
            await Task.yield()
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }, finderOperation: { url in
            #expect(url.path == original.path)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
    let report = await engine.trash(app)
    #expect(report.movedCount == 1)
    #expect(report.results.first?.trashURL == destination)
    #expect(!FileManager.default.fileExists(atPath: original.path))
}

@Test func finderRetryRefusesAnAppChangedDuringTheFirstAttempt() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let data = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let payload = original.appendingPathComponent("Contents/binary")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { _ in
            try Data("updated application".utf8).write(to: payload)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }, finderOperation: { _ in
            Issue.record("App 已改變，不可請 Finder 搬移")
            return original
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error?.contains("已改變") == true)
    #expect(try String(contentsOf: payload, encoding: .utf8) == "updated application")
    #expect(FileManager.default.fileExists(atPath: data.path))
}

private actor RetryActivity {
    var running = false
    func start() { running = true }
    func current() -> ApplicationActivity {
        ApplicationActivity(bundleIDs: running ? ["org.example.editor"] : [])
    }
}

@Test func finderRetryRefusesAnAppRestartedDuringTheFirstAttempt() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let activity = RetryActivity()
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { await activity.current() },
        trashOperation: { _ in
            await activity.start()
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }, finderOperation: { _ in
            Issue.record("App 已重新啟動，不可請 Finder 搬移")
            return original
        })
    let report = await engine.trash(app)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error?.contains("執行中") == true)
    #expect(FileManager.default.fileExists(atPath: original.path))
}

@Test func finderRetryRefusesRelatedDataChangedDuringTheFirstAttempt() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let data = try fixture.data("Caches/org.example.editor")
    let baseline = fixture.engine()
    let app = try #require(try await baseline.scan().applications.first)
    let related = try await baseline.relatedData(for: app)
    let destination = fixture.root.appendingPathComponent("Moved.app")
    let payload = data.appendingPathComponent("payload")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { url in
            if url.path == original.path {
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
            try Data("recent user data".utf8).write(to: payload)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }, finderOperation: { _ in
            Issue.record("相關資料已改變，不可請 Finder 搬移")
            return data
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 1)
    #expect(report.results.last?.error?.contains("已改變") == true)
    #expect(try String(contentsOf: payload, encoding: .utf8) == "recent user data")
}

@Test func finderRetryNeverRunsForCancellationOrUnrelatedErrors() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    for code in [NSUserCancelledError, NSFileWriteUnknownError] {
        let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
            ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
            trashOperation: { _ in throw NSError(domain: NSCocoaErrorDomain, code: code) },
            finderOperation: { _ in
                Issue.record("非權限錯誤不可重試 Finder")
                return original
            })
        #expect(await engine.trash(app).movedCount == 0)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }
}

@Test func finderRetryNeverStartsAfterTaskCancellation() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
        trashOperation: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        }, finderOperation: { _ in
            Issue.record("任務已取消，不可開始 Finder 驗證")
            return original
        })
    let report = await Task { await engine.trash(app) }.value
    #expect(report.movedCount == 0)
    #expect(FileManager.default.fileExists(atPath: original.path))
}

private actor RetryActivitySequence {
    var calls = 0
    func current() -> ApplicationActivity {
        calls += 1
        return ApplicationActivity(bundleIDs: calls >= 4 ? ["org.example.editor"] : [])
    }
}

@Test func finderRetryChecksActivityAgainAfterMeasuringTheApp() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let original = try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    let activity = RetryActivitySequence()
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil, activity: { await activity.current() },
        trashOperation: { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) },
        finderOperation: { _ in
            Issue.record("重試量測後已啟動，不可請 Finder 搬移")
            return original
        })
    let report = await engine.trash(app)
    #expect(report.movedCount == 0)
    #expect(report.results.first?.error?.contains("執行中") == true)
    #expect(FileManager.default.fileExists(atPath: original.path))
}
