import Foundation
import Testing
@testable import ReadbackCore

/// When other apps' sound is taken over, goes down and comes back, with the switch on or off.
@Suite struct OtherAudioDuckingTests {
    @Test func nothingHappensWithTheSwitchOff() {
        var ducking = OtherAudioDucking()
        #expect(ducking.readingChanged(.preparing, switchedOn: false) == .nothing)
        #expect(ducking.readingChanged(.playing, switchedOn: false) == .nothing)
        #expect(ducking.readingChanged(.stopped, switchedOn: false) == .nothing)
        #expect(ducking.state == .normal)
    }

    /// The usual reading: take over while it prepares (the cut lands under the cue sound),
    /// lower when the voice starts, give back a moment after it ends.
    @Test func aReadingTakesOverThenLowersThenRestores() {
        var ducking = OtherAudioDucking()
        #expect(ducking.readingChanged(.preparing, switchedOn: true) == .takeOver)
        #expect(ducking.state == .takenOver)
        #expect(ducking.readingChanged(.playing, switchedOn: true) == .lower)
        #expect(ducking.isLowered)
        #expect(ducking.readingChanged(.stopped, switchedOn: true) == .restoreAfter(OtherAudioDucking.restoreDelay))
        #expect(ducking.restoreDue(.stopped) == .restore)
        #expect(ducking.state == .normal)
    }

    /// Pressing play on a reply that's ready skips preparing: lower straight away.
    @Test func playingWithoutPreparingLowersAtOnce() {
        var ducking = OtherAudioDucking()
        #expect(ducking.readingChanged(.playing, switchedOn: true) == .lower)
        #expect(ducking.readingChanged(.playing, switchedOn: true) == .keepLowered)
    }

    @Test func betweenChunksItStaysDown() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.playing, switchedOn: true)
        #expect(ducking.readingChanged(.preparing, switchedOn: true) == .keepLowered)
        #expect(ducking.readingChanged(.playing, switchedOn: true) == .keepLowered)
    }

    @Test func aReadingThatStartsAgainBeforeTheRestoreKeepsItDown() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.playing, switchedOn: true)
        _ = ducking.readingChanged(.stopped, switchedOn: true)
        #expect(ducking.readingChanged(.preparing, switchedOn: true) == .keepLowered)
        // The timer that was set fires late anyway: nothing to do.
        #expect(ducking.restoreDue(.preparing) == .nothing)
        #expect(ducking.isLowered)
    }

    /// A reading that fails while preparing never lowers anything; the takeover is given back.
    @Test func aReadingThatNeverPlaysGivesTheTakeoverBack() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.preparing, switchedOn: true)
        #expect(ducking.readingChanged(.preparing, switchedOn: true) == .keepTakenOver)
        #expect(ducking.readingChanged(.stopped, switchedOn: true) == .restoreAfter(OtherAudioDucking.restoreDelay))
        #expect(ducking.restoreDue(.stopped) == .restore)
        #expect(ducking.state == .normal)
    }

    /// Deep review 2026-11-26, P2-3: this expected `.restore`, which brings the sound back but
    /// keeps the tap for the 60-second linger, with the switch already off. Off lets it go now.
    @Test func switchingOffMidReadingRestoresAtOnce() {
        var ducking = OtherAudioDucking()
        _ = ducking.readingChanged(.playing, switchedOn: true)
        #expect(ducking.readingChanged(.playing, switchedOn: false) == .release)
        #expect(ducking.state == .normal)
    }

    @Test func aRestoreTimerWithNothingTakenDoesNothing() {
        var ducking = OtherAudioDucking()
        #expect(ducking.restoreDue(.stopped) == .nothing)
    }
}
