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
    @State private var hovering = false
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
                .font(.system(size: 13, weight: .medium))
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
                    // A 20 pt round button, as in the owner's approved mockup (2026-11-25), inside a
                    // 28 pt target you don't miss.
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 20, height: 20)
                        .background(ControlMetrics.pressFill(scheme), in: Circle())
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)   // the target hangs into the padding; the circle sits 8 pt from the edge
                .help("Clear the search")
                .accessibilityLabel("Clear the search")
                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, ControlMetrics.padding)
        .frame(width: width, height: ControlMetrics.height)
        .background(focused ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme), in: shape)
        .overlay {
            shape.strokeBorder(hovering || focused ? ControlMetrics.hoverEdge(scheme) : ControlMetrics.edge(scheme),
                               lineWidth: ControlMetrics.edgeWidth)
        }
        .overlay {
            // Focus: a neutral 2 pt ring 2 pt outside the edge, so the field's size never changes.
            RoundedRectangle(cornerRadius: ControlMetrics.radius + 2, style: .continuous)
                .inset(by: -2)
                .strokeBorder(ControlMetrics.focusRing(scheme), lineWidth: 2)
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .animation(Motion.pop(reduceMotion), value: text.isEmpty)
        .animation(.easeOut(duration: 0.15), value: focused)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(shape)
        .onTapGesture { focused = true }
    }
}
