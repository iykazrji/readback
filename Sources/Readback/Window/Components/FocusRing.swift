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
