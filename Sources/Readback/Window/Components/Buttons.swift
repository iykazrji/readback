import SwiftUI

/// One set of measurements and tints for every control in the window, the setup sheet and the
/// player (buttons, dropdowns, search, switch, segmented control, checkbox), so a row of them
/// lines up exactly and they read as one set. Heights are fixed, not the result of padding
/// around text.
///
/// Chosen by the owner on 2026-11-25 from clickable mockups: black-and-white plates (white and
/// black tints only, no accent colour), 34 pt tall ("make them seem a lot more substantial"),
/// each with a very thin edge. They turned down a brass direction and outline-only controls.
enum ControlMetrics {
    static let height: CGFloat = 34
    static let smallHeight: CGFloat = 28
    /// 0.29 × the height, rounded.
    static let radius: CGFloat = 10
    static let smallRadius: CGFloat = 8
    static let fontSize: CGFloat = 13.5
    static let smallFontSize: CGFloat = 12.5
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 12
    static let quietPadding: CGFloat = 10
    static let smallQuietPadding: CGFloat = 8
    /// The edge is a hairline drawn inside the shape (the owner didn't pick between this and 1 pt).
    static let edgeWidth: CGFloat = 0.5

    static func fill(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.08, light: 0.045) }
    static func hoverFill(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.12, light: 0.075) }
    static func pressFill(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.16, light: 0.10) }
    static func edge(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.13, light: 0.11) }
    static func hoverEdge(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.20, light: 0.18) }

    /// The one solid plate: the main action, a switch that's on, a ticked checkbox.
    static func primaryFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255) : Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255)
    }

    /// Text and glyphs on the primary plate.
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255) : .white
    }

    /// Keyboard focus: a neutral ring 2 pt outside the edge, so nothing moves.
    static func focusRing(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.55, light: 0.45) }

    /// The highlighted row in a menu.
    static func menuHighlight(_ scheme: ColorScheme) -> Color { tint(scheme, dark: 0.08, light: 0.05) }

    /// White on dark, black on light, at an opacity.
    private static func tint(_ scheme: ColorScheme, dark: Double, light: Double) -> Color {
        scheme == .dark ? Color.white.opacity(dark) : Color.black.opacity(light)
    }
}

/// Readback's buttons, in place of the stock bezel. Flat: no shadow on any button, by the
/// owner's call. Each sinks a little while pressed and springs back, and brightens under the
/// pointer, without changing size or weight.
struct ReadbackButtonStyle: ButtonStyle {
    enum Kind {
        /// The one main action: the solid plate.
        case primary
        /// Everything else: a plate of tint with a thin edge.
        case secondary
        /// A text-like action (See all): no plate until the pointer is over it.
        case quiet
        /// Removes or undoes something: drawn like secondary with quieter text. No red (my call,
        /// 2026-11-25: the confirmation it opens says what goes).
        case destructive
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        Styled(kind: kind, configuration: configuration)
    }

    private struct Styled: View {
        let kind: Kind
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            let radius = small ? ControlMetrics.smallRadius : ControlMetrics.radius
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .font(.system(size: small ? ControlMetrics.smallFontSize : ControlMetrics.fontSize,
                              weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, padding(small))
                .frame(height: small ? ControlMetrics.smallHeight : ControlMetrics.height)
                .background(fill, in: shape)
                .overlay {
                    if kind == .secondary || kind == .destructive {
                        shape.strokeBorder(hovering ? ControlMetrics.hoverEdge(scheme) : ControlMetrics.edge(scheme),
                                           lineWidth: ControlMetrics.edgeWidth)
                    }
                }
                .opacity(kind == .primary && hovering && !configuration.isPressed ? 0.9 : 1)
                .overlay {
                    RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                        .inset(by: -2)
                        .strokeBorder(ControlMetrics.focusRing(scheme), lineWidth: 2)
                        .opacity(isFocused ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = isEnabled && $0 }
        }

        private func padding(_ small: Bool) -> CGFloat {
            kind == .quiet ? (small ? ControlMetrics.smallQuietPadding : ControlMetrics.quietPadding)
                : (small ? ControlMetrics.smallPadding : ControlMetrics.padding)
        }

        private var foreground: Color {
            switch kind {
            case .primary: return ControlMetrics.primaryText(scheme)
            case .secondary, .quiet: return .primary
            case .destructive: return hovering ? .primary : .secondary
            }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                return ControlMetrics.primaryFill(scheme)
            case .secondary, .destructive:
                return pressed ? ControlMetrics.pressFill(scheme) : hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme)
            case .quiet:
                return pressed ? ControlMetrics.pressFill(scheme) : hovering ? ControlMetrics.hoverFill(scheme) : .clear
            }
        }
    }
}

extension ButtonStyle where Self == ReadbackButtonStyle {
    static func readback(_ kind: ReadbackButtonStyle.Kind) -> ReadbackButtonStyle { ReadbackButtonStyle(kind: kind) }
}
