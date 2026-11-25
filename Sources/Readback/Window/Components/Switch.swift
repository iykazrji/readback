import SwiftUI

/// Readback's own switch (owner, 2026-11-25), in place of the stock one, black and white like
/// every other control. Off, a tint track with the controls' hairline edge; on, the solid plate
/// with a contrasting thumb. The thumb stretches while it's held and springs across. Space
/// toggles it from the keyboard; `SpreadSwitchStyle` makes the whole row one VoiceOver switch.
/// 35 × 20: the owner found the mockup's 40 × 24 "a bit too high" and picked 20 pt (2026-11-25).
struct ReadbackSwitch: View {
    @Binding var isOn: Bool
    @State private var pressing = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private let width: CGFloat = 35
    private let height: CGFloat = 20
    private let inset: CGFloat = 2

    var body: some View {
        let thumb = height - inset * 2
        let stretch: CGFloat = pressing && !reduceMotion ? 5 : 0
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? ControlMetrics.primaryFill(scheme) : offTrack)
                .overlay { if !isOn { Capsule().strokeBorder(ControlMetrics.edge(scheme), lineWidth: ControlMetrics.edgeWidth) } }
            Capsule()
                .fill(thumbColor)
                .overlay {
                    // On a light window the white thumb needs an edge to read against the pale track.
                    if !isOn && scheme == .light { Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5) }
                }
                .frame(width: thumb + stretch, height: thumb)
                .padding(inset)
        }
        .frame(width: width, height: height)
        .keyboardFocusRing(focused, Capsule())
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Motion.spring(reduceMotion), value: isOn)
        .animation(Motion.spring(reduceMotion), value: pressing)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { pressing = true } }
                .onEnded { _ in
                    pressing = false
                    if isEnabled { isOn.toggle() }
                }
        )
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { isOn.toggle(); return .handled }
        .accessibilityHidden(true)   // the row speaks for it (SpreadSwitchStyle)
    }

    private var offTrack: Color { scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09) }

    private var thumbColor: Color {
        guard isOn, scheme == .dark else { return .white }
        return Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)
    }
}
