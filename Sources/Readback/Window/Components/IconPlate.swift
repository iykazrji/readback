import SwiftUI

/// A square button that's just a glyph on a plate, drawn like a secondary button: the controls'
/// tint, hairline edge, hover and press. 28 pt (small) or 34 pt. Owner's look, 2026-11-25.
struct IconPlate: View {
    let symbol: String
    let help: String
    let small: Bool
    /// Drawn as the one solid plate, like a switch that's on: a thread's mute while it's muted.
    let on: Bool
    let action: () -> Void

    init(_ symbol: String, help: String, small: Bool = true, on: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.small = small
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 12 : 14, weight: .semibold))
        }
        .buttonStyle(PlateStyle(size: small ? ControlMetrics.smallHeight : ControlMetrics.height,
                                radius: small ? ControlMetrics.smallRadius : ControlMetrics.radius, on: on))
        .focusEffectDisabled()   // the plate draws its own neutral keyboard ring
        .help(help)
        .accessibilityLabel(help)
    }

    private struct PlateStyle: ButtonStyle {
        let size: CGFloat
        let radius: CGFloat
        let on: Bool

        func makeBody(configuration: Configuration) -> some View {
            Plate(size: size, radius: radius, on: on, configuration: configuration)
        }
    }

    private struct Plate: View {
        let size: CGFloat
        let radius: CGFloat
        let on: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .foregroundStyle(on ? ControlMetrics.primaryText(scheme) : .primary)
                .frame(width: size, height: size)
                .background(on ? ControlMetrics.primaryFill(scheme)
                            : configuration.isPressed ? ControlMetrics.pressFill(scheme)
                            : hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme), in: shape)
                .overlay { if !on { Hairline(shape, hovering ? ControlMetrics.hoverEdge(scheme) : ControlMetrics.edge(scheme)) } }
                .keyboardFocusRing(isFocused, shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = isEnabled && $0 }
        }
    }
}
