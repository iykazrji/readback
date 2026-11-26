import Foundation

/// Decides when other apps' sound is taken over, turned down for a reading and given back
/// ("Lower other sounds while reading", off unless the person switches it on). The app tells
/// it what the reader is doing and carries out the `Step` it returns, as with `ReplyQueue`.
///
/// Taking over is its own step because macOS cuts the other apps' own output the instant a tap
/// starts, and that cut clicks; nothing public softens it. So the tap takes over at full volume
/// as a reading starts preparing, where the cut lands under the cue sound before the voice,
/// and the sound only eases down once the voice plays. Chosen by the owner on 2026-11-25.
public struct OtherAudioDucking: Equatable {
    /// What the reader is doing, as far as other sound is concerned.
    public enum Reading: Equatable {
        /// Getting a reply ready: the cue sound, making the audio, between chunks.
        case preparing
        /// The voice is coming out.
        case playing
        /// Paused, finished, failed or closed.
        case stopped
    }

    public enum Step: Equatable {
        case nothing
        /// Start the tap with the sound at full volume, so the cut happens now.
        case takeOver
        /// Turn other sound down (taking over first if it hasn't yet).
        case lower
        /// It's down already: keep it there, and cancel a restore that's waiting.
        case keepLowered
        /// It's taken over at full: keep the tap, and cancel a restore that's waiting.
        case keepTakenOver
        /// Bring it back after this many seconds, unless a reading starts again first.
        case restoreAfter(TimeInterval)
        /// Bring it back now.
        case restore
        /// The switch went off: bring it back and let the tap go now, not after the linger.
        case release
    }

    public enum State: Equatable { case normal, takenOver, lowered }

    /// Long enough to bridge the gap between two chunks of a reply, or between a reply and the
    /// next one waiting (the queue starts it 0.8 s after the last ends), so music doesn't swell
    /// up and drop again in between.
    public static let restoreDelay: TimeInterval = 1.5

    public private(set) var state: State = .normal
    public var isLowered: Bool { state == .lowered }
    /// Whether the switch was on when last asked. Back to normal isn't the same as the tap gone:
    /// it lingers after a reading, so switching off has to let it go whatever the state says.
    private var wasSwitchedOn = false

    public init() {}

    /// The reader changed phase, or the switch changed.
    public mutating func readingChanged(_ reading: Reading, switchedOn: Bool) -> Step {
        if !switchedOn {
            guard wasSwitchedOn else { return .nothing }
            wasSwitchedOn = false
            state = .normal
            return .release
        }
        wasSwitchedOn = true
        switch (reading, state) {
        case (.playing, .lowered):
            return .keepLowered
        case (.playing, _):
            state = .lowered
            return .lower
        case (.preparing, .lowered):
            return .keepLowered   // between chunks: stay down
        case (.preparing, .takenOver):
            return .keepTakenOver
        case (.preparing, .normal):
            state = .takenOver
            return .takeOver
        case (.stopped, .normal):
            return .nothing
        case (.stopped, _):
            return .restoreAfter(Self.restoreDelay)
        }
    }

    /// The wait from `restoreAfter` is up.
    public mutating func restoreDue(_ reading: Reading) -> Step {
        guard state != .normal, reading == .stopped else { return .nothing }
        state = .normal
        return .restore
    }
}
