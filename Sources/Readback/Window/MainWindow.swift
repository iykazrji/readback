import AppKit
import ReadbackCore
import SwiftUI

enum MainSection: String, Hashable, CaseIterable {
    case home, history, voices, reading, connections, about

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .voices: return "Voices"
        case .reading: return "Reading"
        case .connections: return "Connections"
        case .about: return "About"
        }
    }

    /// The colour of the section's icon tile.
    var tint: Color {
        switch self {
        case .home: return .orange
        case .history: return .blue
        case .voices: return .pink
        case .reading: return .green
        case .connections: return .gray
        case .about: return .gray
        }
    }

    /// The glyph on the section's icon tile.
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .voices: return "waveform"
        case .reading: return "speaker.wave.2.fill"
        case .connections: return "point.3.filled.connected.trianglepath.dotted"
        case .about: return "info.circle.fill"
        }
    }
}

/// Readback's window: Home, History and the settings, in a sidebar like superwhisper's.
/// While it's open Readback is a regular app (Dock icon, Cmd-Tab, app menu); closing it puts
/// Readback back in the menu bar only.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private unowned let app: AppDelegate
    private let navigation = Navigation()

    @MainActor final class Navigation: ObservableObject {
        @Published var section: MainSection = .home
        /// The first-run sheet that connects the coding tools.
        @Published var showingSetup = false
    }

    init(app: AppDelegate) {
        self.app = app
        let root = MainView(app: app, navigation: navigation)
        // Moves itself when a title bar drag starts: macOS 27.2 drops the system's (see the class).
        window = SelfDraggingWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        // Translucent: each pane draws the desktop blurred under its own tint (GlassBackground).
        // The owner chose this on 2026-11-25, after an opaque window on 2026-11-24.
        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty toolbar keeps the title bar at its toolbar height, so the window buttons sit
        // level with each page's title. Without the sidebar button there'd be no toolbar at all,
        // and the bar would shrink to a plain title bar.
        window.toolbar = NSToolbar(identifier: "ReadbackMain")
        window.toolbarStyle = .unifiedCompact
        window.title = "Readback"
        window.minSize = NSSize(width: 760, height: 500)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 580))
        window.center()
        window.setFrameAutosaveName("ReadbackMain")
        super.init()
        window.delegate = self
    }

    func show(_ section: MainSection?) {
        if let section { navigation.section = section }
        app.runtime.refresh()
        app.connections.refresh()
        NSApp.setActivationPolicy(.regular)
        app.panelPolicyFlipped(to: "regular")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window on Home with the setup sheet over it (first launch).
    func showSetup() {
        show(.home)
        navigation.showingSetup = true
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app once the window is gone.
        NSApp.setActivationPolicy(.accessory)
        app.panelPolicyFlipped(to: "accessory")
    }
}

struct MainView: View {
    let app: AppDelegate
    @ObservedObject var navigation: MainWindowController.Navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            Sidebar(app: app, reader: app.reader, replies: app.replies, prefs: app.prefs, selection: $navigation.section)
                // The sidebar is always there; a button to hide it is one more thing by the window buttons.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(200)
        } detail: {
            // A new page fades in and settles 6 pt up; a plain fade with Reduce Motion.
            ZStack(alignment: .topLeading) {
                detail
                    .id(navigation.section)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            .animation(Motion.spring(reduceMotion), value: navigation.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(GlassBackground(.underWindowBackground, tint: WindowColors.pageTint))
                // The page title sits in the title bar's row, level with the window buttons.
                .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 760, minHeight: 500)
        .containerBackground(.clear, for: .window)   // the panes draw their own glass
        // Every plain button in the window gets Readback's own look (Components/Buttons.swift).
        .buttonStyle(.readback(.secondary))
        // Anything still stock (a small spinner, a text selection) draws in black and white, not
        // the system accent: the owner's black-and-white look, 2026-11-25.
        .tint(.primary)
        .sheet(isPresented: $navigation.showingSetup) {
            SetupSheet(connections: app.connections, replies: app.replies, runtime: app.runtime, downloads: app.downloads, prefs: app.prefs,
                       openConnections: { navigation.section = .connections })
                .tint(.primary)
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.section {
        case .home:
            HomePage(app: app, reader: app.reader, replies: app.replies, connections: app.connections,
                     seeAll: { navigation.section = .history }, openConnections: { navigation.section = .connections })
        case .history:
            HistoryPage(app: app, reader: app.reader, replies: app.replies,
                        openConnections: { navigation.section = .connections })
        case .voices:
            Page(title: "Voices") { VoicesPage(prefs: app.prefs, runtime: app.runtime, downloads: app.downloads,
                                                  preview: app.preview, downloadNow: app.downloadVoice, download: app.download, cancelDownload: app.cancelDownload) }
        case .reading:
            Page(title: "Reading") { ReadingSettings(prefs: app.prefs, reader: app.reader, resetPosition: app.resetPanelPosition) }
        case .connections:
            Page(title: "Connections") { ConnectionSettings(connections: app.connections, replies: app.replies) }
        case .about:
            Page(title: "About") { AboutSettings() }
        }
    }
}

/// A settings page: its title in a bar along the top, the form scrolling under it.
struct Page<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            // The window's material shows through instead of the form's own grey.
            .scrollContentBackground(.hidden)
            .pageHeader(PageTitle(title))
    }
}

/// Space between the window's edge and a page's content, shared so pages line up when you switch.
enum PageMetrics {
    /// Matches where a grouped Form puts its sections, so card pages and settings pages agree.
    static let inset: CGFloat = Spacing.xl
    /// The page's title bar: the window buttons' 38 pt row and room below it, with the title at
    /// its bottom, so titles sit clear of the window's top edge. (Owner: the title was too close
    /// to the top, 2026-11-25.)
    /// 61 since the controls grew to 34 pt (2026-11-25): the title row is one control tall on
    /// every page, and this keeps the title's centre 36 pt from the top, where it sat before.
    static let headerHeight: CGFloat = 61
}

extension View {
    /// Puts `header` in a bar along the top that the page scrolls under, behind a frosted
    /// material that fades out downwards: content blurs and dims as it slides under the title,
    /// with no hard line. Drawn here on every macOS version: the system's own soft scroll edge
    /// (`scrollEdgeEffectStyle`, macOS 26) didn't show under a header that isn't a toolbar
    /// (checked on macOS 27.2).
    func pageHeader<Header: View>(_ header: Header) -> some View {
        modifier(PageHeader(header: header))
    }
}

/// The header bar and its frosting. The frosting shows only once something has scrolled under
/// the title: over the translucent window a second material at rest reads as a dark band.
private struct PageHeader<Header: View>: ViewModifier {
    let header: Header
    @State private var scrolled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 2
            } action: { _, isScrolled in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { scrolled = isScrolled }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header.background(alignment: .top) {
                    Rectangle()
                        .fill(.bar)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 0.62),
                                                     .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: PageMetrics.headerHeight + 22)
                        .opacity(scrolled ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct PageTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        // One control tall whether or not the page has controls, so titles sit at the same height everywhere.
        .frame(height: ControlMetrics.height)
        .padding(.horizontal, PageMetrics.inset)
        .padding(.bottom, Spacing.s)
        .frame(height: PageMetrics.headerHeight, alignment: .bottom)
    }
}

private struct Sidebar: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @ObservedObject var prefs: Preferences
    @Binding var selection: MainSection
    /// The row under the pointer, which gets a soft fill of its own.
    @State private var hovered: MainSection?
    @FocusState private var focused: Bool

    private static let groups: [[MainSection]] = [[.home, .history], [.voices, .reading, .connections]]
    private static var order: [MainSection] { groups.flatMap { $0 } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                    ForEach(group, id: \.self) { section in row(section) }
                }
            }
            .onHover { inside in if !inside { hovered = nil } }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            // The old list moved with the arrow keys; this keeps that.
            .onMoveCommand { direction in
                guard let at = Self.order.firstIndex(of: selection) else { return }
                switch direction {
                case .up: selection = Self.order[max(at - 1, 0)]
                case .down: selection = Self.order[min(at + 1, Self.order.count - 1)]
                default: break
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                NowPlayingCard(app: app, reader: reader, prefs: prefs, runtime: app.runtime, showVoices: { selection = .voices })
                Button {
                    selection = .about
                } label: {
                    HStack(spacing: 6) {
                        Text("Readback").font(.system(size: 13, weight: .semibold))
                        Text(Bundle.main.version).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                }
                .buttonStyle(SidebarTileStyle(isSelected: selection == .about, radius: Radius.sidebarCard))
                .accessibilityLabel("About Readback")
                .accessibilityValue(Bundle.main.version)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity)
        .background(GlassBackground(.sidebar, tint: WindowColors.sidebarTint).ignoresSafeArea())
    }

    private func row(_ section: MainSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                IconTile(symbol: section.symbol, color: section.tint)
                Text(section.title)
                    // One weight whether selected or not: a heavier selected title reflowed the
                    // row. The row's fill says which one is selected.
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if section == .history, replies.waitingCount > 0 {
                    Text("\(replies.waitingCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("\(replies.waitingCount) waiting to be read")
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(SidebarRowStyle())
        .background {
            if isSelected || hovered == section {
                RowHighlight(selected: isSelected)
            }
        }
        .onHover { inside in
            if inside { hovered = section } else if hovered == section { hovered = nil }
        }
        .accessibilityLabel(section.title)
        .accessibilityValue(section == .history && replies.waitingCount > 0 ? "\(replies.waitingCount) waiting" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's fill: the selected row's, or a softer one under the pointer. No movement between
/// rows (the moving "sweep" highlight it replaced felt glitchy, 2026-11-25).
private struct RowHighlight: View {
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .fill(selected ? WindowColors.rowSelected : WindowColors.rowHighlight)
    }
}

/// A section's icon: a white glyph on a small coloured tile, as in System Settings and superwhisper.
private struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: Radius.iconTile, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Sidebar rows give a little when pressed.
private struct SidebarRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The sidebar's small card: what's playing (with Stop), or which voice is set (click to change it).
private struct NowPlayingCard: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var prefs: Preferences
    /// Until the on-device engine is in, a neural choice is read with the macOS voice.
    @ObservedObject var runtime: Runtime
    let showVoices: () -> Void

    var body: some View {
        // Only while it's being read: a finished or failed reply sitting in the player isn't "Reading".
        if reader.isSpeaking {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: reader.phase == .playing)
                        .accessibilityHidden(true)
                    Text(reader.phase == .paused ? "Paused" : "Reading").font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer()
                    Button("Stop") { app.stopEverything() }
                        .buttonStyle(.readback(.quiet))
                        .font(.system(size: 11))
                }
                Text(reader.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Self.height, alignment: .top)
            .surface(radius: Radius.sidebarCard, emphasis: .active)
        } else {
            Button(action: showVoices) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(voice.engine).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(voice.name.isEmpty ? " " : voice.name)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .topLeading)
            }
            .buttonStyle(SidebarTileStyle(isSelected: false, radius: Radius.sidebarCard))
            .help("Change the voice")
            .accessibilityLabel("Voice: \(voice.engine)\(voice.name.isEmpty ? "" : ", \(voice.name)")")
            .accessibilityHint("Opens Voices")
        }
    }

    /// The same height reading or idle, so the sidebar doesn't jump when a reply starts.
    private static let height: CGFloat = 72

    private var voice: (engine: String, name: String) {
        // The voice picked, and what's actually heard until its engine is in.
        if prefs.engine.needsRuntime, !runtime.isInstalled {
            return (prefs.engine.title.components(separatedBy: " (").first ?? prefs.engine.title, "macOS voice for now")
        }
        switch prefs.engine {
        case .system: return ("macOS voice", prefs.systemVoice.isEmpty ? "System default" : (SystemVoice.voices().first { $0.identifier == prefs.systemVoice }?.name ?? ""))
        case .kokoro: return ("Kokoro", VoiceCatalog.kokoroVoice(prefs.kokoroVoice)?.name ?? prefs.kokoroVoice)
        case .melo: return ("MeloTTS", VoiceCatalog.meloVoices.first { $0.id == prefs.meloVoice }?.name ?? prefs.meloVoice)
        case .soprano: return ("Soprano", "")
        case .qwen3: return ("Qwen3-TTS", VoiceCatalog.qwen3Voices.first { $0.id == prefs.qwen3Voice }?.name ?? prefs.qwen3Voice)
        case .custom: return ("Custom model", prefs.voiceSetup.model)
        }
    }
}

/// The sidebar's bottom tiles: a card surface that lifts on hover and press.
private struct SidebarTileStyle: ButtonStyle {
    let isSelected: Bool
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, isSelected: isSelected, radius: radius)
    }

    private struct Tile: View {
        let configuration: Configuration
        let isSelected: Bool
        let radius: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .surface(radius: radius, emphasis: configuration.isPressed || isSelected ? .active : hovering ? .hovered : .resting, on: .sidebar)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// A note under a settings section: small, grey, left-aligned (the Form default centres
/// multi-line footers and draws them full size).
struct FormNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
