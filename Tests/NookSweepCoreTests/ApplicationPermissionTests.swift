import Darwin
import Foundation
import Testing
@testable import NookSweepCore

@Test func applicationPermissionErrorsPreserveAppAndRelatedData() async throws {
    let errors = [
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError),
        NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
        NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
        NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
    ]
    for error in errors {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        let appURL = try fixture.app()
        let dataURL = try fixture.data("Caches/org.example.editor")
        let baseline = fixture.engine()
        let app = try #require(try await baseline.scan().applications.first)
        let related = try await baseline.relatedData(for: app)
        let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
            ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
            trashOperation: { _ in throw error })
        let report = await engine.trash(app, relatedItems: related)
        #expect(report.movedCount == 0)
        #expect(report.results.first?.error?.contains("權限") == true)
        #expect(report.results.first?.needsPermissionHelp == true)
        #expect(report.results.first?.error?.contains(error.localizedDescription) == true)
        #expect(report.results.last?.error == "App 未移除，相關資料已保留")
        #expect(report.results.last?.needsPermissionHelp == false)
        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(FileManager.default.fileExists(atPath: dataURL.appendingPathComponent("payload").path))
    }
}

@Test func applicationOtherErrorsDoNotSuggestGrantingPermissions() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    try fixture.app()
    let app = try #require(try await fixture.engine().scan().applications.first)
    for (domain, code) in [(NSCocoaErrorDomain, NSFileNoSuchFileError),
                           (NSCocoaErrorDomain, NSUserCancelledError),
                           (NSCocoaErrorDomain, NSFileWriteUnknownError),
                           ("org.example.error", NSFileWriteNoPermissionError)] {
        let error = NSError(domain: domain, code: code,
                            userInfo: [NSLocalizedDescriptionKey: "permission denied fixture"])
        let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
            ownBundleID: nil, ownApplicationURL: nil, activity: { ApplicationActivity() },
            trashOperation: { _ in throw error })
        let report = await engine.trash(app)
        #expect(report.movedCount == 0)
        #expect(report.results.first?.needsPermissionHelp == false)
        #expect(report.results.first?.error == error.localizedDescription)
    }
}

@Test func applicationPermissionFailureAfterAppRemovalKeepsRelatedData() async throws {
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
            guard url.path == appURL.path else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
            }
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        })
    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 1)
    #expect(report.results.first?.needsPermissionHelp == false)
    #expect(report.results.last?.needsPermissionHelp == true)
    #expect(FileManager.default.fileExists(atPath: dataURL.appendingPathComponent("payload").path))
}
