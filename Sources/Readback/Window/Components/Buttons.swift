import SwiftUI

/// One set of measurements for every control in the window (buttons, dropdowns, the search
/// field), so a row of them lines up exactly: the same height, corners, text size and fill.
/// Heights are fixed, not the result of padding around text, which is how the first version
/// ended up with a search field taller than the buttons beside it (owner, 2026-11-25).
enum ControlMetrics {
    static let height: CGFloat = 28
    static let smallHeight: CGFloat = 22
    static let radius: CGFloat = 8
    static let smallRadius: CGFloat = 6
    static let fontSize: CGFloat = 13
    static let smallFontSize: CGFloat = 11.5
    static let padding: CGFloat = 12
    static let smallPadding: CGFloat = 9

    /// The resting fill of secondary buttons, dropdowns and the search field.
    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    /// Under the pointer, and pressed.
    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.085)
    }

    static func pressFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.19) : Color.black.opacity(0.11)
    }

    /// The hairline around them: a touch stronger than the card hairline so the edge reads on glass.
    static func edge(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
    }
}

/// Readback's buttons, in place of the stock bezel (the owner found it ugly, 2026-11-25). Flat:
/// no shadows on any button, by the owner's call. Each sinks to 0.96 while pressed and springs
/// back, and brightens under the pointer, without changing size or weight.
struct ReadbackButtonStyle: ButtonStyle {
    enum Kind {
        /// The one main action: accent fill.
        case primary
        /// Everything else: a light translucent fill with a hairline.
        case secondary
        /// A text-like action (See all): accent text, a fill only under the pointer.
        case quiet
        /// Removes or undoes something: a red tint.
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
        @State private var hovering = false

        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            let shape = RoundedRectangle(cornerRadius: small ? ControlMetrics.smallRadius : ControlMetrics.radius, style: .continuous)
            configuration.label
                .font(.system(size: small ? ControlMetrics.smallFontSize : ControlMetrics.fontSize, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .quiet ? (small ? 6 : 8) : (small ? ControlMetrics.smallPadding : ControlMetrics.padding))
                .frame(height: small ? ControlMetrics.smallHeight : ControlMetrics.height)
                .background(fill, in: shape)
                .overlay {
                    if kind == .secondary { shape.strokeBorder(ControlMetrics.edge(scheme), lineWidth: 0.5) }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = isEnabled && $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: return .white
            case .secondary: return .primary
            case .quiet: return .accentColor
            case .destructive: return scheme == .dark ? Color(red: 1, green: 0.55, blue: 0.55) : Color(red: 0.78, green: 0.13, blue: 0.13)
            }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                return Color.accentColor.opacity(pressed ? 0.82 : hovering ? 0.92 : 1)
            case .secondary:
                return pressed ? ControlMetrics.pressFill(scheme) : hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme)
            case .quiet:
                return Color.accentColor.opacity(pressed ? 0.18 : hovering ? 0.12 : 0)
            case .destructive:
                return Color.red.opacity(pressed ? 0.26 : hovering ? 0.2 : 0.13)
            }
        }
    }
}

extension ButtonStyle where Self == ReadbackButtonStyle {
    static func readback(_ kind: ReadbackButtonStyle.Kind) -> ReadbackButtonStyle { ReadbackButtonStyle(kind: kind) }
}
