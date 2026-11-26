import Foundation
import Testing
@testable import ReadbackCore

/// History's matching: a session (from Home's "See all N replies"), a tool, and search words.
@Suite struct ReplyFilterTests {
    private func reply(_ text: String, session: String?, cwd: String? = "/Users/x/code/readback",
                       source: String? = "claude") -> Reply {
        Reply(text: text, source: source, cwd: cwd, session: session, state: .played)
    }

    @Test func everythingWhenEmpty() {
        let filter = ReplyFilter()
        #expect(filter.matches(reply("a", session: "s1")))
        #expect(filter.matches(reply("b", session: nil, source: "opencode")))
        #expect(!filter.isNarrowed)
    }

    @Test func sessionKeepsOnlyItsReplies() {
        let filter = ReplyFilter(session: "s1")
        #expect(filter.matches(reply("a", session: "s1")))
        #expect(!filter.matches(reply("b", session: "s2")))
        #expect(filter.isNarrowed)
    }

    /// The session already says which tool; a tool picked earlier in the menu mustn't hide it.
    @Test func sessionIgnoresTool() {
        let filter = ReplyFilter(session: "s1", tool: .codex)
        #expect(filter.matches(reply("a", session: "s1", source: "claude")))
    }

    @Test func sessionAndSearchTogether() {
        let filter = ReplyFilter(session: "s1", query: "handoff")
        #expect(filter.matches(reply("The handoff is written", session: "s1")))
        #expect(!filter.matches(reply("Tests pass", session: "s1")))
        #expect(!filter.matches(reply("The handoff is written", session: "s2")))
    }

    @Test func searchIsTrimmedAndCaseless() {
        let filter = ReplyFilter(query: "  HANDOFF ")
        #expect(filter.matches(reply("the handoff is written", session: "s1")))
        #expect(ReplyFilter(query: "   ").isNarrowed == false)
    }

    @Test func searchMatchesTheTitleToo() {
        // A reply's title is "Claude Code · readback".
        #expect(ReplyFilter(query: "readback").matches(reply("nothing here", session: "s1")))
    }

    @Test func toolNarrows() {
        let filter = ReplyFilter(tool: .codex)
        #expect(filter.matches(reply("a", session: "s1", source: "codex")))
        #expect(!filter.matches(reply("b", session: "s2", source: "claude")))
    }

    /// OpenCode's replies carry no session id: Home groups them by folder and tool, and the
    /// filter has to use that same key or "See all" would show nothing.
    @Test func sessionlessRepliesMatchTheirHomeKey() {
        let a = reply("a", session: nil, cwd: "/w/one", source: "opencode")
        let other = reply("b", session: nil, cwd: "/w/one", source: "codex")
        let id = SessionSummary.sessions(from: [a, other]).first { $0.newest.id == a.id }!.id
        #expect(id == SessionSummary.key(of: a))
        let filter = ReplyFilter(session: id)
        #expect(filter.matches(a))
        #expect(!filter.matches(other))
    }
}
