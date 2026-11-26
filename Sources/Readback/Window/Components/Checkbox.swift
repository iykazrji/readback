import SwiftUI

/// Readback's checkbox, in place of the stock `.checkbox` toggle style: a 16 pt box with the
/// controls' edge, and when ticked the solid plate with a check that pops in. The whole row is
/// the target, Space toggles it when it has keyboard focus, and VoiceOver reads it as one
/// checkbox with its label. Part of the owner's black-and-white look, 2026-11-25.
struct ReadbackCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @FocusState private var focused: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    box.fill(configuration.isOn ? ControlMetrics.primaryFill(scheme)
                             : hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme))
                    if !configuration.isOn {
                        Hairline(box, ControlMetrics.hoverEdge(scheme))
                    }
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ControlMetrics.primaryText(scheme))
                        .scaleEffect(configuration.isOn || reduceMotion ? 1 : 0.4)
                        .opacity(configuration.isOn ? 1 : 0)
                }
                // 16 pt: the owner found 20 "slightly too big" (2026-11-25).
                .frame(width: 16, height: 16)
                .keyboardFocusRing(focused, box)
                .padding(.top, 6)   // level with a 28 pt tile's centre beside it
                configuration.label
            }
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .onHover { hovering = isEnabled && $0 }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.pop(reduceMotion), value: configuration.isOn)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .focusable(isEnabled)
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.space) { configuration.isOn.toggle(); return .handled }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "checked" : "unchecked")
            .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
        }
    }
}

extension ToggleStyle where Self == ReadbackCheckboxStyle {
    static var readbackCheckbox: ReadbackCheckboxStyle { ReadbackCheckboxStyle() }
}
