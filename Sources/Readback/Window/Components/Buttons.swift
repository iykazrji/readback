import SwiftUI

/// Readback's buttons, in place of the stock bezel (the owner found it ugly, 2026-11-25). Flat:
/// no shadows on any button, by the owner's call. Each sinks a little while pressed and springs
/// back, and brightens under the pointer.
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
            configuration.label
                .font(.system(size: small ? 11.5 : 12.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, small ? 9 : 12)
                .padding(.vertical, small ? 3.5 : 5.5)
                .background(fill, in: RoundedRectangle(cornerRadius: small ? 7 : Radius.control + 1, style: .continuous))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: small ? 7 : Radius.control + 1, style: .continuous)
                            .strokeBorder(WindowColors.hairline, lineWidth: 0.5)
                    }
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.press : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = isEnabled && $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: return .white
            case .secondary: return .primary
            case .quiet: return .accentColor
            case .destructive: return scheme == .dark ? Color(red: 1, green: 0.54, blue: 0.54) : Color(red: 0.8, green: 0.15, blue: 0.15)
            }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                return Color.accentColor.opacity(pressed ? 0.8 : hovering ? 0.92 : 1)
            case .secondary:
                let base: Double = scheme == .dark ? 0.09 : 0.05
                let tone: Color = scheme == .dark ? .white : .black
                return tone.opacity(pressed ? base + 0.08 : hovering ? base + 0.05 : base)
            case .quiet:
                return Color.accentColor.opacity(pressed ? 0.18 : hovering ? 0.12 : 0)
            case .destructive:
                return Color.red.opacity(pressed ? 0.28 : hovering ? 0.22 : 0.14)
            }
        }
    }
}

extension ButtonStyle where Self == ReadbackButtonStyle {
    static func readback(_ kind: ReadbackButtonStyle.Kind) -> ReadbackButtonStyle { ReadbackButtonStyle(kind: kind) }
}
