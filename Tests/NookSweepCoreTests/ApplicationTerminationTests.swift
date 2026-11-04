import Foundation
import Testing
@testable import NookSweepCore

private func terminationModeName(_ mode: ApplicationTerminationMode) -> String {
    switch mode {
    case .none: "none"
    case .quit: "quit"
    case .force: "force"
    }
}

private actor TerminationFixtureState {
    let appURL: URL
    let bundleID: String
    let relaunchAfterMove: Bool
    var running = true
    var requests: [String] = []
    var requestedURLs: [URL] = []

    init(appURL: URL, bundleID: String = "org.example.editor", relaunchAfterMove: Bool = false) {
        self.appURL = appURL
        self.bundleID = bundleID
        self.relaunchAfterMove = relaunchAfterMove
    }

    func activity() -> ApplicationActivity {
        let active = running || (relaunchAfterMove && !FileManager.default.fileExists(atPath: appURL.path))
        return active ? ApplicationActivity(bundleIDs: [bundleID], applicationPaths: [appURL.path])
            : ApplicationActivity()
    }

    func record(_ url: URL, mode: ApplicationTerminationMode) {
        requestedURLs.append(url)
        requests.append(terminationModeName(mode))
    }

    func stop() { running = false }
}

private func terminationEngine(_ fixture: ApplicationFixture, state: TerminationFixtureState,
    ownID: String? = nil,
    terminate: @escaping @Sendable (URL, ApplicationTerminationMode) async throws -> Void) -> ApplicationsEngine {
    ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: ownID, ownApplicationURL: nil, activity: { await state.activity() },
        terminateOperation: { url, mode in
            await state.record(url, mode: mode)
            try await terminate(url, mode)
        }, trashOperation: { url in
            let destination = url.deletingLastPathComponent().appendingPathComponent("Moved-" + UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
}

@Test func applicationQuitAndForceStopBeforeMovingAppAndRelatedData() async throws {
    let modes: [ApplicationTerminationMode] = [.quit, .force]
    for mode in modes {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        let appURL = try fixture.app()
        let dataURL = try fixture.data("Caches/org.example.editor")
        let state = TerminationFixtureState(appURL: appURL)
        let engine = terminationEngine(fixture, state: state) { url, _ in
            #expect(url.path == appURL.path)
            #expect(FileManager.default.fileExists(atPath: appURL.path))
            #expect(FileManager.default.fileExists(atPath: dataURL.path))
            await state.stop()
        }
        let app = try #require(try await engine.scan().applications.first)
        #expect(app.isRemovable)
        #expect(app.isRunning)
        let related = try await engine.relatedData(for: app)
        #expect(related.count == 1 && related.allSatisfy(\.isSelectable))

        let report = await engine.trash(app, relatedItems: related, terminationMode: mode)
        #expect(report.movedCount == 2)
        #expect(report.results.allSatisfy { $0.succeeded })
        #expect(await state.requests == [terminationModeName(mode)])
        #expect(await state.requestedURLs.map(\.path) == [appURL.path])
        #expect(!FileManager.default.fileExists(atPath: appURL.path))
        #expect(!FileManager.default.fileExists(atPath: dataURL.path))
    }
}

@Test func applicationDefaultRemovalDoesNotTerminateRunningApp() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let state = TerminationFixtureState(appURL: appURL)
    let engine = terminationEngine(fixture, state: state) { _, _ in await state.stop() }
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)

    let report = await engine.trash(app, relatedItems: related)
    #expect(report.movedCount == 0)
    #expect(report.results.count == 2 && report.results.allSatisfy { !$0.succeeded })
    #expect(await state.requests.isEmpty)
    #expect(FileManager.default.fileExists(atPath: appURL.path))
    #expect(FileManager.default.fileExists(atPath: dataURL.path))
}

@Test func applicationFailedOrIncompleteTerminationPreservesAllSelectedData() async throws {
    for refuses in [true, false] {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        let appURL = try fixture.app()
        let dataURL = try fixture.data("Caches/org.example.editor")
        let state = TerminationFixtureState(appURL: appURL)
        let engine = terminationEngine(fixture, state: state) { _, _ in
            if refuses { throw CleanupError.refused("測試拒絕終止") }
        }
        let app = try #require(try await engine.scan().applications.first)
        let related = try await engine.relatedData(for: app)

        let report = await engine.trash(app, relatedItems: related, terminationMode: .force)
        #expect(report.movedCount == 0)
        #expect(report.results.count == 2 && report.results.allSatisfy { !$0.succeeded })
        #expect(await state.requests == ["force"])
        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(FileManager.default.fileExists(atPath: dataURL.path))
    }
}

@Test func applicationInvalidOrProtectedRecordCannotTriggerTermination() async throws {
    for protection in ["own", "apple", "outside", "symlink", "identity", "fingerprint"] {
        let fixture = try ApplicationFixture()
        defer { try? fixture.dispose() }
        let bundleID = protection == "apple" ? "com.apple.fixture" : "org.example.editor"
        let appURL = try fixture.app(id: bundleID)
        let size = try applicationMeasure(appURL)
        var selectedURL = appURL
        if protection == "outside" {
            selectedURL = fixture.home.appendingPathComponent("Outside.app")
            try FileManager.default.moveItem(at: appURL, to: selectedURL)
        } else if protection == "symlink" {
            let moved = fixture.home.appendingPathComponent("Preserved.app")
            try FileManager.default.moveItem(at: appURL, to: moved)
            try FileManager.default.createSymbolicLink(at: appURL, withDestinationURL: moved)
        }
        let state = TerminationFixtureState(appURL: selectedURL, bundleID: bundleID)
        let engine = terminationEngine(fixture, state: state,
            ownID: protection == "own" ? bundleID : nil) { _, _ in await state.stop() }
        let app = ApplicationRecord(url: selectedURL, name: "Example",
            bundleID: protection == "identity" ? "org.forged.editor" : bundleID,
            version: "1.2.3", bytes: size.bytes, fileCount: size.fileCount, isRunning: true,
            blockedReason: nil, fingerprint: protection == "fingerprint" ? "changed" : size.fingerprint)

        let report = await engine.trash(app, terminationMode: .force)
        #expect(report.movedCount == 0)
        #expect(report.results.first?.succeeded == false)
        #expect(await state.requests.isEmpty)
        #expect(FileManager.default.fileExists(atPath: selectedURL.path))
    }
}

@Test func applicationChangedWhileTerminatingIsRevalidatedBeforeTrash() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let state = TerminationFixtureState(appURL: appURL)
    let engine = terminationEngine(fixture, state: state) { url, _ in
        try Data("終止期間被更新的 App".utf8).write(to: url.appendingPathComponent("Contents/binary"))
        await state.stop()
    }
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)

    let report = await engine.trash(app, relatedItems: related, terminationMode: .quit)
    #expect(report.movedCount == 0)
    #expect(report.results.count == 2 && report.results.allSatisfy { !$0.succeeded })
    #expect(await state.requests == ["quit"])
    #expect(FileManager.default.fileExists(atPath: appURL.path))
    #expect(FileManager.default.fileExists(atPath: dataURL.path))
}

@Test func applicationRestartAfterAppMovePreservesRelatedData() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let state = TerminationFixtureState(appURL: appURL, relaunchAfterMove: true)
    let engine = terminationEngine(fixture, state: state) { _, _ in await state.stop() }
    let app = try #require(try await engine.scan().applications.first)
    let related = try await engine.relatedData(for: app)

    let report = await engine.trash(app, relatedItems: related, terminationMode: .force)
    #expect(report.movedCount == 1)
    #expect(report.results.first?.succeeded == true)
    #expect(report.results.last?.error?.contains("執行中") == true)
    #expect(await state.requests == ["force"])
    #expect(FileManager.default.fileExists(atPath: dataURL.path))
}

@Test func applicationTerminationTargetsOnlyExactAppAndItsInternalProcesses() {
    let app = URL(fileURLWithPath: "/NookSweep-Process-Fixture/Example.app")
    let helper = app.appendingPathComponent("Contents/Frameworks/Helper.app")
    let executable = app.appendingPathComponent("Contents/MacOS/Example")
    let otherCopy = URL(fileURLWithPath: "/Other-Applications/Example.app")
    let similarPrefix = URL(fileURLWithPath: "/NookSweep-Process-Fixture/Example.app-extra")
    #expect(applicationProcessBelongsToApp(app, bundleURL: app, executableURL: nil))
    #expect(applicationProcessBelongsToApp(app, bundleURL: helper, executableURL: nil))
    #expect(applicationProcessBelongsToApp(app, bundleURL: nil, executableURL: executable))
    #expect(!applicationProcessBelongsToApp(app, bundleURL: otherCopy, executableURL: nil))
    #expect(!applicationProcessBelongsToApp(app, bundleURL: similarPrefix, executableURL: nil))
    #expect(!applicationProcessBelongsToApp(app, bundleURL: nil,
        executableURL: similarPrefix.appendingPathComponent("Contents/MacOS/Example")))
    #expect(!applicationProcessBelongsToApp(app, bundleURL: nil, executableURL: nil))
}

@Test func applicationRunningInternalHelperStillPreventsRemoval() async throws {
    let fixture = try ApplicationFixture()
    defer { try? fixture.dispose() }
    let appURL = try fixture.app()
    let dataURL = try fixture.data("Caches/org.example.editor")
    let helper = appURL.appendingPathComponent("Contents/Frameworks/Helper.app")
    let engine = ApplicationsEngine(applicationRoots: [fixture.applications], home: fixture.home,
        ownBundleID: nil, ownApplicationURL: nil,
        activity: { ApplicationActivity(bundleIDs: ["org.example.helper"], applicationPaths: [helper.path]) },
        terminateOperation: { _, _ in },
        trashOperation: { _ in throw CleanupError.refused("測試不可移動仍在使用的 App") })
    let app = try #require(try await engine.scan().applications.first)
    #expect(app.isRunning)
    let related = try await engine.relatedData(for: app)
    for mode: ApplicationTerminationMode in [.none, .force] {
        let report = await engine.trash(app, relatedItems: related, terminationMode: mode)
        #expect(report.movedCount == 0)
        #expect(report.results.first?.error?.contains("執行中") == true)
        #expect(FileManager.default.fileExists(atPath: appURL.path))
        #expect(FileManager.default.fileExists(atPath: dataURL.path))
    }
}
