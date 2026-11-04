import AppKit
import Foundation

@MainActor
func recycleApplication(_ url: URL) async throws -> URL {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
        NSWorkspace.shared.recycle([url]) { destinations, error in
            continuation.resume(with: Result {
                try applicationTrashDestination(for: url, destinations: destinations, error: error)
            })
        }
    }
}

func applicationTrashDestination(for source: URL, destinations: [URL: URL], error: Error?) throws -> URL {
    if let destination = destinations[source] { return destination }
    if let error { throw error }
    throw CleanupError.refused("系統未回傳垃圾桶位置，請到 Finder 確認")
}
