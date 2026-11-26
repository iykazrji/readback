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

/// P1-7: a 0.4 helper still running against this app (a hook that started before the update,
/// a second copy on the same port) gets its /read answered. 0.4's Codex prompt hook sent
/// POST /replay with `{"session": "<id>"}` and JSON headers (0.4 main.swift:62–69, 285).
final class DeepReviewCompatibilityTests: XCTestCase {
    private func post(_ path: String, _ body: String) -> Result<ControlRequest, ControlRequest.Refusal> {
        ControlRequest.parse(HTTPRequest(method: "POST", path: path, headers: ["host": "127.0.0.1:8908", "content-type": "application/json"],
                                         body: Data(body.utf8)), port: 8908)
    }

    func testThe04ReplayRouteStillReadsTheLastReply() {
        XCTAssertEqual(try post("/replay", #"{"session":"c"}"#).get(), .replay(session: "c"))
        guard case .failure(let refusal) = post("/replay", "{}") else { return XCTFail("a replay names its session") }
        XCTAssertEqual(refusal.status, 400)
    }
}

/// Fix review, round 1 (R1-1): in 0.5 Claude Code's commands are files, /readback:read and
/// /readback:speak. If its UserPromptSubmit hook fires for one, that prompt isn't a new turn, and
/// it stops nothing: otherwise /readback:read would make the reply it's about to read look like an
/// earlier turn's (a second History row) or stop the reading it starts. The hook's stdin is
/// Claude Code's UserPromptSubmit payload: session_id and prompt (HookPayload.stopRequest).
final class DeepReviewOwnCommandTests: XCTestCase {
    func testReadbacksOwnCommandIsntANewTurn() {
        for prompt in ["/readback:read", "/readback:speak on", "/readback:speak"] {
            XCTAssertNil(HookPayload(json: ["session_id": "s", "prompt": prompt]).stopRequest, prompt)
        }
        XCTAssertEqual(HookPayload(json: ["session_id": "s", "prompt": "fix the failing test"]).stopRequest,
                       StopRequest(session: "s", newTurn: true))
        XCTAssertEqual(HookPayload(json: ["session_id": "s", "prompt": "/read the docs first"]).stopRequest,
                       StopRequest(session: "s", newTurn: true), "an ordinary prompt that starts like one")
    }
}

/// P2-1: "the engine is installed" has one meaning, its receipt and its server both there. A retry
/// after the voice step failed resumes at the voice step (Runtime.install), so it never clears an
/// environment that works; VoiceServer and Runtime ask the same question.
final class DeepReviewEngineInstalledTests: XCTestCase {
    func testInstalledMeansTheReceiptAndTheServer() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rb-engine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ReadbackPaths(home: home)
        let fm = FileManager.default
        XCTAssertFalse(paths.engineIsInstalled)
        try fm.createDirectory(at: paths.voiceServer.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: paths.voiceServer.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertFalse(paths.engineIsInstalled, "a server without its receipt is an install cut short")
        try Data("{}".utf8).write(to: paths.runtimeReceipt)
        XCTAssertTrue(paths.engineIsInstalled)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.voiceServer.path)
        XCTAssertFalse(paths.engineIsInstalled, "a server that can't run")
    }

    /// The step a retry starts at: past the engine once it's installed, so `uv venv --clear` only
    /// ever runs over an environment that was never finished.
    func testARetryAfterTheVoiceStepStartsThere() {
        XCTAssertEqual(EngineInstall.firstStep(engineInstalled: true), .voice)
        XCTAssertEqual(EngineInstall.firstStep(engineInstalled: false), .python)
    }
}

/// P2-2: the copied mod in Application Support is shared by every Claude Code login connected to
/// Readback. One connected only through CLAUDE_CONFIG_DIR (a work login, AGENT-SETUP.md) gets the
/// new mod at launch too, though the app only sees ~/.claude, which isn't connected.
final class DeepReviewSharedModTests: XCTestCase {
    func testLaunchRefreshesTheCopyWhenOnlyASecondLoginIsConnected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rb-mod-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        // This version's mod, as the bundle carries it: the 0.3.0 manifest and the command files.
        let bundled = home.appendingPathComponent("Bundle/ClaudeCodePlugin", isDirectory: true)
        try fm.createDirectory(at: bundled.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: bundled.appendingPathComponent("commands"), withIntermediateDirectories: true)
        try #"{"name":"readback","version":"0.3.0"}"#.write(to: bundled.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        try "---\ndescription: Read the last reply aloud now with Readback\n---\n".write(to: bundled.appendingPathComponent("commands/read.md"), atomically: true, encoding: .utf8)
        // The 0.4 copy, left by connecting the second login: no command files.
        let paths = ReadbackPaths(home: home)
        try fm.createDirectory(at: paths.claudePlugin.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try #"{"name":"readback","version":"0.2.0"}"#.write(to: paths.claudePlugin.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true, encoding: .utf8)

        let files = IntegrationFiles(paths: paths, cli: "/Applications/Readback.app/Contents/Helpers/readback", bundledPlugin: bundled, codex: { _, _ in })
        XCTAssertEqual(try files.status(.claude), .notConnected, "~/.claude itself isn't connected")
        try files.refreshPlugin()
        XCTAssertTrue(fm.fileExists(atPath: paths.claudePlugin.appendingPathComponent("commands/read.md").path))
        XCTAssertEqual(try String(contentsOf: paths.claudePlugin.appendingPathComponent(".claude-plugin/plugin.json"), encoding: .utf8),
                       #"{"name":"readback","version":"0.3.0"}"#)
    }

    /// Never connected anywhere: no copy, and launch doesn't make one.
    func testNoCopyIsMadeWhenNothingWasConnected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rb-mod-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let bundled = home.appendingPathComponent("Bundle/ClaudeCodePlugin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try "x".write(to: bundled.appendingPathComponent("a"), atomically: true, encoding: .utf8)
        let paths = ReadbackPaths(home: home)
        try IntegrationFiles(paths: paths, cli: "/x/readback", bundledPlugin: bundled, codex: { _, _ in }).refreshPlugin()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.claudePlugin.path))
    }
}

/// P2-3: switching "Lower other sounds while reading" off lets the tap go now, not after the
/// 60-second linger that's only for a run of replies, including when a reading already ended and
/// the tap is lingering. AppDelegate passes the switch as `prefs.lowerOtherAudio` on every phase.
final class DeepReviewDuckingTests: XCTestCase {
    func testSwitchingOffMidReadingLetsTheTapGo() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.playing, switchedOn: true)
        XCTAssertEqual(ducking.readingChanged(.playing, switchedOn: false), .release)
        XCTAssertEqual(ducking.readingChanged(.stopped, switchedOn: false), .nothing, "once")
    }

    func testSwitchingOffWhileTheTapLingersLetsItGo() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.playing, switchedOn: true)
        _ = ducking.readingChanged(.stopped, switchedOn: true)
        XCTAssertEqual(ducking.restoreDue(.stopped), .restore, "back up; the tap lingers")
        XCTAssertEqual(ducking.readingChanged(.stopped, switchedOn: false), .release)
    }

    func testOffAllAlongDoesNothing() {
        var ducking = OtherAudioDucking()
        XCTAssertEqual(ducking.readingChanged(.playing, switchedOn: false), .nothing)
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
