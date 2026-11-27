import AppKit
import ReadbackCore
import SwiftUI

/// A button that opens Readback's own menu of actions, with nothing in it chosen: "Turn reading
/// off" opens For 1 hour / Until 8 AM / Until I turn it back on. It looks like any other button,
/// with no chevron, because it's an action and the menu finishes the sentence (owner, 2026-11-27:
/// "let the dropdown look like a button"). The menu is the one Dropdown shows, so it opens above
/// the button when there's no room below, and the keyboard works the same.
struct MenuButton: View {
    struct Item {
        let title: String
        let action: () -> Void
    }

    let title: String
    var kind: ReadbackButtonStyle.Kind = .secondary
    var fullWidth = false
    /// Worked out when the menu opens, each title with what it does, so a pick does what its words
    /// said then ("Until 8 AM" is true at that moment, and stays the 8 AM it named).
    let items: () -> [Item]
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
        .closesItsMenu(id, presenter: presenter)
        .accessibilityLabel(title)
        .accessibilityHint("Opens a menu")
    }

    private func toggle() {
        if presenter.openID == id { presenter.close(); return }
        guard let view = anchor.view, let window = view.window else { return }
        let entries = items()
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        presenter.show(DropdownMenu(
            id: id,
            label: title,
            sections: [(title: nil, items: entries.map(\.title))],
            selected: nil,
            choose: { index in if entries.indices.contains(index) { entries[index].action() } }
        ), below: rect, in: window, reduceMotion: reduceMotion)
    }
}

/// "Turn reading off" with the menu bar's three lengths, for the sidebar and the Reading page.
/// The lengths are worked out in Core when the menu opens (`ReadingOff.Choice`).
struct TurnReadingOffButton: View {
    var fullWidth = false
    let turnOff: (ReadingOff.Choice) -> Void

    var body: some View {
        MenuButton(title: "Turn reading off", fullWidth: fullWidth) {
            ReadingOff.Choice.all(now: Date()).map { choice in .init(title: choice.title) { turnOff(choice) } }
        }
    }
}
