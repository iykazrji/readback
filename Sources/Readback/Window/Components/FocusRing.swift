import AppKit
import SwiftUI

extension View {
    /// The controls' focus ring, shown only when focus arrived from the keyboard (Tab), the way a
    /// Mac shows it: not after a click, and not when a sheet focuses its first control on opening.
    /// `shape` is the ring itself, drawn 2 pt outside the control so nothing moves.
    func keyboardFocusRing<S: InsettableShape>(_ focused: Bool, _ shape: S) -> some View {
        modifier(KeyboardFocusRing(focused: focused, shape: shape))
    }
}

private struct KeyboardFocusRing<S: InsettableShape>: ViewModifier {
    let focused: Bool
    let shape: S
    @State private var viaKeyboard = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .overlay {
                shape.inset(by: -2)
                    .strokeBorder(ControlMetrics.focusRing(scheme), lineWidth: 2)
                    .opacity(focused && viaKeyboard ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: focused) { _, isFocused in
                viaKeyboard = isFocused && NSApp.currentEvent?.type == .keyDown
            }
    }
}

/// The controls' thin edge: exactly one device pixel on any screen, drawn inside the shape. A
/// fixed 0.5 pt line was a full pixel on Retina but half a pixel on a 1x display, where it
/// faded to almost nothing (final review, 2026-11-25).
struct Hairline<S: InsettableShape>: View {
    let shape: S
    let color: Color
    @Environment(\.displayScale) private var displayScale

    init(_ shape: S, _ color: Color) {
        self.shape = shape
        self.color = color
    }

    var body: some View {
        shape.strokeBorder(color, lineWidth: 1 / max(displayScale, 1)).allowsHitTesting(false)
    }
}
