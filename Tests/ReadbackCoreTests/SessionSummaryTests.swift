import Foundation
import Testing
@testable import ReadbackCore

/// Home's Sessions list: recent replies grouped by the session they came from.
@Suite struct SessionSummaryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func reply(_ text: String, session: String?, cwd: String? = "/Users/x/code/readback",
                       source: String? = "claude", at minutes: Double) -> Reply {
        Reply(text: text, source: source, cwd: cwd, session: session, received: t0.addingTimeInterval(minutes * 60), state: .played)
    }

    @Test func groupsBySession() {
        let replies = [reply("a", session: "s1", at: 0), reply("b", session: "s2", at: 1), reply("c", session: "s1", at: 2)]
        let sessions = SessionSummary.sessions(from: replies)
        #expect(sessions.map(\.id) == ["s1", "s2"])
        #expect(sessions.first?.count == 2)
    }

    @Test func newestSessionFirst() {
        let replies = [reply("old", session: "s1", at: 0), reply("new", session: "s2", at: 5), reply("mid", session: "s3", at: 3)]
        #expect(SessionSummary.sessions(from: replies).map(\.id) == ["s2", "s3", "s1"])
    }

    @Test func newestIsTheSessionsLatestReply() {
        let replies = [reply("first", session: "s1", at: 0), reply("latest", session: "s1", at: 9), reply("middle", session: "s1", at: 4)]
        #expect(SessionSummary.sessions(from: replies).first?.newest.text == "latest")
    }

    @Test func repliesWithoutASessionGroupByFolderAndTool() {
        let replies = [
            reply("a", session: nil, cwd: "/w/one", source: "opencode", at: 0),
            reply("b", session: nil, cwd: "/w/one", source: "opencode", at: 1),
            reply("c", session: nil, cwd: "/w/one", source: "codex", at: 2),
        ]
        let sessions = SessionSummary.sessions(from: replies)
        #expect(sessions.count == 2)
        #expect(Set(sessions.map(\.id)) == ["cwd:/w/one|opencode", "cwd:/w/one|codex"])
    }

    @Test func projectIsTheFolderName() {
        let s = SessionSummary.sessions(from: [reply("a", session: "s", cwd: "/Users/x/code/enterprise-dashboard/", at: 0)])
        #expect(s.first?.project == "enterprise-dashboard")
        let noFolder = SessionSummary.sessions(from: [reply("a", session: "s", cwd: nil, source: "codex", at: 0)])
        #expect(noFolder.first?.project == "Codex")
        #expect(noFolder.first?.tool == .codex)
    }

    @Test func limitCaps() {
        let replies = (0..<12).map { reply("r\($0)", session: "s\($0)", at: Double($0)) }
        #expect(SessionSummary.sessions(from: replies, limit: 8).count == 8)
        #expect(SessionSummary.sessions(from: replies, limit: 8).first?.id == "s11")
    }

    /// History saves times to the second, so two sessions' newest replies can tie. Their order
    /// must never depend on input order: Home redraws many times a second while a reply plays,
    /// and a tie that flipped made two rows swap back and forth (found 2026-11-25).
    @Test func tiedSessionsKeepOneOrder() {
        let a = reply("a", session: "alpha", at: 5), b = reply("b", session: "beta", at: 5), c = reply("c", session: "gamma", at: 5)
        let one = SessionSummary.sessions(from: [a, b, c]).map(\.id)
        let two = SessionSummary.sessions(from: [c, b, a]).map(\.id)
        let three = SessionSummary.sessions(from: [b, c, a]).map(\.id)
        #expect(one == two && two == three)
        #expect(one == ["alpha", "beta", "gamma"])
    }

    @Test func repliesComeNewestFirstInsideASession() {
        let replies = [reply("one", session: "s", at: 0), reply("three", session: "s", at: 2), reply("two", session: "s", at: 1)]
        #expect(SessionSummary.sessions(from: replies).first?.replies.map(\.text) == ["three", "two", "one"])
    }
}
