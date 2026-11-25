import CoreAudio
import Foundation

/// Plays other apps' sound back quieter while Readback reads: frames from a Core Audio tap
/// (interleaved Float32, one or two channels) into the output device's buffers, whatever their
/// layout, with a gain that eases toward its target so it never clicks. Runs on the real-time
/// audio thread: no allocation, no locks.
public enum DuckingMix {
    /// About a third of the volume (-10 dB): clearly in the background, still there.
    public static let loweredGain: Float = 0.3
    /// How quickly the gain moves between full and lowered: most of the way in about a quarter
    /// of a second, so the music eases down rather than dropping.
    static let rampSeconds: Float = 0.08
    /// Fading in from silence when the tap starts, and out to silence before it goes: quick, so
    /// it's a blink rather than a dip, but never a jump. macOS cuts the app's own output the
    /// moment the tap starts and lets it back the moment it goes, and the playback here runs a
    /// few milliseconds behind it, so switching straight over at full level clicked (heard by the
    /// owner on 2026-11-25).
    static let edgeSeconds: Float = 0.015

    /// The per-frame step toward the target for a one-pole ramp of `rampSeconds`.
    public static func rampCoefficient(sampleRate: Double) -> Float {
        coefficient(sampleRate: sampleRate, seconds: rampSeconds)
    }

    /// The same for `edgeSeconds`, used below the lowered level: fading in from silence or out to it.
    public static func edgeCoefficient(sampleRate: Double) -> Float {
        coefficient(sampleRate: sampleRate, seconds: edgeSeconds)
    }

    private static func coefficient(sampleRate: Double, seconds: Float) -> Float {
        guard sampleRate > 0 else { return 0.002 }
        return 1 - exp(-1 / (Float(sampleRate) * seconds))
    }

    /// Output channel 0 gets the left side and 1 the right; a mono output gets both mixed;
    /// any other channels, and frames the tap didn't fill, are silent.
    /// `edgeCoefficient` (defaults to `coefficient`) takes over below the lowered level, where
    /// the playback is fading in from silence or out to it.
    public static func render(tap: UnsafePointer<Float>, tapChannels: Int, tapFrames: Int,
                              into outputs: UnsafeMutableAudioBufferListPointer,
                              target: Float, current: inout Float, coefficient: Float, edgeCoefficient: Float? = nil) {
        var totalChannels = 0
        var frames = tapFrames
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            let channels = max(1, Int(buffer.mNumberChannels))
            totalChannels += channels
            frames = min(frames, Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        }
        guard frames > 0, totalChannels > 0, (1...2).contains(tapChannels) else { return }

        let goal = min(max(target, 0), 1)
        let step = min(max(coefficient, 0), 1)
        let edge = min(max(edgeCoefficient ?? coefficient, 0), 1)
        let edgeBelow = loweredGain * 0.98
        var gain = current
        for frame in 0..<frames {
            gain += (goal - gain) * (goal < edgeBelow || gain < edgeBelow ? edge : step)
            let base = frame * tapChannels
            let left = tap[base] * gain
            let right = (tapChannels == 1 ? tap[base] : tap[base + 1]) * gain
            var offset = 0
            for buffer in outputs {
                let channels = max(1, Int(buffer.mNumberChannels))
                if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                    let row = data.advanced(by: frame * channels)
                    for channel in 0..<channels {
                        let global = offset + channel
                        let sample: Float
                        if totalChannels == 1 { sample = (left + right) * 0.5 }
                        else if global == 0 { sample = left }
                        else if global == 1 { sample = right }
                        else { sample = 0 }
                        row[channel] = min(max(sample, -1), 1)
                    }
                }
                offset += channels
            }
        }
        current = gain
    }
}
