import Foundation
import Testing
@testable import NookSweepCore

@Test func releaseVersionsCompareNumericComponentsAndIgnoreTagPrefix() throws {
    let old = try #require(ReleaseVersion("1.9.9"))
    let new = try #require(ReleaseVersion("v1.10.0"))
    #expect(new > old)
    #expect(new == ReleaseVersion("1.10.0"))
    #expect(new.description == "1.10.0")
    #expect(ReleaseVersion("2.0.0")! > new)
    #expect(ReleaseVersion("1.9.10")! > old)
}

@Test func releaseVersionsRejectUnstableMalformedOrOversizedTags() {
    for value in ["", "1.2", "1.2.3.4", "-1.2.3", "+1.2.3", "1.2.3-beta.1",
                  "1.2.3+build", "v1.2.3/../../other", " 1.2.3", "1.2.x", "999999999999999999999.0.0"] {
        #expect(ReleaseVersion(value) == nil)
        #expect(AppRelease(tag: value) == nil)
    }
}

@Test func releasePageAlwaysUsesTheOfficialRepositoryAndValidatedTag() throws {
    let release = try #require(AppRelease(tag: "v1.8.0"))
    #expect(release.version.description == "1.8.0")
    #expect(release.pageURL.absoluteString == "https://github.com/jacky100888/NookSweep/releases/tag/v1.8.0")
    #expect(AppRelease(tag: "https://example.com/1.8.0") == nil)
}

@Test func latestReleaseDecodingAcceptsOnlyStablePublishedMetadata() throws {
    let data = Data(#"{"tag_name":"v1.8.0","draft":false,"prerelease":false,"html_url":"https://example.com/untrusted"}"#.utf8)
    let release = try decodeLatestRelease(data, statusCode: 200)
    #expect(release.tag == "v1.8.0")
    #expect(release.pageURL.host == "github.com")
    for body in [
        #"{"tag_name":"v1.8.0","draft":true,"prerelease":false}"#,
        #"{"tag_name":"v1.8.0","draft":false,"prerelease":true}"#,
        #"{"tag_name":"v1.8.0-beta","draft":false,"prerelease":false}"#,
        #"{"tag_name":"v1.8.0"}"#, "not json"
    ] {
        #expect(throws: (any Error).self) { try decodeLatestRelease(Data(body.utf8), statusCode: 200) }
    }
}

@Test func latestReleaseHTTPFailuresNeverBecomeDownloadNotices() {
    let data = Data(#"{"tag_name":"v9.0.0","draft":false,"prerelease":false}"#.utf8)
    for code in [301, 403, 404, 429, 500] {
        #expect(throws: (any Error).self) { try decodeLatestRelease(data, statusCode: code) }
    }
}
