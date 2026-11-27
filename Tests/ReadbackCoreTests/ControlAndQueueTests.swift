import XCTest
@testable import ReadbackCore

final class ControlRequestTests: XCTestCase {
    /// The headers the CLI (URLSession, main.swift `send`) and the mod (register.tsx `call`) send.
    private func parse(_ method: String, _ path: String, _ body: String = "",
                       headers: [String: String]? = nil) -> Result<ControlRequest, ControlRequest.Refusal> {
        var sent = ["host": "127.0.0.1:8908"]
        if method == "POST" { sent["content-type"] = "application/json" }
        return ControlRequest.parse(HTTPRequest(method: method, path: path, headers: headers ?? sent, body: Data(body.utf8)))
    }

    /// S01 (the browser part): a web page can't drive Readback. A cross-site form or fetch can't
    /// set application/json without a preflight, which nothing answers; a DNS-rebinding page
    /// arrives with its own Host.
    func testOnlyLocalJSONClientsGetThrough() {
        XCTAssertEqual(status(parse("POST", "/stop", "", headers: ["host": "127.0.0.1:8908", "content-type": "text/plain"])), 415)
        XCTAssertEqual(status(parse("POST", "/stop", "", headers: ["host": "127.0.0.1:8908"])), 415)
        XCTAssertEqual(status(parse("GET", "/health", headers: ["host": "evil.example:8908"])), 403)
        XCTAssertEqual(status(parse("GET", "/health", headers: [:])), 403)
        XCTAssertEqual(try parse("GET", "/health", headers: ["host": "localhost:8908"]).get(), .health)
        XCTAssertEqual(try parse("POST", "/stop", "", headers: ["host": "127.0.0.1:8908", "content-type": "application/json; charset=utf-8"]).get(),
                       .stop(session: nil))
    }

    private func status(_ result: Result<ControlRequest, ControlRequest.Refusal>) -> Int? {
        if case .failure(let refusal) = result { return refusal.status }
        return nil
    }

    func testUnknownPathsAndWrongMethodsAreRefused() {
        XCTAssertEqual(status(parse("GET", "/nope")), 404)
        XCTAssertEqual(status(parse("GET", "/speak")), 405)
        XCTAssertEqual(status(parse("POST", "/health")), 405)
        XCTAssertEqual(try parse("GET", "/health").get(), .health)
    }

    func testStopWithNoBodyStopsEverythingButABrokenBodyIsRefused() {
        XCTAssertEqual(try parse("POST", "/stop").get(), .stop(session: nil))
        XCTAssertEqual(try parse("POST", "/stop", "{}").get(), .stop(session: nil))
        XCTAssertEqual(try parse("POST", "/stop", #"{"session":"a"}"#).get(), .stop(session: "a"))
        XCTAssertEqual(status(parse("POST", "/stop", "{ not json")), 400)
    }

    func testCommandsNeedASessionToSwitchSpeak() {
        XCTAssertEqual(status(parse("POST", "/command", #"{"command":"speak","tool":"codex"}"#)), 400)
        XCTAssertEqual(try parse("POST", "/command", #"{"command":"speak","tool":"codex","session":"c","enabled":true}"#).get(),
                       .command(CommandRequest(command: .speak, tool: .codex, session: "c", enabled: true)))
        XCTAssertEqual(try parse("POST", "/command", #"{"command":"read","tool":"claude","text":"hi"}"#).get(),
                       .command(CommandRequest(command: .read, tool: .claude, session: nil, text: "hi")))
        XCTAssertEqual(status(parse("POST", "/command", #"{"command":"sing","tool":"codex","session":"c"}"#)), 400)
    }

    func testEngineActionsAreCheckedAndNoBodyOnlyReports() {
        XCTAssertEqual(try parse("POST", "/engine").get(), .engine(nil))
        XCTAssertEqual(try parse("POST", "/engine", #"{"action":"install"}"#).get(), .engine(.install))
        XCTAssertEqual(status(parse("POST", "/engine", #"{"action":"reinstall"}"#)), 400)
    }

    func testWhatTheCLISendsIsWhatTheServerReads() throws {
        let sent = SpeakRequest(text: "Done.", source: "codex", cwd: "/x", session: "s")
        let body = String(decoding: try JSONEncoder().encode(sent), as: UTF8.self)
        XCTAssertEqual(try parse("POST", "/speak", body).get(), .speak(sent))
        let auto = String(decoding: try JSONEncoder().encode(AutoRequest(tool: .opencode, enabled: true)), as: UTF8.self)
        XCTAssertEqual(try parse("POST", "/auto", auto).get(), .auto(AutoRequest(tool: .opencode, enabled: true)))
    }

    func testHealthWritesANullSessionForTheMod() throws {
        let health = Health(speaking: false, phase: "idle", session: nil, current: 0, count: 0, speed: 1, waiting: 0,
                            history: 0, auto: [:], engine: "system", runtime: "installed", version: "dev", menuBarIcon: "missing")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(health)) as? [String: Any])
        XCTAssertTrue(json["session"] is NSNull)
        XCTAssertEqual(json["ok"] as? Bool, true)
    }

    func testThePortMovesWithReadbackPort() {
        XCTAssertEqual(ReadbackApp.port(environment: [:]), 8908)
        XCTAssertEqual(ReadbackApp.port(environment: ["READBACK_PORT": "9123"]), 9123)
        XCTAssertEqual(ReadbackApp.port(environment: ["READBACK_PORT": "nope"]), 8908)
    }
}

final class CommandAnswerTests: XCTestCase {
    /// Claude Code's commands are /readback:speak and /readback:read (owner, 2026-11-25); Codex's
    /// stay as Codex sends them.
    func testAnswersNameEachToolsOwnCommands() {
        XCTAssertEqual(CommandAnswer.speak(asked: nil, thread: .asItsTool, everyReply: false, tool: .claude),
                       "Read-aloud is off in this session. /readback:speak on switches it on, /readback:read reads the last reply.")
        XCTAssertTrue(CommandAnswer.speak(asked: nil, thread: .on, everyReply: true, tool: .claude).hasSuffix("/readback:read reads the last reply."))
        XCTAssertEqual(CommandAnswer.speak(asked: nil, thread: .asItsTool, everyReply: false, tool: .codex),
                       "Read-aloud is off in this chat. /speak on switches it on, /read reads the last reply.")
        XCTAssertEqual(Tool.claude.speakCommand, "/readback:speak")
        XCTAssertEqual(Tool.claude.readCommand, "/readback:read")
        XCTAssertEqual(Tool.codex.speakCommand, "/speak")
    }

    func testEachToolHearsItsOwnWordForAConversation() {
        XCTAssertEqual(CommandAnswer.speak(asked: true, thread: .on, everyReply: false, tool: .claude), "Read-aloud is on for this session.")
        XCTAssertEqual(CommandAnswer.speak(asked: false, thread: .muted, everyReply: false, tool: .codex), "Muted this chat. /speak on unmutes it.")
        XCTAssertEqual(CommandAnswer.read(played: false, tool: .codex), "There's no reply in this chat to read yet.")
    }

    /// /speak off mutes a thread even with "read every reply" on (owner, 2026-11-26).
    func testSpeakOffMutesEvenWhenTheToolReadsEveryReply() {
        XCTAssertEqual(CommandAnswer.speak(asked: false, thread: .muted, everyReply: true, tool: .claude),
                       "Muted this session. /readback:speak on unmutes it.")
        XCTAssertTrue(CommandAnswer.speak(asked: nil, thread: .asItsTool, everyReply: true, tool: .claude)
            .hasPrefix("Read-aloud is on here, because Readback reads every Claude Code reply. /readback:speak off mutes just this session."))
        XCTAssertEqual(CommandAnswer.speak(asked: nil, thread: .muted, everyReply: true, tool: .claude),
                       "This session is muted. /readback:speak on unmutes it; /readback:read reads the last reply.")
    }

    /// Turning a thread on while Readback is off says that nothing plays until it's back on.
    func testTurningAThreadOnWhileReadingIsOffSaysSo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 16, minute: 12))!
        let morning = ReadingOff.nextMorning(after: now, calendar: calendar)
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(CommandAnswer.speak(asked: true, thread: .on, everyReply: false, readingOffUntil: morning, tool: .claude,
                                           now: now, calendar: calendar, locale: us),
                       "Read-aloud is on for this session. But reading is off in Readback until 8\u{202F}AM tomorrow. Turn it back on from the menu bar icon.")
        XCTAssertEqual(CommandAnswer.speak(asked: true, thread: .on, everyReply: false, readingOffUntil: .distantFuture, tool: .codex,
                                           now: now, calendar: calendar, locale: us),
                       "Read-aloud is on for this chat. But reading is off in Readback. Turn it back on from the menu bar icon.")
    }
}

final class ReplyQueueTests: XCTestCase {
    private func hook(_ text: String, session: String? = "s1") -> SpeakRequest {
        SpeakRequest(text: text, source: "claude", session: session)
    }

    private func playing(_ step: ReplyQueue.Step) -> (text: String, cue: Bool)? {
        if case .play(let reply, let cue) = step { return (reply.text, cue) }
        return nil
    }

    private func reading(_ reply: Reply?, speaking: Bool = true) -> ReplyQueue.Reading {
        .init(replyID: reply?.id, session: reply?.session, isSpeaking: speaking)
    }

    func testAReplyNobodyAskedForIsOnlyKept() {
        var queue = ReplyQueue()
        XCTAssertEqual(queue.received(hook("hi"), switchedOn: false, reading: nil, cutIn: false), .nothing)
        XCTAssertEqual(queue.history.replies.first?.state, .kept)
    }

    func testRepliesWaitTheirTurnAndPlayInArrivalOrder() {
        var queue = ReplyQueue()
        let first = queue.received(hook("one"), switchedOn: true, reading: nil, cutIn: false)
        XCTAssertEqual(playing(first)?.text, "one")
        XCTAssertEqual(playing(first)?.cue, true, "started by itself, so the cue warns first")
        let now = reading(queue.history.replies.first)
        XCTAssertEqual(queue.received(hook("two"), switchedOn: true, reading: now, cutIn: false), .nothing)
        XCTAssertEqual(queue.received(hook("three"), switchedOn: true, reading: now, cutIn: false), .nothing)

        // "one" finished; before the pause runs out a new reply arrives: the oldest waiting goes first.
        let finished = ReplyQueue.Reading(replyID: now.replyID, session: "s1", isSpeaking: false)
        XCTAssertEqual(playing(queue.received(hook("four"), switchedOn: true, reading: finished, cutIn: false))?.text, "two")
        XCTAssertEqual(playing(queue.playNext(reading: nil))?.text, "three")
        XCTAssertEqual(playing(queue.playNext(reading: nil))?.text, "four")
        XCTAssertEqual(queue.playNext(reading: nil), .nothing)
    }

    func testCuttingInAndAskingOutrightPlayNow() {
        var queue = ReplyQueue()
        _ = queue.received(hook("one"), switchedOn: true, reading: nil, cutIn: false)
        let now = reading(queue.history.replies.first)
        XCTAssertEqual(playing(queue.received(hook("two"), switchedOn: true, reading: now, cutIn: true))?.text, "two")
        let say = SpeakRequest(text: "hello", source: "Readback", autoplay: true)
        let step = queue.received(say, switchedOn: false, reading: now, cutIn: false)
        XCTAssertEqual(playing(step)?.text, "hello")
        XCTAssertEqual(playing(step)?.cue, false, "asked for just now: no warning")
    }

    func testAReplyWithNothingToSayIsSkippedNotStuck() {
        var queue = ReplyQueue()
        _ = queue.received(hook("one"), switchedOn: true, reading: nil, cutIn: false)
        let now = reading(queue.history.replies.first)
        _ = queue.received(hook("   "), switchedOn: true, reading: now, cutIn: false)
        _ = queue.received(hook("three"), switchedOn: true, reading: now, cutIn: false)
        XCTAssertEqual(playing(queue.playNext(reading: nil))?.text, "three")
        XCTAssertEqual(queue.history.waitingCount, 0)
    }

    func testASessionsStopDropsOnlyItsOwnWaitingAndReading() {
        var queue = ReplyQueue()
        _ = queue.received(hook("mine", session: "a"), switchedOn: true, reading: nil, cutIn: false)
        let now = reading(queue.history.replies.first)
        _ = queue.received(hook("mine too", session: "a"), switchedOn: true, reading: now, cutIn: false)
        _ = queue.received(hook("theirs", session: "b"), switchedOn: true, reading: now, cutIn: false)

        XCTAssertEqual(queue.stop(session: "b", reading: now), .nothing, "b's stop leaves a's reading alone")
        XCTAssertEqual(queue.stop(session: "a", reading: now), .stopThenNext)
        XCTAssertEqual(queue.history.waitingCount, 0)
    }

    func testASessionsStopLeavesASampleAlone() {
        var queue = ReplyQueue()
        let sample = ReplyQueue.Reading(replyID: nil, session: nil, isSpeaking: true)
        XCTAssertEqual(queue.stop(session: "a", reading: sample), .nothing)
    }

    func testQuietKeepsWhatWasWaiting() {
        var queue = ReplyQueue()
        _ = queue.received(hook("one"), switchedOn: true, reading: nil, cutIn: false)
        _ = queue.received(hook("two"), switchedOn: true, reading: reading(queue.history.replies.first), cutIn: false)
        XCTAssertEqual(queue.stopAll(), .quiet)
        XCTAssertEqual(queue.history.replies.map(\.state), [.kept, .played])
    }

    func testReadLastFindsTheReplyTheHookAlreadyGaveOrAddsIt() {
        var queue = ReplyQueue()
        XCTAssertEqual(queue.readLast(session: "s1"), .nothing)
        _ = queue.received(hook("The answer."), switchedOn: false, reading: nil, cutIn: false)

        XCTAssertEqual(playing(queue.readLast(session: "s1", asSent: hook("The answer.")))?.cue, false)
        XCTAssertEqual(queue.history.replies.count, 1, "the same entry, not a copy")

        XCTAssertEqual(playing(queue.readLast(session: "s2", asSent: hook("Never reached Readback.", session: "s2")))?.text,
                       "Never reached Readback.")
        XCTAssertEqual(queue.history.replies.count, 2)
        XCTAssertEqual(playing(queue.readLast(session: "s1"))?.text, "The answer.")
    }

    func testWaitingFromLastTimeIsKeptNotQueued() {
        var history = ReplyHistory()
        history.add(Reply(text: "old", source: nil, cwd: nil, session: nil, state: .waiting))
        XCTAssertEqual(ReplyQueue(restoring: history).history.waitingCount, 0)
    }
}

final class ReadingSwitchesTests: XCTestCase {
    func testSessionsAndToolsSwitchReadingOn() throws {
        let suite = "readback-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let switches = ReadingSwitches(defaults: defaults)

        XCTAssertFalse(switches.wantsReading(tool: .codex, thread: "c"))
        switches.setSession("c", true)
        XCTAssertTrue(switches.wantsReading(tool: .codex, thread: "c"))
        XCTAssertFalse(switches.wantsReading(tool: .codex, thread: "other"))
        switches.setSession("c", false)
        switches.setReadsEveryReply(.codex, true)
        XCTAssertTrue(switches.wantsReading(tool: .codex, thread: nil))
        XCTAssertFalse(switches.wantsReading(tool: .claude, thread: nil))
        XCTAssertEqual(defaults.bool(forKey: "autoRead.codex"), true, "the key older versions and the CLI read")
    }
}

final class HookPayloadTests: XCTestCase {
    func testBrokenStdinIsToldApartFromNone() {
        XCTAssertNil(HookPayload.parse(Data("not json".utf8)))
        XCTAssertNotNil(HookPayload.parse(Data()))
    }

    func testTheReplyFallsBackToTheTranscript() throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        try """
        {"type":"assistant","message":{"content":[{"type":"text","text":"From the file."}]}}
        {"type":"user","message":{"content":"thanks"}}
        """.write(to: transcript, atomically: true, encoding: .utf8)
        let payload = HookPayload(json: ["transcript_path": transcript.path, "session_id": "s", "cwd": "/p"])
        XCTAssertEqual(payload.speakRequest(from: .claude), SpeakRequest(text: "From the file.", source: "claude", cwd: "/p", session: "s"))
    }
}

final class IntegrationFixesTests: XCTestCase {
    var home: URL!
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-fixes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testConnectingTwiceKeepsThePersonsOwnBackup() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil)
        let settings = files.paths.claudeSettings
        try "{\n  \"model\": \"opus\"\n}\n".write(to: settings, atomically: true, encoding: .utf8)
        try files.connect(.claude)
        try files.connect(.claude)
        try files.disconnect(.claude)
        XCTAssertEqual(try String(contentsOf: settings.appendingPathExtension("before-readback"), encoding: .utf8),
                       "{\n  \"model\": \"opus\"\n}\n")
    }

    func testABrokenHooksFileStopsCodexBeforeAnythingChanges() throws {
        var ran: [[String]] = []
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil,
                                     codex: { args, _ in ran.append(args) })
        try "{ not json".write(to: files.paths.codexHooks, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try files.connect(.codex))
        XCTAssertTrue(ran.isEmpty)
    }

    func testTheNewestInstalledPluginWinsByVersionNumber() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: { _, _ in })
        let codex = files.paths.codexDir
        try "[plugins.\"readback@readback\"]\nenabled = true\n".write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        func install(_ version: String, cli: String) throws {
            let hooks = CodexPlugin.files(cli: cli).first { $0.path.hasSuffix("hooks/hooks.json") }!.contents
            let url = codex.appendingPathComponent("plugins/cache/readback/readback/\(version)/hooks/hooks.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try hooks.write(to: url, atomically: true, encoding: .utf8)
        }
        try install("0.9.0", cli: "/Old/Readback.app/Contents/Helpers/readback")
        try install("0.10.0", cli: cli)
        XCTAssertEqual(try files.status(.codex), .updateAvailable, "0.10.0 is newer than 0.9.0")
    }

    func testOpenCodeRunsTheSameHookCommandsAsTheOthers() {
        let plugin = Integrations.openCodePlugin(cli: cli)
        XCTAssertTrue(plugin.contains(#"run(["hook", "opencode"]"#))
        XCTAssertTrue(plugin.contains(#"run(["stop"]"#))
    }
}

final class HookOwnershipTests: XCTestCase {
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    /// B07: only the exact lines Readback writes are Readback's.
    func testOnlyTheLinesReadbackWritesAreItsOwn() {
        XCTAssertTrue(Integrations.isOurs(HookCommand.promptSent.line(cli: cli)))
        XCTAssertTrue(Integrations.isOurs(HookCommand.replyFinished(.codex).line(cli: "/Users/me/My 'Apps'/Readback.app/Contents/Helpers/readback")))
        XCTAssertFalse(Integrations.isOurs("'\(cli)' say done && afplay /System/Library/Sounds/Pop.aiff"))
        XCTAssertFalse(Integrations.isOurs("echo '\(cli)' stop >> ~/hooks.log"))
        XCTAssertFalse(Integrations.isOurs("my-logger --after '\(cli)' stop"))
    }

    func testASomeoneElsesHookThatMentionsReadbackSurvivesDisconnect() throws {
        let custom = "'\(cli)' say finished"
        var root = try JSONValue.parse("{}")
        Integrations.addHook(&root, event: "Stop", command: custom, timeout: 5)
        Integrations.connectClaude(&root, cli: cli, pluginDir: "/x/Readback/ClaudeCodePlugin")
        Integrations.disconnectClaude(&root)
        XCTAssertEqual(Integrations.ourCommands(root), [:])
        XCTAssertEqual(root["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"]?.stringValue, custom)
    }
}

final class OwnedFilesTests: XCTestCase {
    var home: URL!
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-owned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/opencode/plugins"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    /// B01: someone else's plugins/readback.js is refused, not replaced.
    func testOpenCodeRefusesAPluginFileItDidntWrite() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil)
        let theirs = "export const Mine = async () => ({})\n"
        try theirs.write(to: files.paths.openCodePlugin, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try files.connect(.opencode)) { XCTAssertTrue("\($0)".contains("readback.js")) }
        XCTAssertEqual(try String(contentsOf: files.paths.openCodePlugin, encoding: .utf8), theirs)
    }

    /// B23: connected means every piece is in place: both hooks and the mod.
    func testClaudeWithAPieceMissingIsIncomplete() throws {
        let bundle = home.appendingPathComponent("bundle/ClaudeCodePlugin/.claude-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "{}".write(to: bundle.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: bundle.deletingLastPathComponent())
        try files.connect(.claude)
        XCTAssertEqual(try files.status(.claude), .connected)

        try FileManager.default.removeItem(at: files.paths.claudePlugin)
        XCTAssertEqual(try files.status(.claude), .incomplete)
        try files.connect(.claude)
        XCTAssertEqual(try files.status(.claude), .connected)

        var root = try JSONValue.parse(String(contentsOf: files.paths.claudeSettings, encoding: .utf8))
        root.set("hooks", .object([("Stop", root["hooks"]!["Stop"]!)]))
        try root.formatted().write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try files.status(.claude), .incomplete, "the stop-on-new-message hook is gone")
    }
}

/// S05: reply text and logs are the person's alone, whatever the folder above allows.
final class PrivateFilesTests: XCTestCase {
    private func mode(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    func testHistoryAndLogsAreOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readback-private-\(UUID().uuidString)/Readback", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let history = dir.appendingPathComponent("history.json")
        try ReplyHistory().save(to: history)
        XCTAssertEqual(try mode(history), 0o600)
        XCTAssertEqual(try mode(dir), 0o700)
        try ReplyHistory().save(to: history)
        XCTAssertEqual(try mode(history), 0o600, "an atomic rewrite keeps it private")

        let log = dir.appendingPathComponent("Logs/cli.log")
        try LogFile.append("one\n", to: log)
        try LogFile.append("two\n", to: log)
        XCTAssertEqual(try mode(log), 0o600)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "one\ntwo\n")
    }
}

/// S03: what the CLI logs about a prompt that almost was /speak or /read carries the command's
/// shape, never the person's words.
final class PromptNearMissTests: XCTestCase {
    func testOnlyTheShapeIsKept() {
        XCTAssertEqual(PromptCommand.nearMiss("/speak please, my API key is sk-123"), "a / word with speak in it (6 characters), then 6 words")
        XCTAssertEqual(PromptCommand.nearMiss("[$speak](/Users/me/.codex/skills/speak/SKILL.md) loudly"), "a [ word with speak in it (48 characters), then 1 word")
        let secret = PromptCommand.nearMiss("/readPrivateToken123") ?? ""
        XCTAssertFalse(secret.contains("Private"), secret)
        XCTAssertNil(PromptCommand.nearMiss("read the docs and fix the reader"))
        XCTAssertNil(PromptCommand.nearMiss("/speak on"), "that one is a command, not a near miss")
    }
}

/// S04: the header block has a ceiling even when its end has arrived.
final class HTTPFramingTests: XCTestCase {
    func testHugeHeadersAreRefusedOnceComplete() {
        let request = "GET /health HTTP/1.1\r\nX-Pad: " + String(repeating: "a", count: 70_000) + "\r\n\r\n"
        XCTAssertEqual(HTTPRequest.parse(Data(request.utf8)), .invalid("headers too large"))
    }
}

/// B08: a hook's stop reaches only its own session; a hook that sent none stops nothing.
final class HookStopTests: XCTestCase {
    func testAHookWithoutASessionStopsNothing() {
        XCTAssertEqual(HookPayload(json: ["session_id": "s"]).stopRequest, StopRequest(session: "s", newTurn: true))
        XCTAssertNil(HookPayload(json: [:]).stopRequest)
        XCTAssertNil(HookPayload(json: ["session_id": ""]).stopRequest)
    }
}

/// B13: a codex command that hangs is ended, so one stuck Connect can't block the rest.
final class CodexTimeoutTests: XCTestCase {
    func testAHungCodexIsEndedWithAClearError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readback-hang-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("codex")
        try "#!/bin/sh\necho starting\nsleep 30\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let started = Date()
        XCTAssertThrowsError(try CodexCLI(path: fake.path).run(["plugin", "add", "x"], codexHome: dir, timeout: 0.5)) { error in
            XCTAssertTrue("\(error)".contains("didn't finish"), "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}

/// B09: /read in Codex finds the chat's last reply in its rollout even when Readback never got it.
/// Record shapes from codex-rs (history/src/rollout_payload.rs, protocol/src/protocol.rs at 3f65e9f1).
final class CodexTranscriptTests: XCTestCase {
    private func payload(_ lines: [String]) throws -> (HookPayload, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID()).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return (HookPayload(json: ["session_id": "t", "prompt": "/read", "transcript_path": url.path, "last_assistant_message": NSNull()]), url)
    }

    func testTheTurnsFinalMessageIsTheReply() throws {
        let (hook, url) = try payload([
            #"{"timestamp":"2026-11-25T00:00:00Z","type":"session_meta","payload":{"id":"t"}}"#,
            #"{"timestamp":"2026-11-25T00:00:01Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Working on it."}]}}"#,
            #"{"timestamp":"2026-11-25T00:00:09Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"All tests pass."}}"#,
            #"{"timestamp":"2026-11-25T00:00:10Z","type":"event_msg","payload":{"type":"user_message","message":"/read"}}"#,
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(hook.replyText(), "All tests pass.")
    }

    func testAnAssistantMessageItemWorksTooWithoutTaskComplete() throws {
        let (hook, url) = try payload([
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hi"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello."}]}}"#,
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(hook.transcriptReply(), "Hello.")
    }
}

/// B03/B18: a reading that fails isn't a reading heard, and the queue goes on after it.
final class FailedReadingTests: XCTestCase {
    func testAFailedReplyGoesBackToTheHistoryAndTheNextOnePlays() {
        var queue = ReplyQueue()
        guard case .play(let first, _) = queue.received(SpeakRequest(text: "one", session: "s"), switchedOn: true, reading: nil, cutIn: false) else {
            return XCTFail("expected the first to play")
        }
        let busy = ReplyQueue.Reading(replyID: first.id, session: "s", isSpeaking: true)
        _ = queue.received(SpeakRequest(text: "two", session: "s"), switchedOn: true, reading: busy, cutIn: false)

        queue.readingFailed(first.id)
        XCTAssertEqual(queue.history.reply(first.id)?.state, .kept, "never heard, so it can be played again")
        guard case .play(let next, _) = queue.playNext(reading: nil) else { return XCTFail("the queue stalled") }
        XCTAssertEqual(next.text, "two")
    }
}

/// B12/B24: a voice is checked against the engine it's for, from the catalog, before anything is saved.
final class VoiceCheckTests: XCTestCase {
    func testVoicesAreCheckedAgainstTheCatalog() {
        XCTAssertNil(VoiceCatalog.problem(voice: "bm_george", for: .kokoro, systemVoiceExists: { _ in false }))
        XCTAssertNotNil(VoiceCatalog.problem(voice: "bm_gorge", for: .kokoro, systemVoiceExists: { _ in false }), "a typo that looks like an id")
        XCTAssertNotNil(VoiceCatalog.problem(voice: "af_heart", for: .melo, systemVoiceExists: { _ in false }), "checked for the engine asked for")
        XCTAssertNil(VoiceCatalog.problem(voice: "EN-BR", for: .melo, systemVoiceExists: { _ in false }))
        XCTAssertNotNil(VoiceCatalog.problem(voice: "x", for: .soprano, systemVoiceExists: { _ in true }))
        XCTAssertNil(VoiceCatalog.problem(voice: "", for: .system, systemVoiceExists: { _ in false }), "the system default")
        XCTAssertNil(VoiceCatalog.problem(voice: "com.apple.voice.Alex", for: .system, systemVoiceExists: { $0 == "com.apple.voice.Alex" }))
    }
}

/// B20: a file Readback has nothing to change in is never rewritten (reformatted).
final class NoOpWriteTests: XCTestCase {
    func testAnUnchangedSettingsFileKeepsItsBytes() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-noop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: "/Applications/Readback.app/Contents/Helpers/readback", bundledPlugin: nil)
        let compact = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try compact.write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        try files.disconnect(.claude)
        XCTAssertEqual(try String(contentsOf: files.paths.claudeSettings, encoding: .utf8), compact)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.paths.claudeSettings.path + ".before-readback"))
    }
}

/// Codex review round 1, #1: an edit to hooks.json made while Codex installs the plugin survives.
final class CodexConcurrentEditTests: XCTestCase {
    func testAHookAddedDuringTheInstallIsKept() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-race-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let cli = "/Applications/Readback.app/Contents/Helpers/readback"
        let hooks = home.appendingPathComponent(".codex/hooks.json")
        var legacy = try JSONValue.parse("{}")
        Integrations.addHook(&legacy, event: "Stop", command: HookCommand.replyFinished(.codex).line(cli: cli), timeout: 10)
        try legacy.formatted().write(to: hooks, atomically: true, encoding: .utf8)

        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: { args, _ in
            guard args.prefix(2) == ["plugin", "add"] else { return }
            var root = try JSONValue.parse(String(contentsOf: hooks, encoding: .utf8))
            Integrations.addHook(&root, event: "Stop", command: "my-own-hook", timeout: 5)
            try root.formatted().write(to: hooks, atomically: true, encoding: .utf8)
        })
        try files.connect(.codex)
        let after = try String(contentsOf: hooks, encoding: .utf8)
        XCTAssertTrue(after.contains("my-own-hook"), after)
        XCTAssertFalse(after.contains("hook codex"), "the legacy hook still goes")
    }
}

/// Codex review round 1, #8: Claude's settings are touched only where Readback's own entries are.
final class ClaudeOwnershipTests: XCTestCase {
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"
    var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-claude-own-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testSomeoneElsesEmptyPluginDirsSurvivesDisconnect() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil)
        let theirs = "{\n  \"env\": {\n    \"CLAUDE_CODE_PLUGIN_DIRS\": \"\"\n  }\n}\n"
        try theirs.write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        try files.disconnect(.claude)
        XCTAssertEqual(try String(contentsOf: files.paths.claudeSettings, encoding: .utf8), theirs)
    }

    func testAFileWithOnlyTheModStillListedIsntTakenAsTheOriginal() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil)
        let original = "{\n  \"model\": \"opus\"\n}\n"
        try original.write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        try files.connect(.claude)
        var root = try JSONValue.parse(String(contentsOf: files.paths.claudeSettings, encoding: .utf8))
        root.remove("hooks")   // the hooks removed by hand; the mod stays listed
        try root.formatted().write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        try files.connect(.claude)
        XCTAssertEqual(try String(contentsOf: files.paths.claudeSettings.appendingPathExtension("before-readback"), encoding: .utf8), original)
    }
}

/// Codex review round 1, #7: a partial install shows as incomplete (with Disconnect), never as
/// connected or as nothing.
final class PartialInstallTests: XCTestCase {
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"
    var home: URL!
    var bundle: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        bundle = home.appendingPathComponent("bundle/ClaudeCodePlugin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try "{}".write(to: bundle.appendingPathComponent("hooks/hooks.json"), atomically: true, encoding: .utf8)
        try "export {}".write(to: bundle.appendingPathComponent("hooks/register.tsx"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testAMissingModFileIsIncomplete() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: bundle)
        try files.connect(.claude)
        XCTAssertEqual(try files.status(.claude), .connected)
        try FileManager.default.removeItem(at: files.paths.claudePlugin.appendingPathComponent("hooks/register.tsx"))
        XCTAssertEqual(try files.status(.claude), .incomplete)
    }

    func testOnlyTheModListedIsIncompleteNotDisconnected() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: bundle)
        try files.connect(.claude)
        var root = try JSONValue.parse(String(contentsOf: files.paths.claudeSettings, encoding: .utf8))
        root.remove("hooks")
        try root.formatted().write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
        XCTAssertEqual(try files.status(.claude), .incomplete)
    }

    func testAnEnabledCodexPluginWithNoInstalledCopyIsIncomplete() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: { _, _ in })
        try "[plugins.\"readback@readback\"]\nenabled = true\n".write(to: files.paths.codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try files.status(.codex), .incomplete)
    }
}

/// Codex review round 1, #5: a codex wrapper that exits while a child still holds its output
/// open doesn't hold Connect up.
final class CodexWrapperTests: XCTestCase {
    func testAChildHoldingThePipeDoesntBlock() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readback-wrap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("codex")
        try "#!/bin/sh\nsleep 5 &\necho codex-cli 0.200.0\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let started = Date()
        XCTAssertEqual(try CodexCLI(path: fake.path).version(), "codex-cli 0.200.0")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}

/// Codex review round 1, #10: /read can run before its Stop hook arrives; the late hook is the same
/// reply, not a second one to read.
final class ReadBeforeHookTests: XCTestCase {
    func testTheLateHookJoinsTheReplyReadAlready() {
        var queue = ReplyQueue()
        let asSent = SpeakRequest(text: "Done.", source: "codex", session: "c")
        guard case .play = queue.readLast(session: "c", asSent: asSent) else { return XCTFail("expected /read to play") }
        XCTAssertEqual(queue.received(SpeakRequest(text: "Done.", source: "codex", session: "c"), switchedOn: true, reading: nil, cutIn: false), .nothing)
        XCTAssertEqual(queue.history.replies.count, 1)

        // A later reply that says the same thing is a new one.
        guard case .play = queue.received(SpeakRequest(text: "Done.", source: "codex", session: "c"), switchedOn: true, reading: nil, cutIn: false) else {
            return XCTFail("a new reply plays")
        }
        XCTAssertEqual(queue.history.replies.count, 2)
    }
}

/// Codex review round 1, #14: `CODEX_HOME=<orca> readback disconnect codex` leaves ~/.codex's
/// shared plugin working.
final class OrcaFromTheCLITests: XCTestCase {
    func testDisconnectingOrcaThroughCodexHomeRepairsTheUsualHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-orca-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let usual = home.appendingPathComponent(".codex", isDirectory: true)
        let orca = ReadbackPaths(home: home).orcaCodexDir
        for dir in [usual, orca] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let enabled = "[plugins.\"readback@readback\"]\nenabled = true\n"
        for dir in [usual, orca] { try enabled.write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8) }
        var reinstalledIn: [String] = []
        let files = IntegrationFiles(paths: ReadbackPaths(home: home, environment: ["CODEX_HOME": orca.path]),
                                     cli: "/Applications/Readback.app/Contents/Helpers/readback", bundledPlugin: nil,
                                     codex: { args, codexHome in if args.prefix(2) == ["plugin", "add"] { reinstalledIn.append(codexHome.standardizedFileURL.path) } })
        try files.disconnect(.codex)   // the CLI's .codex is Orca here
        XCTAssertEqual(reinstalledIn, [usual.standardizedFileURL.path])
    }
}

/// Codex review round 1, #15.
final class ProtocolNitTests: XCTestCase {
    func testOnlyTheJSONMediaTypeCounts() {
        let request = HTTPRequest(method: "POST", path: "/stop", headers: ["host": "127.0.0.1:8908", "content-type": "application/json-example"], body: Data())
        guard case .failure(let refusal) = ControlRequest.parse(request, port: 8908) else { return XCTFail("accepted") }
        XCTAssertEqual(refusal.status, 415)
    }

    func testBareSpeakSaysWhyItsOnWhenEveryReplyIs() {
        let answer = CommandAnswer.speak(asked: nil, thread: .asItsTool, everyReply: true, tool: .codex)
        XCTAssertFalse(answer.contains("/speak off changes it"), answer)
        XCTAssertTrue(answer.contains("every Codex reply"), answer)
    }
}

/// Codex review round 2.
final class RoundTwoQueueTests: XCTestCase {
    /// A /read entry only waits a little while for its hook: a later turn saying the same thing
    /// is a new reply.
    func testAnOldReadEntryDoesntSwallowALaterReply() {
        var queue = ReplyQueue()
        let then = Date(timeIntervalSince1970: 1_000_000)
        _ = queue.readLast(session: "c", asSent: SpeakRequest(text: "Done.", source: "codex", session: "c"), now: then)
        let later = queue.received(SpeakRequest(text: "Done.", source: "codex", session: "c"), switchedOn: true, reading: nil,
                                   cutIn: false, now: then.addingTimeInterval(120))
        guard case .play = later else { return XCTFail("the later reply was swallowed") }
        XCTAssertEqual(queue.history.replies.count, 2)
    }

    /// /read reuses only the session's newest reply; an older one with the same words is another turn.
    func testReadOnlyReusesTheNewestReply() {
        var queue = ReplyQueue()
        _ = queue.received(SpeakRequest(text: "Done.", session: "c"), switchedOn: false, reading: nil, cutIn: false)
        _ = queue.received(SpeakRequest(text: "Something else.", session: "c"), switchedOn: false, reading: nil, cutIn: false)
        _ = queue.readLast(session: "c", asSent: SpeakRequest(text: "Done.", session: "c"))
        XCTAssertEqual(queue.history.replies.count, 3, "a new entry for the tool's newest reply")
        XCTAssertEqual(queue.received(SpeakRequest(text: "Done.", session: "c"), switchedOn: true, reading: nil, cutIn: false), .nothing,
                       "and that turn's late hook joins it")
    }

    func testAnAskedReadingIsNeverTakenForTheLateHook() {
        var queue = ReplyQueue()
        _ = queue.readLast(session: nil, asSent: SpeakRequest(text: "hello", session: nil))
        guard case .play = queue.received(SpeakRequest(text: "hello", source: "Readback", autoplay: true), switchedOn: false, reading: nil, cutIn: false) else {
            return XCTFail("`readback say` should read")
        }
    }
}

final class RoundTwoTranscriptTests: XCTestCase {
    /// An interrupted turn's progress message isn't the last reply; the last finished turn's is.
    func testAnInterruptedTurnDoesntReplaceTheFinishedReply() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try [
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Done."}]}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Done."}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Checking…"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Still checking…"}]}}"#,
        ].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(HookPayload(json: ["transcript_path": url.path]).transcriptReply(), "Done.")
    }
}

final class RoundTwoMarkdownTests: XCTestCase {
    func testATabIndentIsNotAFence() {
        XCTAssertTrue(SpeechText.clean("Useful summary:\n\t~~~\nFinal result: passed").contains("Final result: passed"))
    }

    func testAnEscapedPipeIsntAColumn() {
        let spoken = SpeechText.clean(#"A \| B"# + "\n--- | ---\nmore text")
        XCTAssertFalse(spoken.contains("table skipped"), spoken)
        XCTAssertTrue(spoken.contains("more text"), spoken)
    }
}

final class RoundTwoCodexStatusTests: XCTestCase {
    func testAnEnabledPluginWithEmptyCachedHooksIsIncomplete() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-empty-hooks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        let cached = codex.appendingPathComponent("plugins/cache/readback/readback/\(CodexPlugin.version)/hooks/hooks.json")
        try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: cached, atomically: true, encoding: .utf8)
        try "[plugins.\"readback@readback\"]\nenabled = true\n".write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: "/Applications/Readback.app/Contents/Helpers/readback", bundledPlugin: nil, codex: { _, _ in })
        XCTAssertEqual(try files.status(.codex), .incomplete)
    }
}

/// Codex review round 2, #5: everything codex wrote before it exited is read, however much.
final class CodexDrainTests: XCTestCase {
    func testOutputWrittenRightBeforeExitIsKept() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readback-drain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("codex")
        try "#!/bin/sh\nhead -c 300000 /dev/zero | tr '\\\\0' 'a'\necho\necho codex-cli 0.200.0\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        for _ in 0..<5 {
            XCTAssertTrue(try CodexCLI(path: fake.path).version().hasSuffix("codex-cli 0.200.0"))
        }
    }
}

/// Codex review round 3.
final class RoundThreeTests: XCTestCase {
    /// A new prompt in the session is a new turn: the next Stop hook is that turn's reply.
    func testANewPromptEndsTheWaitForTheOldHook() {
        var queue = ReplyQueue()
        _ = queue.readLast(session: "s", asSent: SpeakRequest(text: "Done.", source: "claude", session: "s"))
        _ = queue.stop(session: "s", reading: nil, newTurn: true)   // the next prompt's hook
        guard case .play = queue.received(SpeakRequest(text: "Done.", source: "claude", session: "s"), switchedOn: true, reading: nil, cutIn: false) else {
            return XCTFail("the new turn's reply was swallowed")
        }
    }

    /// /read reusing the last stored "Done." still waits for this turn's late hook, so it isn't read twice.
    func testReusingAnEarlierEntryAlsoWaitsForTheLateHook() {
        var queue = ReplyQueue()
        _ = queue.received(SpeakRequest(text: "Done.", session: "s"), switchedOn: false, reading: nil, cutIn: false)
        _ = queue.readLast(session: "s", asSent: SpeakRequest(text: "Done.", session: "s"))
        XCTAssertEqual(queue.received(SpeakRequest(text: "Done.", session: "s"), switchedOn: true, reading: nil, cutIn: false), .nothing)
    }

    /// Text Codex marks as commentary isn't a reply; /read only sends finished replies.
    func testCommentaryIsNeverTheLastReply() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"Checking…"}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let hook = HookPayload(json: ["transcript_path": url.path])
        XCTAssertNil(hook.transcriptReply())
        XCTAssertNil(hook.finishedTranscriptReply())
    }

    func testFinishedOnlySkipsUnmarkedText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Half."}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let hook = HookPayload(json: ["transcript_path": url.path])
        XCTAssertEqual(hook.transcriptReply(), "Half.")
        XCTAssertNil(hook.finishedTranscriptReply())
    }

    /// `readback stop` with nothing on stdin (a person, a script, a Shortcut) stops everything;
    /// with a hook's JSON it's that session's only, and nothing without one.
    func testStopFromAPersonOrAHook() {
        XCTAssertEqual(StopRequest.fromCLI(stdin: Data()), StopRequest(session: nil))
        XCTAssertEqual(StopRequest.fromCLI(stdin: Data(#"{"session_id":"s"}"#.utf8)), StopRequest(session: "s", newTurn: true))
        XCTAssertNil(StopRequest.fromCLI(stdin: Data(#"{"prompt":"hi"}"#.utf8)))
    }
}

/// Codex review round 4: only a new turn ends /read's wait for its hook.
final class RoundFourTests: XCTestCase {
    func testAStopButtonIsntANewTurn() {
        var queue = ReplyQueue()
        _ = queue.readLast(session: "s", asSent: SpeakRequest(text: "Done.", source: "claude", session: "s"))
        _ = queue.stop(session: "s", reading: nil)                    // the mod's Stop button
        XCTAssertEqual(queue.received(SpeakRequest(text: "Done.", source: "claude", session: "s"), switchedOn: true, reading: nil, cutIn: false), .nothing,
                       "the late hook is still this turn's")
    }

    func testARestartEndsTheWait() {
        var queue = ReplyQueue()
        _ = queue.readLast(session: "s", asSent: SpeakRequest(text: "Done.", source: "claude", session: "s"))
        var restarted = ReplyQueue(restoring: queue.history)
        guard case .play = restarted.received(SpeakRequest(text: "Done.", source: "claude", session: "s"), switchedOn: true, reading: nil, cutIn: false) else {
            return XCTFail("a reply after a restart was swallowed")
        }
    }

    func testOnlyAHooksStopIsANewTurn() throws {
        XCTAssertEqual(HookPayload(json: ["session_id": "s"]).stopRequest?.newTurn, true)
        let parsed = ControlRequest.parse(HTTPRequest(method: "POST", path: "/stop",
                                                      headers: ["host": "127.0.0.1:8908", "content-type": "application/json"],
                                                      body: Data(#"{"session":"s","newTurn":true}"#.utf8)), port: 8908)
        XCTAssertEqual(try parsed.get(), .stop(session: "s", newTurn: true))
    }
}
