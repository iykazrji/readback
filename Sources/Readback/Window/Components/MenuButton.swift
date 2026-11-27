import AppKit
import SwiftUI

/// A button that opens Readback's own menu of actions, with nothing in it chosen: "Turn reading
/// off" opens For 1 hour / Until 8 AM / Until I turn it back on. It looks like any other button,
/// with no chevron, because it's an action and the menu finishes the sentence (owner, 2026-11-27:
/// "let the dropdown look like a button"). The menu is the one Dropdown shows, so it opens above
/// the button when there's no room below, and the keyboard works the same.
struct MenuButton: View {
    let title: String
    var kind: ReadbackButtonStyle.Kind = .secondary
    var fullWidth = false
    /// Worked out when the menu opens, so "Until 8 AM" is true at that moment.
    let items: () -> [String]
    let choose: (Int) -> Void
    @ObservedObject private var presenter = DropdownPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = AnchorView.Box()
    @State private var id = UUID()

    var body: some View {
        Button(action: toggle) {
            Text(title).frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.readback(kind))
        .controlSize(.small)
        .focusEffectDisabled()   // the style draws its own neutral keyboard ring
        .background(AnchorView(box: anchor))
        .accessibilityLabel(title)
        .accessibilityHint("Opens a menu")
    }

    private func toggle() {
        if presenter.openID == id { presenter.close(); return }
        guard let view = anchor.view, let window = view.window else { return }
        let titles = items()
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        presenter.show(DropdownMenu(
            id: id,
            label: title,
            sections: [(title: nil, items: titles)],
            selected: nil,
            choose: { index in if titles.indices.contains(index) { choose(index) } }
        ), below: rect, in: window, reduceMotion: reduceMotion)
    }
}
