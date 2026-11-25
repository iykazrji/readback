import AppKit
import ReadbackCore
import SwiftUI

/// Readback's own dropdown, in place of the stock pop-up button (owner, 2026-11-25: every
/// dropdown a custom popover). The button looks like a secondary button with a chevron. Its
/// menu opens in a small window of its own above the main one, as a real Mac menu does: a
/// layer inside the window was drawn under the split view's columns and never showed. Keyboard:
/// Up, Down, Return, Space, Esc and type-to-jump (`MenuNavigation`). VoiceOver: the button reads
/// its label and current choice; the open menu is a list of buttons with the chosen one selected.
struct Dropdown<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
    }

    struct Section {
        let title: String?
        let options: [Option]
    }

    let label: String
    @Binding var selection: Value
    let sections: [Section]
    @ObservedObject private var presenter = DropdownPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = AnchorView.Box()
    @State private var id = UUID()

    init(_ label: String, selection: Binding<Value>, options: [(title: String, value: Value)]) {
        self.init(label, selection: selection, sections: [Section(title: nil, options: options.map { Option(title: $0.title, value: $0.value) })])
    }

    init(_ label: String, selection: Binding<Value>, sections: [Section]) {
        self.label = label
        _selection = selection
        self.sections = sections
    }

    private var options: [Option] { sections.flatMap(\.options) }
    private var selectedTitle: String { options.first { $0.value == selection }?.title ?? "" }
    private var isOpen: Bool { presenter.openID == id }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Text(selectedTitle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(Motion.spring(reduceMotion), value: isOpen)
            }
            .padding(.trailing, -2)   // the icon side 2 pt tighter than the text side, so it looks centred
        }
        .buttonStyle(.readback(.secondary))
        .background(AnchorView(box: anchor))
        // On the button itself, so VoiceOver's press still opens it (a replacement element
        // made with .accessibilityElement(children: .ignore) had no action).
        .accessibilityLabel(label)
        .accessibilityValue(selectedTitle)
        .accessibilityHint("Opens a menu")
    }

    private func toggle() {
        if isOpen { presenter.close(); return }
        guard let view = anchor.view, let window = view.window else { return }
        let all = options
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        presenter.show(DropdownMenu(
            id: id,
            label: label,
            sections: sections.map { ($0.title, $0.options.map(\.title)) },
            selected: all.firstIndex { $0.value == selection },
            choose: { index in if all.indices.contains(index) { selection = all[index].value } }
        ), below: rect, in: window, reduceMotion: reduceMotion)
    }
}

/// The button's place on screen, for the menu to open under.
private struct AnchorView: NSViewRepresentable {
    final class Box { weak var view: NSView? }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

struct DropdownMenu {
    let id: UUID
    let label: String
    let sections: [(title: String?, items: [String])]
    let selected: Int?
    let choose: (Int) -> Void
}

/// Shows one dropdown menu at a time, in a borderless window attached above its parent.
@MainActor
final class DropdownPresenter: ObservableObject {
    static let shared = DropdownPresenter()

    @Published private(set) var openID: UUID?
    private var panel: MenuWindow?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func show(_ menu: DropdownMenu, below anchor: NSRect, in parent: NSWindow, reduceMotion: Bool) {
        close()
        let size = MenuPanel.size(for: menu, minWidth: anchor.width)
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let gap: CGFloat = 4, margin: CGFloat = 8
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        var opensUp = false
        if origin.y < visible.minY + margin {   // no room below: open above the button
            origin.y = anchor.maxY + gap
            opensUp = true
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)

        let window = MenuWindow(contentRect: NSRect(origin: origin, size: size))
        window.contentView = NSHostingView(rootView: MenuPanel(menu: menu, opensUp: opensUp, reduceMotion: reduceMotion,
                                                               close: { [weak self] in self?.close() }))
        parent.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        panel = window
        openID = menu.id

        // A click anywhere outside the menu closes it, and does nothing else, as a menu does.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, event.window !== panel else { return event }
            self.close()
            return nil
        }
        // Switching to another app, or the menu losing focus some other way, closes it too.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let panel {
            let parent = panel.parent
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            parent?.makeKey()
        }
        panel = nil
        openID = nil
    }
}

private final class MenuWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true   // a menu floats; this is the window's own shadow, not a button's
        level = .popUpMenu
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
}

private struct MenuPanel: View {
    let menu: DropdownMenu
    let opensUp: Bool
    let reduceMotion: Bool
    let close: () -> Void
    @State private var navigation: MenuNavigation
    @State private var shown = false
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var voiceOverOn: Int?

    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 22
    static let padding: CGFloat = 5
    static let maxHeight: CGFloat = 320

    init(menu: DropdownMenu, opensUp: Bool, reduceMotion: Bool, close: @escaping () -> Void) {
        self.menu = menu
        self.opensUp = opensUp
        self.reduceMotion = reduceMotion
        self.close = close
        _navigation = State(initialValue: MenuNavigation(titles: menu.sections.flatMap(\.items), selected: menu.selected))
    }

    static func size(for menu: DropdownMenu, minWidth: CGFloat) -> NSSize {
        let font = NSFont.systemFont(ofSize: 12.5)
        let header = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let widestItem = menu.sections.flatMap(\.items).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let widestHeader = menu.sections.compactMap(\.title).map { ($0 as NSString).size(withAttributes: [.font: header]).width }.max() ?? 0
        // An item: 5 pt menu padding, 6 pt row padding, the 12 pt check and a 6 pt gap on the left,
        // 6 + 5 on the right (and a little air); a heading: 5 + 10 on each side.
        let needed = max(ceil(widestItem) + 52, ceil(widestHeader) + 32)
        let rows = CGFloat(menu.sections.reduce(0) { $0 + $1.items.count })
        let headers = CGFloat(menu.sections.filter { $0.title != nil }.count)
        return NSSize(width: max(minWidth, needed),
                      height: min(rows * rowHeight + headers * headerHeight + padding * 2, maxHeight))
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(menu.sections.enumerated()), id: \.offset) { sectionIndex, section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .frame(height: Self.headerHeight, alignment: .bottomLeading)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(Array(section.items.enumerated()), id: \.offset) { itemIndex, title in
                            row(title, index: offset(of: sectionIndex) + itemIndex)
                        }
                    }
                }
                .padding(Self.padding)
            }
            .onAppear {
                focused = true
                if let h = navigation.highlighted { scroller.scrollTo(h, anchor: .center); voiceOverOn = h }
                withAnimation(Motion.pop(reduceMotion)) { shown = true }
            }
            .onChange(of: navigation.highlighted) { _, h in
                if let h { withAnimation(.easeOut(duration: 0.1)) { scroller.scrollTo(h) } }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(WindowColors.hairline, lineWidth: 0.5))
        .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: opensUp ? .bottomLeading : .topLeading)
        .opacity(shown ? 1 : 0)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { navigation.moveDown(); return .handled }
        .onKeyPress(.upArrow) { navigation.moveUp(); return .handled }
        .onKeyPress(.return) { chooseHighlighted(); return .handled }
        .onKeyPress(.space) { chooseHighlighted(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(phases: .down) { press in
            guard let character = press.characters.first, character.isLetter || character.isNumber else { return .ignored }
            navigation.type(character, at: ProcessInfo.processInfo.systemUptime)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(menu.label)
    }

    private func offset(of section: Int) -> Int {
        menu.sections.prefix(section).reduce(0) { $0 + $1.items.count }
    }

    private func row(_ title: String, index: Int) -> some View {
        let highlighted = navigation.highlighted == index
        return Button {
            menu.choose(index)
            close()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(menu.selected == index ? 1 : 0)
                    .frame(width: 12)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight)
            .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .onHover { if $0 { navigation.highlight(index) } }
        .accessibilityAddTraits(menu.selected == index ? .isSelected : [])
        .accessibilityFocused($voiceOverOn, equals: index)
    }

    private func chooseHighlighted() {
        guard let index = navigation.highlighted else { return }
        menu.choose(index)
        close()
    }
}
