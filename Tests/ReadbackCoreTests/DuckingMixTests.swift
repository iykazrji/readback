import CoreAudio
import Foundation
import Testing
@testable import ReadbackCore

/// Other apps' sound, taken from the tap and played back quieter: channel layout and gain.
@Suite struct DuckingMixTests {
    /// Output buffers as Core Audio hands them over: `layout` is the channels in each buffer.
    private final class Outputs {
        let list: UnsafeMutableAudioBufferListPointer
        let storage: [UnsafeMutablePointer<Float>]
        let frames: Int
        init(layout: [Int], frames: Int) {
            self.frames = frames
            list = AudioBufferList.allocate(maximumBuffers: layout.count)
            storage = layout.map { channels in
                let p = UnsafeMutablePointer<Float>.allocate(capacity: channels * frames)
                p.initialize(repeating: 99, count: channels * frames)   // garbage, to see it cleared
                return p
            }
            for (i, channels) in layout.enumerated() {
                list[i] = AudioBuffer(mNumberChannels: UInt32(channels),
                                      mDataByteSize: UInt32(channels * frames * MemoryLayout<Float>.size),
                                      mData: storage[i])
            }
        }
        func samples(_ buffer: Int) -> [Float] {
            let channels = Int(list[buffer].mNumberChannels)
            return Array(UnsafeBufferPointer(start: storage[buffer], count: channels * frames))
        }
        deinit { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
    }

    private func render(_ tap: [Float], channels: Int, into out: Outputs, target: Float, current: inout Float,
                        coefficient: Float = 1, edgeCoefficient: Float? = nil) {
        tap.withUnsafeBufferPointer { p in
            DuckingMix.render(tap: p.baseAddress!, tapChannels: channels, tapFrames: tap.count / channels,
                              into: out.list, target: target, current: &current, coefficient: coefficient, edgeCoefficient: edgeCoefficient)
        }
    }

    @Test func stereoIntoOneInterleavedStereoBuffer() {
        let out = Outputs(layout: [2], frames: 2)
        var gain: Float = 0.5
        render([1, -1, 0.5, -0.5], channels: 2, into: out, target: 0.5, current: &gain)
        #expect(out.samples(0) == [0.5, -0.5, 0.25, -0.25])
    }

    @Test func stereoIntoTwoPlanarBuffers() {
        let out = Outputs(layout: [1, 1], frames: 2)
        var gain: Float = 1
        render([1, -1, 0.5, -0.5], channels: 2, into: out, target: 1, current: &gain)
        #expect(out.samples(0) == [1, 0.5])
        #expect(out.samples(1) == [-1, -0.5])
    }

    @Test func extraOutputChannelsStaySilent() {
        let out = Outputs(layout: [4], frames: 1)
        var gain: Float = 1
        render([0.2, 0.4], channels: 2, into: out, target: 1, current: &gain)
        #expect(out.samples(0) == [0.2, 0.4, 0, 0])
    }

    @Test func aMonoOutputGetsBothSidesMixed() {
        let out = Outputs(layout: [1], frames: 1)
        var gain: Float = 1
        render([0.2, 0.4], channels: 2, into: out, target: 1, current: &gain)
        #expect(abs(out.samples(0)[0] - 0.3) < 0.0001)
    }

    @Test func aMonoTapFeedsBothSides() {
        let out = Outputs(layout: [2], frames: 1)
        var gain: Float = 1
        render([0.7], channels: 1, into: out, target: 1, current: &gain)
        #expect(out.samples(0) == [0.7, 0.7])
    }

    /// The gain eases toward its target a little every frame, so there's no click.
    @Test func theGainEasesTowardsItsTarget() {
        let frames = 2000
        let out = Outputs(layout: [2], frames: frames)
        var gain: Float = 1
        let coefficient = DuckingMix.rampCoefficient(sampleRate: 48_000)
        render([Float](repeating: 1, count: frames * 2), channels: 2, into: out, target: DuckingMix.loweredGain, current: &gain, coefficient: coefficient)
        let left = stride(from: 0, to: frames * 2, by: 2).map { out.samples(0)[$0] }
        #expect(left.first! < 1 && left.first! > 0.99)                 // starts right where it was
        #expect(zip(left, left.dropFirst()).allSatisfy { $0 >= $1 })   // only ever goes down
        // 2000 frames is 41.7 ms, about half the 80 ms time constant: 0.3 + 0.7 * e^(-41.7/80)
        #expect(abs(gain - 0.716) < 0.01)
        var more = gain
        let long = Outputs(layout: [2], frames: 48_000)
        render([Float](repeating: 1, count: 96_000), channels: 2, into: long, target: DuckingMix.loweredGain, current: &more, coefficient: coefficient)
        #expect(abs(more - DuckingMix.loweredGain) < 0.001)            // a second later it's there
    }

    /// Starting the tap: from silence up to the lowered level in a blink (no jump, no long dip),
    /// then the slow ramp for anything between lowered and full.
    @Test func fadingInFromSilenceIsQuickAndSmooth() {
        let rate = 48_000.0
        let frames = Int(rate * 0.06)   // 60 ms
        let out = Outputs(layout: [2], frames: frames)
        var gain: Float = 0
        render([Float](repeating: 1, count: frames * 2), channels: 2, into: out, target: DuckingMix.loweredGain, current: &gain,
               coefficient: DuckingMix.rampCoefficient(sampleRate: rate), edgeCoefficient: DuckingMix.edgeCoefficient(sampleRate: rate))
        let left = stride(from: 0, to: frames * 2, by: 2).map { out.samples(0)[$0] }
        #expect(left.first! < 0.001)                                     // starts at silence
        #expect(zip(left, left.dropFirst()).allSatisfy { $0 <= $1 })    // only rises
        #expect(zip(left, left.dropFirst()).allSatisfy { $1 - $0 < 0.002 })   // no jump between samples
        #expect(abs(gain - DuckingMix.loweredGain) < 0.01)              // there within 60 ms
    }

    /// Letting go: down to silence quickly before the tap goes, whatever level it was at.
    @Test func fadingOutToSilenceIsQuick() {
        let rate = 48_000.0
        let frames = Int(rate * 0.08)
        let out = Outputs(layout: [2], frames: frames)
        var gain: Float = 1
        render([Float](repeating: 1, count: frames * 2), channels: 2, into: out, target: 0, current: &gain,
               coefficient: DuckingMix.rampCoefficient(sampleRate: rate), edgeCoefficient: DuckingMix.edgeCoefficient(sampleRate: rate))
        #expect(gain < 0.01)
    }

    /// Between lowered and full it stays on the slow ramp, so the music eases rather than blinks.
    @Test func betweenLoweredAndFullItEasesSlowly() {
        let rate = 48_000.0
        let frames = Int(rate * 0.06)
        let out = Outputs(layout: [2], frames: frames)
        var gain: Float = 1
        render([Float](repeating: 1, count: frames * 2), channels: 2, into: out, target: DuckingMix.loweredGain, current: &gain,
               coefficient: DuckingMix.rampCoefficient(sampleRate: rate), edgeCoefficient: DuckingMix.edgeCoefficient(sampleRate: rate))
        #expect(gain > 0.6)   // 60 ms into an 80 ms ramp: still well on its way down
    }

    @Test func framesStopAtTheShorterSideAndTheRestIsSilent() {
        let out = Outputs(layout: [2], frames: 3)
        var gain: Float = 1
        render([1, 1], channels: 2, into: out, target: 1, current: &gain)   // only one tap frame
        #expect(out.samples(0) == [1, 1, 0, 0, 0, 0])
    }

    @Test func nothingLoudGetsThrough() {
        let out = Outputs(layout: [2], frames: 1)
        var gain: Float = 1
        render([3, -3], channels: 2, into: out, target: 1, current: &gain)
        #expect(out.samples(0) == [1, -1])
    }
}
