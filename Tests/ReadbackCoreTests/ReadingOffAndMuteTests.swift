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

    @Test func anOpenCodeFolderIsAThreadToo() {
        let thread = SessionSummary.key(session: nil, cwd: "/Users/me/app", source: "opencode")
        #expect(thread == SessionSummary.key(of: Reply(text: "x", source: "opencode", cwd: "/Users/me/app", session: nil, state: .kept)))
        withSwitches { switches in
            switches.setReadsEveryReply(.opencode, true)
            switches.setMuted(thread, true)
            #expect(!switches.wantsReading(tool: .opencode, thread: thread))
        }
    }

    // MARK: Everything off

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
