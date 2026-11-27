import Foundation
import Testing
@testable import ReadbackCore

/// A user asked to quiet single threads and to switch all reading off for a while (owner, 2026-11-26).
@Suite struct ReadingOffAndMuteTests {
    private func withSwitches(_ body: (ReadingSwitches) -> Void) {
        let suite = "readback-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(ReadingSwitches(defaults: defaults))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 26) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Threads

    @Test func aMuteBeatsTheToolsEveryReply() {
        withSwitches { switches in
            switches.setReadsEveryReply(.claude, true)
            switches.setSession("noisy", false)
            #expect(!switches.wantsReading(tool: .claude, thread: "noisy"))
            #expect(switches.wantsReading(tool: .claude, thread: "other"))
        }
    }

    @Test func speakOnLiftsAMuteAndReadsEvenWithoutEveryReply() {
        withSwitches { switches in
            switches.setSession("t", false)
            switches.setSession("t", true)
            #expect(!switches.isMuted("t"))
            #expect(switches.wantsReading(tool: .codex, thread: "t"))
        }
    }

    @Test func unmutingInTheAppHandsTheThreadBackToItsTool() {
        withSwitches { switches in
            switches.setMuted("t", true)
            switches.setMuted("t", false)
            #expect(!switches.isMuted("t"))
            #expect(!switches.isSessionOn("t"))
            #expect(!switches.wantsReading(tool: .codex, thread: "t"))
            switches.setReadsEveryReply(.codex, true)
            #expect(switches.wantsReading(tool: .codex, thread: "t"))
        }
    }

    /// The player's Unmute is an undo: a thread that was on with /speak on reads again
    /// (review round 1, 2026-11-26: muting used to drop the /speak on, so Unmute left it quiet).
    @Test func unmutingInTheAppPutsBackASpeakOn() {
        withSwitches { switches in
            switches.setSession("t", true)
            switches.setMuted("t", true)
            #expect(!switches.wantsReading(tool: .codex, thread: "t"))
            switches.setMuted("t", false)
            #expect(switches.wantsReading(tool: .codex, thread: "t"))
        }
    }

    /// `readback session <id>` says on only while the thread reads by /speak on: a mute beats it,
    /// even though the /speak on is kept for the unmute (review round 2, 2026-11-26).
    @Test func aMutedThreadIsntReportedOn() {
        withSwitches { switches in
            switches.setSession("t", true)
            #expect(switches.isSessionOnAndUnmuted("t"))
            switches.setMuted("t", true)
            #expect(switches.isSessionOn("t"))
            #expect(!switches.isSessionOnAndUnmuted("t"))
            switches.setMuted("t", false)
            #expect(switches.isSessionOnAndUnmuted("t"))
        }
    }

    /// OpenCode's plugin sends its session id and folder, so each OpenCode chat is its own thread,
    /// the same row Home shows; a mute holds for that chat and not its neighbour in the folder.
    @Test func anOpenCodeChatFromTheRealHookIsItsOwnThread() throws {
        func reply(_ id: String) throws -> SpeakRequest {
            let json = #"{"last_assistant_message":"Done.","session_id":"\#(id)","cwd":"/Users/me/app"}"#
            return try #require(HookPayload.parse(Data(json.utf8))?.speakRequest(from: .opencode))
        }
        let first = try reply("ses_a"), second = try reply("ses_b")
        let firstKey = SessionSummary.key(session: first.session, cwd: first.cwd, source: first.source)
        let row = SessionSummary.sessions(from: [Reply(first, state: .kept)]).first?.id
        #expect(firstKey == "ses_a")
        #expect(row == firstKey)
        #expect(SessionSummary.project(cwd: first.cwd, source: first.source) == "app")
        #expect(SessionSummary.project(cwd: nil, source: "codex") == "Codex")
        withSwitches { switches in
            switches.setReadsEveryReply(.opencode, true)
            switches.setMuted(firstKey, true)
            #expect(!switches.wantsReading(tool: .opencode, thread: firstKey))
            #expect(switches.wantsReading(tool: .opencode, thread: SessionSummary.key(session: second.session, cwd: second.cwd, source: second.source)))
        }
    }

    @Test func aReplyWithoutASessionIdIsItsFoldersThread() {
        let thread = SessionSummary.key(session: nil, cwd: "/Users/me/app", source: "opencode")
        #expect(thread == SessionSummary.key(of: Reply(text: "x", source: "opencode", cwd: "/Users/me/app", session: nil, state: .kept)))
        withSwitches { switches in
            switches.setReadsEveryReply(.opencode, true)
            switches.setMuted(thread, true)
            #expect(!switches.wantsReading(tool: .opencode, thread: thread))
        }
    }

    // MARK: Everything off

    /// Once a timed off has ended it's forgotten, so setting the clock back can't bring it back
    /// while the menu bar icon says reading is on (review round 1, 2026-11-26).
    @Test func anEndedOffIsForgotten() {
        withSwitches { switches in
            switches.setReadingOff(until: at(17))
            switches.forgetEndedOff(now: at(16))
            #expect(switches.readingOff(now: at(16)) == at(17), "still going: kept")
            switches.forgetEndedOff(now: at(17, 1))
            #expect(switches.readingOff(now: at(16)) == nil, "over: gone, even with the clock set back")
            switches.setReadingOff(until: .distantFuture)
            switches.forgetEndedOff(now: at(17))
            #expect(switches.readingOff(now: at(17)) == .distantFuture)
        }
    }

    @Test func offBeatsEverySwitch() {
        withSwitches { switches in
            switches.setReadsEveryReply(.claude, true)
            switches.setSession("t", true)
            switches.setReadingOff(until: .distantFuture)
            #expect(!switches.wantsReading(tool: .claude, thread: "t"))
            switches.setReadingOff(until: nil)
            #expect(switches.wantsReading(tool: .claude, thread: "t"))
        }
    }

    @Test func aTimedOffEndsByItself() {
        withSwitches { switches in
            switches.setReadsEveryReply(.claude, true)
            switches.setReadingOff(until: at(17))
            #expect(switches.readingOff(now: at(16, 59)) == at(17))
            #expect(!switches.wantsReading(tool: .claude, thread: nil, now: at(16, 59)))
            #expect(switches.readingOff(now: at(17)) == nil)
            #expect(switches.wantsReading(tool: .claude, thread: nil, now: at(17, 1)))
        }
    }

    // MARK: How long

    @Test func untilMorningIsTomorrowsEightOrTodaysBeforeIt() {
        #expect(ReadingOff.nextMorning(after: at(16, 12), calendar: calendar) == at(8, day: 27))
        #expect(ReadingOff.nextMorning(after: at(2), calendar: calendar) == at(8))
        #expect(ReadingOff.nextMorning(after: at(8), calendar: calendar) == at(8, day: 27))
    }

    @Test func itSaysWhenReadingComesBack() {
        let us = Locale(identifier: "en_US")
        let nnbsp = "\u{202F}"
        #expect(ReadingOff.describe(until: at(17, 12), now: at(16, 12), calendar: calendar, locale: us) == "5:12\(nnbsp)PM")
        #expect(ReadingOff.describe(until: at(8, day: 27), now: at(16, 12), calendar: calendar, locale: us) == "8\(nnbsp)AM tomorrow")
        #expect(ReadingOff.describe(until: .distantFuture, now: at(16), calendar: calendar, locale: us) == nil)
        #expect(ReadingOff.morningLabel(now: at(2), calendar: calendar, locale: us) == "Until 8\(nnbsp)AM")
        #expect(ReadingOff.morningLabel(now: at(16), calendar: calendar, locale: us) == "Until 8\(nnbsp)AM tomorrow")
        #expect(ReadingOff.status(until: .distantFuture, now: at(16), calendar: calendar, locale: us) == "Reading is off")
    }

    // MARK: The three lengths, in every place that offers them

    /// The menu bar, the sidebar and Reading offer the same three, in this order (owner, 2026-11-27).
    @Test func eachLengthEndsWhenItSays() {
        #expect(ReadingOff.Length.allCases == [.hour, .morning, .untilOn])
        func pick(_ length: ReadingOff.Length, at now: Date) -> Date? {
            ReadingOff.Choice.all(now: now, calendar: calendar).first { $0.length == length }?.until(pickedAt: now)
        }
        #expect(ReadingOff.Choice.all(now: at(16), calendar: calendar).map(\.length) == ReadingOff.Length.allCases)
        #expect(pick(.hour, at: at(16, 12)) == at(17, 12))
        #expect(pick(.morning, at: at(16, 12)) == at(8, day: 27))
        #expect(pick(.morning, at: at(2)) == at(8))
        #expect(pick(.untilOn, at: at(16)) == .distantFuture)
    }

    /// A menu can sit open while the clock moves on. A pick means what the menu said when it
    /// opened: opened at 7:59 saying "Until 8 AM" and picked at 8:01, it doesn't turn reading off
    /// until 8 AM the next day (review round 1, 2026-11-27). For 1 hour counts from the pick.
    @Test func aPickMeansWhatTheMenuSaidWhenItOpened() {
        let us = Locale(identifier: "en_US")
        let opened = ReadingOff.Choice.all(now: at(7, 59), calendar: calendar, locale: us)
        func choice(_ length: ReadingOff.Length) -> ReadingOff.Choice { opened.first { $0.length == length }! }
        #expect(choice(.morning).title == "Until 8\u{202F}AM")
        #expect(choice(.morning).until(pickedAt: at(7, 59).addingTimeInterval(30)) == at(8))
        #expect(choice(.morning).until(pickedAt: at(8, 1)) == nil)
        #expect(choice(.hour).until(pickedAt: at(8, 1)) == at(9, 1))
        #expect(choice(.untilOn).until(pickedAt: at(8, 1)) == .distantFuture)

        // Opened just before midnight, picked just after: "8 AM tomorrow" is still the same 8 AM.
        let lateNight = ReadingOff.Choice.all(now: at(23, 59), calendar: calendar, locale: us)
        let morning = lateNight.first { $0.length == .morning }!
        #expect(morning.title == "Until 8\u{202F}AM tomorrow")
        #expect(morning.until(pickedAt: at(0, 1, day: 27)) == at(8, day: 27))
    }

    /// Each finishes "Turn reading off": the same words wherever the menu opens.
    @Test func eachLengthFinishesTurnReadingOff() {
        let us = Locale(identifier: "en_US")
        let nnbsp = "\u{202F}"
        func menu(_ length: ReadingOff.Length, _ now: Date) -> String { length.menuTitle(now: now, calendar: calendar, locale: us) }
        #expect(menu(.hour, at(16)) == "For 1 hour")
        #expect(menu(.morning, at(16)) == "Until 8\(nnbsp)AM tomorrow")
        #expect(menu(.morning, at(2)) == "Until 8\(nnbsp)AM")
        #expect(menu(.untilOn, at(16)) == "Until I turn it back on")
    }

    // MARK: Copy

    /// The Reading footer broke "/readback:speak on" after its slash (UI check, 2026-11-26).
    @Test func aCommandsSlashStaysWithItsName() {
        let joiner = "\u{2060}"
        let footer = SlashCommand.keptWhole(in: "/readback:speak off mutes one session, /readback:speak on reads one, and /read.")
        #expect(footer == "/\(joiner)readback:speak off mutes one session, /\(joiner)readback:speak on reads one, and /\(joiner)read.")
        #expect(footer.replacingOccurrences(of: joiner, with: "") == "/readback:speak off mutes one session, /readback:speak on reads one, and /read.")
        let untouched = "Edits ~/.claude/settings.json, and/or keeps <name>.before-readback. A lone / stays."
        #expect(SlashCommand.keptWhole(in: untouched) == untouched)
    }

    // MARK: The queue

    @Test func mutingAThreadStopsItsReadingAndKeepsItsWaitingReplies() {
        var queue = ReplyQueue()
        let first = SpeakRequest(text: "One.", source: "claude", session: "noisy")
        guard case .play(let playing, _) = queue.received(first, switchedOn: true, reading: nil, cutIn: false) else {
            Issue.record("the first reply didn't play"); return
        }
        let reading = ReplyQueue.Reading(replyID: playing.id, session: "noisy", isSpeaking: true)
        _ = queue.received(SpeakRequest(text: "Two.", source: "claude", session: "noisy"), switchedOn: true, reading: reading, cutIn: false)
        _ = queue.received(SpeakRequest(text: "Other.", source: "claude", session: "calm"), switchedOn: true, reading: reading, cutIn: false)
        #expect(queue.mute(thread: "noisy", reading: reading) == .stopThenNext)
        let waiting = queue.history.replies.filter { $0.state == .waiting }
        #expect(waiting.map(\.text) == ["Other."])
        let muted = queue.history.replies.first { $0.text == "Two." }
        #expect(muted?.state == .kept, "kept in History, not dropped")
        guard case .play(let next, _) = queue.playNext(reading: nil) else {
            Issue.record("the other thread's reply didn't play next"); return
        }
        #expect(next.text == "Other.")
    }

    /// Clear in History drops the reply being read; muting its thread still stops it, because the
    /// thread comes from the reading, not the history (review round 1, 2026-11-26).
    @Test func mutingStopsTheReadingEvenAfterHistoryWasCleared() {
        var queue = ReplyQueue()
        guard case .play(let playing, _) = queue.received(SpeakRequest(text: "Long.", source: "claude", session: "noisy"),
                                                          switchedOn: true, reading: nil, cutIn: false) else {
            Issue.record("the reply didn't play"); return
        }
        let reading = ReplyQueue.Reading(replyID: playing.id, session: "noisy", thread: "noisy", isSpeaking: true)
        _ = queue.history.clearForUndo()
        #expect(queue.history.reply(playing.id) == nil)
        #expect(queue.mute(thread: "noisy", reading: reading) == .stopThenNext)
    }

    @Test func mutingAnOpenCodeFolderStopsItsReading() {
        var queue = ReplyQueue()
        let request = SpeakRequest(text: "Done.", source: "opencode", cwd: "/Users/me/app")
        guard case .play(let playing, _) = queue.received(request, switchedOn: true, reading: nil, cutIn: false) else {
            Issue.record("the reply didn't play"); return
        }
        let thread = SessionSummary.key(session: nil, cwd: "/Users/me/app", source: "opencode")
        let reading = ReplyQueue.Reading(replyID: playing.id, session: nil, thread: thread, isSpeaking: true)
        #expect(queue.mute(thread: thread, reading: reading) == .stopThenNext)
    }

    @Test func mutingAnotherThreadLeavesTheReadingAlone() {
        var queue = ReplyQueue()
        guard case .play(let playing, _) = queue.received(SpeakRequest(text: "One.", source: "claude", session: "calm"),
                                                          switchedOn: true, reading: nil, cutIn: false) else {
            Issue.record("the reply didn't play"); return
        }
        let reading = ReplyQueue.Reading(replyID: playing.id, session: "calm", isSpeaking: true)
        #expect(queue.mute(thread: "noisy", reading: reading) == .nothing)
    }
}
