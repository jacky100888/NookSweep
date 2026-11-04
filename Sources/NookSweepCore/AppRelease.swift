import Foundation

public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    private let components: [Int]

    public init?(_ value: String) {
        let plain = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = plain.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { 48...57 ~= $0 } }) else {
            return nil
        }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }
    public var description: String { components.map(String.init).joined(separator: ".") }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct AppRelease: Equatable, Sendable {
    public let tag: String
    public let version: ReleaseVersion
    public let pageURL: URL

    public init?(tag: String) {
        guard let version = ReleaseVersion(tag),
              let url = URL(string: "https://github.com/jacky100888/NookSweep/releases/tag/\(tag)") else { return nil }
        self.tag = tag
        self.version = version
        pageURL = url
    }
}

public func fetchLatestRelease() async throws -> AppRelease {
    guard let url = URL(string: "https://api.github.com/repos/jacky100888/NookSweep/releases/latest") else {
        throw ReleaseCheckError.invalidMetadata
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("NookSweep", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw ReleaseCheckError.invalidMetadata }
    return try decodeLatestRelease(data, statusCode: response.statusCode)
}

func decodeLatestRelease(_ data: Data, statusCode: Int) throws -> AppRelease {
    guard (200..<300).contains(statusCode) else { throw ReleaseCheckError.http(statusCode) }
    let value = try JSONDecoder().decode(LatestReleaseMetadata.self, from: data)
    guard !value.draft, !value.prerelease, let release = AppRelease(tag: value.tag_name) else {
        throw ReleaseCheckError.invalidMetadata
    }
    return release
}

private struct LatestReleaseMetadata: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
}

private enum ReleaseCheckError: LocalizedError {
    case http(Int), invalidMetadata

    var errorDescription: String? {
        switch self {
        case .http(let code): "GitHub 暫時無法提供更新資訊（HTTP \(code)）"
        case .invalidMetadata: "無法辨識正式版本的更新資訊"
        }
    }
}
