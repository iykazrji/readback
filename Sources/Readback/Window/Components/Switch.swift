import SwiftUI

/// Readback's own switch (owner, 2026-11-25), in place of the stock one: the track fills with
/// the accent, and the thumb stretches while it's held and springs across when let go. Space
/// toggles it from the keyboard; `SpreadSwitchStyle` makes the whole row one VoiceOver switch.
struct ReadbackSwitch: View {
    @Binding var isOn: Bool
    @State private var pressing = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = 32
    private let height: CGFloat = 19
    private let inset: CGFloat = 2

    var body: some View {
        let thumb = height - inset * 2
        let stretch: CGFloat = pressing && !reduceMotion ? 5 : 0
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentColor : (scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)))
            Capsule()
                .fill(Color.white)
                .frame(width: thumb + stretch, height: thumb)
                .padding(inset)
        }
        .frame(width: width, height: height)
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
        .onKeyPress(.space) { isOn.toggle(); return .handled }
        .accessibilityHidden(true)   // the row speaks for it (SpreadSwitchStyle)
    }
}
