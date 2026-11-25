import Foundation
import Testing
@testable import ReadbackCore

/// Only works out paths; nothing here reads or writes the folders it names.
@Suite(.serialized) struct ClaudeConfigDirTests {
    private func with(_ value: String?, _ body: () -> Void) {
        let before = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        if let value { setenv("CLAUDE_CONFIG_DIR", value, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") }
        body()
        if let before { setenv("CLAUDE_CONFIG_DIR", before, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") }
    }

    @Test func aSecondLoginsFolderIsUsedForTheRealHome() {
        guard ProcessInfo.processInfo.environment["READBACK_HOME"] == nil else { return }
        with("/Users/someone/.claude-work") {
            #expect(ReadbackPaths().claudeDir.path == "/Users/someone/.claude-work")
            #expect(ReadbackPaths().claudeSettings.path == "/Users/someone/.claude-work/settings.json")
        }
        with("~/.claude-work") {
            #expect(ReadbackPaths().claudeDir.path == ReadbackPaths.defaultHome.path + "/.claude-work")
        }
    }

    @Test func withoutItItsTheUsualFolder() {
        guard ProcessInfo.processInfo.environment["READBACK_HOME"] == nil else { return }
        with(nil) {
            #expect(ReadbackPaths().claudeDir.path == ReadbackPaths.defaultHome.path + "/.claude")
        }
    }

    @Test func aTestsFakeHomeNeverFollowsIt() {
        let fake = URL(fileURLWithPath: "/tmp/readback-fake-home")
        with("/Users/someone/.claude-work") {
            #expect(ReadbackPaths(home: fake).claudeDir.path == "/tmp/readback-fake-home/.claude")
        }
    }
}
