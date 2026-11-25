import SwiftUI

/// A download's progress, in place of the stock bar (which drew in the system accent): a 4 pt
/// capsule, the track in the controls' tint and the filled part in the solid plate's colour.
/// With no total yet, a short segment slides across; with Reduce Motion, the track just dims.
/// My call on the look (2026-11-25); the owner's black-and-white rule set the colours.
struct Meter: View {
    let fraction: Double?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fraction: Double?) {
        self.fraction = fraction
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(ControlMetrics.pressFill(scheme))
                if let fraction {
                    Capsule()
                        .fill(ControlMetrics.primaryFill(scheme))
                        .frame(width: max(4, width * min(max(fraction, 0), 1)))
                        .animation(Motion.spring(reduceMotion), value: fraction)
                } else if !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                        Capsule()
                            .fill(ControlMetrics.primaryFill(scheme))
                            .frame(width: width * 0.3)
                            .offset(x: (width * 1.3) * phase - width * 0.3)
                    }
                    .clipShape(Capsule())
                } else {
                    Capsule().fill(ControlMetrics.primaryFill(scheme).opacity(0.35))
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? "in progress")
    }
}
