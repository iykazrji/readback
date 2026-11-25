import XCTest
@testable import ReadbackCore

final class ReplyHistoryTests: XCTestCase {
    private func reply(_ text: String, _ state: Reply.State, minutesAgo: Double = 0) -> Reply {
        Reply(text: text, source: "claude", cwd: "/Users/me/inkine", session: "s1",
              received: Date(timeIntervalSinceNow: -minutesAgo * 60), state: state)
    }

    func testNewestFirstAndWaitingPlaysInArrivalOrder() {
        var history = ReplyHistory()
        let a = reply("first", .waiting), b = reply("second", .waiting), c = reply("third", .kept)
        history.add(a); history.add(b); history.add(c)
        XCTAssertEqual(history.replies.map(\.text), ["third", "second", "first"])
        XCTAssertEqual(history.nextWaiting?.text, "first")
        XCTAssertEqual(history.waitingCount, 2)
        history.mark(a.id, .played)
        XCTAssertEqual(history.nextWaiting?.text, "second")
    }

    func testCapDropsOldestFinishedButNeverWaiting() {
        var history = ReplyHistory(limit: 3)
        history.add(reply("old waiting", .waiting))
        history.add(reply("played 1", .played))
        history.add(reply("played 2", .played))
        history.add(reply("new", .kept))
        XCTAssertEqual(history.replies.map(\.text), ["new", "played 2", "old waiting"])
    }

    func testClearKeepsWhatIsStillWaiting() {
        var history = ReplyHistory()
        history.add(reply("waiting", .waiting))
        history.add(reply("done", .played))
        history.clear()
        XCTAssertEqual(history.replies.map(\.text), ["waiting"])
    }

    func testPreviewIsSpeakableAndShort() {
        let r = reply("## Done\n\nFixed **the bug** in `main.swift`.\n```\ncode\n```", .kept)
        XCTAssertEqual(r.preview, "Done Fixed the bug in main.swift. (code block skipped)")
        XCTAssertTrue(reply(String(repeating: "word ", count: 60), .kept).preview.hasSuffix("…"))
    }

    func testRequestCarriesSessionAndTitle() {
        let r = reply("hi", .waiting)
        XCTAssertEqual(r.request.session, "s1")
        XCTAssertEqual(r.request.autoplay, true)
        XCTAssertEqual(r.title, "Claude Code · inkine")
    }

    func testSavesAndLoads() throws {
        var history = ReplyHistory()
        history.add(reply("kept for later", .kept))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try history.save(to: url)
        let loaded = try XCTUnwrap(ReplyHistory.load(from: url))
        XCTAssertEqual(loaded.replies.map(\.text), ["kept for later"])
        XCTAssertEqual(loaded.replies.first?.id, history.replies.first?.id)
        XCTAssertNil(ReplyHistory.load(from: url.appendingPathExtension("missing")))
    }
}
