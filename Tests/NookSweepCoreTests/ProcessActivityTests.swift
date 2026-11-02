import Testing
@testable import NookSweepCore

@Test func nativeAIToolProcessesAreRecognized() {
    #expect(AIProcessActivity.toolID(processName: "codex-aarch64-apple-darwin", executablePath: "") == "codex")
    #expect(AIProcessActivity.toolID(processName: "helper", executablePath: "/Applications/Claude.app/Contents/MacOS/helper") == "claude")
    #expect(AIProcessActivity.toolID(processName: "gemini", executablePath: "/bin/gemini") == "gemini")
}

@Test func unrelatedProcessesDoNotBecomeAITools() {
    #expect(AIProcessActivity.toolID(processName: "node", executablePath: "/opt/node/bin/node") == nil)
    #expect(AIProcessActivity.toolID(processName: "notes", executablePath: "/tmp/my-codex-assets/notes") == nil)
}

@Test func nativeVersionExecutableStillIdentifiesClaude() {
    #expect(AIProcessActivity.toolID(processName: "2.1.218",
        executablePath: "/tmp/test-home/.local/share/claude/versions/2.1.218") == "claude")
    #expect(AIProcessActivity.toolID(processName: "2.1.218",
        executablePath: "/tmp/test-home/share/claude/versions/2.1.218") == nil)
}
