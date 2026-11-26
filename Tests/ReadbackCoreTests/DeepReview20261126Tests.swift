import Foundation
import XCTest
@testable import ReadbackCore

/// Deep review of 2026-11-26, PR #1. The ledger is docs/reviews/2026-11-26-review-ledger.md.
final class DeepReviewQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    /// P1-2: two turns that both say "Done." are two replies, even when /read runs between the
    /// second turn's prompt and its Stop hook. The app sends the prompt hook's stop as
    /// `StopRequest(session:newTurn: true)` (HookPayload.stopRequest), and the Stop hook's reply as
    /// `SpeakRequest(text:source:cwd:session:)` (HookPayload.speakRequest).
    func testTwoTurnsSayingTheSameThingAreTwoReplies() {
        var queue = ReplyQueue()
        let done = SpeakRequest(text: "Done.", source: "claude", session: "s")
        _ = queue.received(done, switchedOn: false, reading: nil, cutIn: false, now: t0)
        _ = queue.stop(session: "s", reading: nil, newTurn: true, now: t0 + 5)          // the next prompt
        _ = queue.readLast(session: "s", asSent: done, now: t0 + 20)                    // /read before its Stop
        _ = queue.received(done, switchedOn: false, reading: nil, cutIn: false, now: t0 + 21)   // that Stop
        XCTAssertEqual(queue.history.replies.count, 2, "the second turn has its own row")
        XCTAssertEqual(queue.history.replies.map(\.received), [t0 + 20, t0], "and its own time")
    }

    /// The same turn's /read still reuses the row its Stop hook already added.
    func testReadInTheSameTurnStillReusesTheRow() {
        var queue = ReplyQueue()
        let done = SpeakRequest(text: "Done.", source: "claude", session: "s")
        _ = queue.stop(session: "s", reading: nil, newTurn: true, now: t0)
        _ = queue.received(done, switchedOn: false, reading: nil, cutIn: false, now: t0 + 10)
        _ = queue.readLast(session: "s", asSent: done, now: t0 + 12)
        XCTAssertEqual(queue.history.replies.count, 1)
    }

    /// Another session's new turn doesn't make this session's reply an old one.
    func testATurnElsewhereDoesntCount() {
        var queue = ReplyQueue()
        let done = SpeakRequest(text: "Done.", source: "claude", session: "s")
        _ = queue.received(done, switchedOn: false, reading: nil, cutIn: false, now: t0)
        _ = queue.stop(session: "other", reading: nil, newTurn: true, now: t0 + 5)
        _ = queue.readLast(session: "s", asSent: done, now: t0 + 6)
        XCTAssertEqual(queue.history.replies.count, 1)
    }

    /// P1-6: with more replies waiting than the history holds, the one being read stays in the
    /// history until it has an outcome, so a failure can keep it to play again.
    func testTheReplyBeingReadIsntTrimmedBeforeItSpeaks() {
        var queue = ReplyQueue(restoring: ReplyHistory(limit: 2))
        for (i, text) in ["First.", "Second.", "Third."].enumerated() {
            _ = queue.received(SpeakRequest(text: text, session: "s"), switchedOn: true,
                               reading: .init(replyID: UUID(), session: "x", isSpeaking: true), cutIn: false, now: t0 + Double(i))
        }
        guard case .play(let first, _) = queue.playNext(reading: nil) else { return XCTFail("expected the oldest to play") }
        XCTAssertEqual(first.text, "First.")
        XCTAssertNotNil(queue.history.reply(first.id), "still in the history while it's read")
        queue.readingFailed(first.id)
        XCTAssertEqual(queue.history.reply(first.id)?.state, .kept, "kept, to be played again")
    }
}

final class DeepReviewPrivateFilesTests: XCTestCase {
    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rb-private-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mode(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    /// P1-8: making a folder private takes away what others could do and never gives the owner
    /// back a permission they took away. ReplyHistory.save writes through PrivateFiles.write.
    func testAReadOnlyFolderStaysReadOnly() throws {
        let dir = try temp()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path); try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try ReplyHistory().save(to: dir.appendingPathComponent("history.json")), "the person made it read-only")
        XCTAssertEqual(try mode(dir), 0o500)
    }

    func testAnOpenFolderIsNarrowed() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try ReplyHistory().save(to: dir.appendingPathComponent("history.json"))
        XCTAssertEqual(try mode(dir), 0o700)
    }

    /// The same rule for an older log file: narrowed, never made writable again.
    func testAReadOnlyLogStaysReadOnly() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("cli.log")
        try "old\n".write(to: log, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: log.path)
        XCTAssertThrowsError(try LogFile.append("new\n", to: log))
        XCTAssertEqual(try mode(log), 0o400)
    }
}
