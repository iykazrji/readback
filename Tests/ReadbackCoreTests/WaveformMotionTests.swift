import Foundation
import Testing
@testable import ReadbackCore

/// The playing mark: the player's waveform shape, a highlight sweeping across it, and bars
/// that grow and shrink out of step while a reply plays.
@Suite struct WaveformMotionTests {
    private let samples = stride(from: 0.0, through: 5.0, by: 0.05).map { $0 }

    @Test func heightsAreTheWaveformShape() {
        #expect(WaveformMotion.heights == [3, 6, 10, 13, 8, 5, 2.5])
    }

    @Test func stillWhenNotPlaying() {
        let frames = [0, 0.4, 3.7].map { WaveformMotion.frame(at: $0, playing: false, reduceMotion: false) }
        for frame in frames {
            #expect(frame.count == 7)
            #expect(frame.allSatisfy { $0.scale == 1 && $0.opacity == 1 })
        }
        #expect(frames[0] == frames[1] && frames[1] == frames[2])
    }

    @Test func barsMoveWhilePlaying() {
        let a = WaveformMotion.frame(at: 0, playing: true, reduceMotion: false)
        let b = WaveformMotion.frame(at: 0.3, playing: true, reduceMotion: false)
        #expect(zip(a, b).contains { $0.scale != $1.scale })
        for t in samples {
            for bar in WaveformMotion.frame(at: t, playing: true, reduceMotion: false) {
                #expect((0.45 - 1e-9)...(1.15 + 1e-9) ~= bar.scale)
            }
        }
    }

    @Test func sweepLightsOneRegionAtATime() {
        for t in samples {
            let frame = WaveformMotion.frame(at: t, playing: true, reduceMotion: false)
            #expect(frame.allSatisfy { (0.3 - 1e-9)...(1 + 1e-9) ~= $0.opacity })
            #expect(frame.contains { $0.opacity > 0.999 })
            #expect(frame.contains { $0.opacity < 0.5 })
        }
    }

    @Test func sweepRepeatsEvery1_25Seconds() {
        for t in [0.1, 0.7] {
            let a = WaveformMotion.frame(at: t, playing: true, reduceMotion: false)
            let b = WaveformMotion.frame(at: t + 1.25, playing: true, reduceMotion: false)
            for (x, y) in zip(a, b) { #expect(abs(x.opacity - y.opacity) < 1e-9) }
        }
    }

    @Test func reduceMotionKeepsBarsStill() {
        var opacities = Set<Double>()
        for t in samples {
            let frame = WaveformMotion.frame(at: t, playing: true, reduceMotion: true)
            #expect(frame.allSatisfy { $0.scale == 1 })
            opacities.insert(frame[0].opacity)
        }
        #expect(opacities.count > 1)
    }

    @Test func eachBarCarriesItsHeight() {
        let frame = WaveformMotion.frame(at: 1.3, playing: true, reduceMotion: false)
        #expect(frame.map(\.height) == WaveformMotion.heights)
    }
}
