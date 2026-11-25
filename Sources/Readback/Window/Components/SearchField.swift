import SwiftUI

/// Readback's own search field (owner, 2026-11-25), in place of the stock NSSearchField: a
/// magnifier, the prompt, a clear button that springs in once there's text, Esc to empty it,
/// and an accent focus ring. It widens a little while it has focus.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 190
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(_ prompt: String, text: Binding<String>, width: CGFloat = 190) {
        self.prompt = prompt
        _text = text
        self.width = width
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: focused && !reduceMotion ? width + 40 : width)
        .background((scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.05)),
                    in: RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : WindowColors.hairline, lineWidth: focused ? 2 : 0.5)
        }
        .animation(Motion.pop(reduceMotion), value: text.isEmpty)
        .animation(Motion.spring(reduceMotion), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
