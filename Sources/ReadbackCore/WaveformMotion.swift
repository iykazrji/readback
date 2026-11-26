import Foundation

/// How the "playing" waveform moves, as numbers the view draws. It's the floating player's
/// SF Symbols `waveform` shape with two motions on top: a highlight sweeping across the bars
/// (like `.variableColor.iterative`), and each bar growing and shrinking on its own loop, out
/// of step with the others, like a voice. Paused or idle, it's the plain shape at full strength.
/// The owner asked for the waveform to move as well as sweep on 2026-11-25.
public enum WaveformMotion {
    /// Bar heights in a 13 pt tall box, left to right.
    public static let heights: [Double] = [3, 6, 10, 13, 8, 5, 2.5]

    /// One pass of the highlight across the bars.
    public static let sweepPeriod: TimeInterval = 1.25

    /// Each bar's grow-and-shrink loop, there and back.
    static let talkPeriods: [TimeInterval] = [0.62, 0.9, 0.74, 1.05, 0.68, 0.96, 0.58].map { $0 * 2 }
    static let talkOffset: TimeInterval = 0.37

    public struct Bar: Equatable, Sendable {
        public let height: Double
        /// Multiplies the height, about the bar's centre.
        public let scale: Double
        public let opacity: Double
    }

    public static func frame(at time: TimeInterval, playing: Bool, reduceMotion: Bool) -> [Bar] {
        heights.enumerated().map { index, height in
            guard playing else { return Bar(height: height, scale: 1, opacity: 1) }
            return Bar(height: height,
                       scale: reduceMotion ? 1 : talkScale(bar: index, at: time),
                       opacity: sweepOpacity(bar: index, at: time))
        }
    }

    /// The bars sit a seventh of a pass apart, so one is always lit.
    static func sweepOpacity(bar: Int, at time: TimeInterval) -> Double {
        let stagger = sweepPeriod / Double(heights.count)
        let phase = fraction((time - Double(bar) * stagger) / sweepPeriod)
        return interpolate(phase, through: [(0, 0.3), (0.08, 1), (0.30, 1), (0.42, 0.3), (1, 0.3)])
    }

    static func talkScale(bar: Int, at time: TimeInterval) -> Double {
        let period = talkPeriods[bar % talkPeriods.count]
        let phase = fraction((time + Double(bar) * talkOffset) / period)
        let there = phase < 0.5 ? phase * 2 : (1 - phase) * 2   // out and back, like CSS's alternate
        return interpolate(there, through: [(0, 1), (0.35, 0.45), (0.7, 1.15), (1, 0.7)], eased: true)
    }

    private static func fraction(_ x: Double) -> Double { x - x.rounded(.down) }

    private static func interpolate(_ x: Double, through stops: [(at: Double, value: Double)], eased: Bool = false) -> Double {
        for (a, b) in zip(stops, stops.dropFirst()) where x <= b.at {
            var t = b.at > a.at ? (x - a.at) / (b.at - a.at) : 1
            if eased { t = t * t * (3 - 2 * t) }
            return a.value + (b.value - a.value) * t
        }
        return stops.last?.value ?? 1
    }
}
