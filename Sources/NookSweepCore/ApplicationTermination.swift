import AppKit
import Foundation

func applicationProcessBelongsToApp(_ applicationURL: URL, bundleURL: URL?, executableURL: URL?) -> Bool {
    let path = applicationURL.standardizedFileURL.path
    return [bundleURL, executableURL].compactMap { $0 }.contains {
        let candidate = $0.standardizedFileURL.path
        return candidate == path || candidate.hasPrefix(path + "/")
    }
}

@MainActor
func terminateApplication(_ url: URL, mode: ApplicationTerminationMode) async throws {
    guard mode != .none else { return }
    let applications = NSWorkspace.shared.runningApplications.filter {
        applicationProcessBelongsToApp(url, bundleURL: $0.bundleURL, executableURL: $0.executableURL)
    }
    for application in applications where !application.isTerminated {
        try Task.checkCancellation()
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw CleanupError.refused("NookSweep 無法結束自身")
        }
        let requested = mode == .force ? application.forceTerminate() : application.terminate()
        guard requested || application.isTerminated else {
            throw CleanupError.refused("App 拒絕結束，已保留；可重新掃描後選擇強制結束並移除")
        }
    }
    let deadline = Date().addingTimeInterval(5)
    while applications.contains(where: { !$0.isTerminated }) {
        try Task.checkCancellation()
        guard Date() < deadline else {
            throw CleanupError.refused("App 未於 5 秒內結束，已保留；可重新掃描後選擇強制結束並移除")
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}
