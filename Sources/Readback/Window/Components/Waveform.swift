import ReadbackCore
import SwiftUI

/// The "playing" mark everywhere: the floating player's waveform shape, with a highlight
/// sweeping across it and bars that grow and shrink like a voice (`WaveformMotion`). Paused or
/// idle it's still and at full strength, and nothing redraws: the timeline only runs while
/// playing. With Reduce Motion the bars stay still and only the sweep runs. The owner asked for
/// the window and the player to share this mark, and for it to move, on 2026-11-25.
struct Waveform: View {
    let playing: Bool
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(playing: Bool, height: CGFloat = 13) {
        self.playing = playing
        self.height = height
    }

    private var barWidth: CGFloat { height * 0.123 }
    private var gap: CGFloat { height * 0.06 }
    private var width: CGFloat {
        let count = CGFloat(WaveformMotion.heights.count)
        return barWidth * count + gap * (count - 1)
    }

    var body: some View {
        Group {
            if playing {
                TimelineView(.animation) { context in
                    bars(WaveformMotion.frame(at: context.date.timeIntervalSinceReferenceDate, playing: true, reduceMotion: reduceMotion))
                }
            } else {
                bars(WaveformMotion.frame(at: 0, playing: false, reduceMotion: reduceMotion))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private func bars(_ frame: [WaveformMotion.Bar]) -> some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(frame.indices, id: \.self) { index in
                let bar = frame[index]
                Capsule()
                    .frame(width: barWidth, height: max(barWidth, height * bar.height / 13 * bar.scale))
                    .opacity(bar.opacity)
            }
        }
        .frame(width: width, height: height)
    }
}
