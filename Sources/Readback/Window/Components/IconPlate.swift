import SwiftUI

/// A square button that's just a glyph on a plate, drawn like a secondary button: the controls'
/// tint, hairline edge, hover and press. 28 pt (small) or 34 pt. Owner's look, 2026-11-25.
struct IconPlate: View {
    let symbol: String
    let help: String
    let small: Bool
    let action: () -> Void

    init(_ symbol: String, help: String, small: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.small = small
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 12 : 14, weight: .semibold))
        }
        .buttonStyle(PlateStyle(size: small ? ControlMetrics.smallHeight : ControlMetrics.height,
                                radius: small ? ControlMetrics.smallRadius : ControlMetrics.radius))
        .help(help)
        .accessibilityLabel(help)
    }

    private struct PlateStyle: ButtonStyle {
        let size: CGFloat
        let radius: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            Plate(size: size, radius: radius, configuration: configuration)
        }
    }

    private struct Plate: View {
        let size: CGFloat
        let radius: CGFloat
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(configuration.isPressed ? ControlMetrics.pressFill(scheme)
                            : hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme), in: shape)
                .overlay { shape.strokeBorder(hovering ? ControlMetrics.hoverEdge(scheme) : ControlMetrics.edge(scheme),
                                              lineWidth: ControlMetrics.edgeWidth) }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = isEnabled && $0 }
        }
    }
}
