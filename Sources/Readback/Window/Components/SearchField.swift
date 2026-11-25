import SwiftUI

/// Readback's own search field (owner, 2026-11-25), in place of the stock NSSearchField: a
/// magnifier, the prompt, a clear button that springs in once there's text, and Esc to empty
/// it. It shares `ControlMetrics` with the buttons and dropdowns beside it: the same height,
/// corners, fill and edge. Focus shows as a neutral ring (no accent colour), and the field
/// keeps its width, so nothing next to it moves.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat = 200
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(_ prompt: String, text: Binding<String>, width: CGFloat = 200) {
        self.prompt = prompt
        _text = text
        self.width = width
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.radius, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: ControlMetrics.fontSize))
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
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)   // a target you don't miss, inside the field's height
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -6)   // the 24 pt target hangs into the padding; the icon sits where the text would end
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, ControlMetrics.padding - 2)
        .frame(width: width, height: ControlMetrics.height)
        .background(focused ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme), in: shape)
        .overlay { shape.strokeBorder(ControlMetrics.edge(scheme), lineWidth: 0.5) }
        .overlay {
            // Focus: a neutral ring just outside the edge, so the field's size never changes.
            shape.inset(by: -2.5)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28), lineWidth: 1.5)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(Motion.pop(reduceMotion), value: text.isEmpty)
        .animation(.easeOut(duration: 0.15), value: focused)
        .contentShape(shape)
        .onTapGesture { focused = true }
    }
}
