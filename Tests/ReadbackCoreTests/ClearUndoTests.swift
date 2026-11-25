import Foundation
import Testing
@testable import ReadbackCore

@Suite struct ClearUndoTests {
    private func reply(_ text: String, _ state: Reply.State, minutesAgo: Double) -> Reply {
        Reply(text: text, source: "claude", cwd: "/x", session: "s", received: Date(timeIntervalSinceNow: -minutesAgo * 60), state: state)
    }

    @Test func clearKeepsWaitingRepliesAndHandsBackTheRest() {
        var history = ReplyHistory()
        history.add(reply("old", .played, minutesAgo: 30))
        history.add(reply("waiting", .waiting, minutesAgo: 20))
        history.add(reply("kept", .kept, minutesAgo: 10))
        let gone = history.clearForUndo()
        #expect(Set(gone.map(\.text)) == ["old", "kept"])
        #expect(history.replies.map(\.text) == ["waiting"])
    }

    @Test func undoPutsEverythingBackInOrder() {
        var history = ReplyHistory()
        for (i, text) in ["a", "b", "c"].enumerated() { history.add(reply(text, .played, minutesAgo: Double(30 - i))) }
        let before = history.replies.map(\.text)
        let gone = history.clearForUndo()
        history.restore(gone)
        #expect(history.replies.map(\.text) == before)
    }

    @Test func aReplyThatArrivedAfterTheClearStaysOnTop() {
        var history = ReplyHistory()
        history.add(reply("old", .played, minutesAgo: 30))
        let gone = history.clearForUndo()
        history.add(reply("new", .played, minutesAgo: 0))
        history.restore(gone)
        #expect(history.replies.map(\.text) == ["new", "old"])
    }

    @Test func undoingTwiceAddsNothingTwice() {
        var history = ReplyHistory()
        history.add(reply("a", .played, minutesAgo: 5))
        let gone = history.clearForUndo()
        history.restore(gone)
        history.restore(gone)
        #expect(history.replies.count == 1)
    }

    @Test func undoStillHoldsTheLimit() {
        var history = ReplyHistory(limit: 3)
        for i in 0..<3 { history.add(reply("old \(i)", .played, minutesAgo: Double(60 - i))) }
        let gone = history.clearForUndo()
        history.add(reply("new 1", .played, minutesAgo: 2))
        history.add(reply("new 2", .played, minutesAgo: 1))
        history.restore(gone)
        #expect(history.replies.count == 3)
        #expect(history.replies.map(\.text) == ["new 2", "new 1", "old 2"])
    }
}
