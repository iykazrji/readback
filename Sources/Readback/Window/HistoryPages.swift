import AppKit
import ReadbackCore
import SwiftUI

// MARK: Home

struct HomePage: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @ObservedObject var connections: Connections
    @ObservedObject var prefs: Preferences
    @ObservedObject var runtime: Runtime
    let seeAll: () -> Void
    let openSession: (SessionSummary) -> Void
    let openConnections: () -> Void
    let openVoices: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Home, top to bottom: what's reading now and what's next, the read-every-reply switches,
    /// recent sessions, and setup at a glance. One column (owner's pick), one 24 pt gap between
    /// sections, laid out as the home-plates mockup the owner signed off on 2026-11-25. Turning
    /// reading off, and saying it's off, is the sidebar's Reading card, on every page (owner,
    /// 2026-11-27).
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                NowCard(app: app, reader: reader, replies: replies)
                EveryReplyRow(prefs: prefs)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    sectionHeader("Sessions") {
                        Button(action: seeAll) {
                            HStack(spacing: 6) {
                                Text("See all")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.readback(.quiet))
                        .controlSize(.small)
                        .padding(.trailing, -ControlMetrics.smallQuietPadding)
                        .accessibilityLabel("See all")
                        .disabled(replies.all.isEmpty)
                    }
                    if replies.all.isEmpty {
                        EmptyReplies(openConnections: openConnections)
                    } else {
                        SessionsList(app: app, sessions: SessionSummary.sessions(from: replies.all), reader: reader,
                                     openSession: openSession)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    sectionHeader("Setup") { EmptyView() }
                    SetupChips(prefs: prefs, runtime: runtime, downloads: app.downloads, connections: connections,
                               openConnections: openConnections, openVoices: openVoices)
                }
            }
            .padding(.horizontal, PageMetrics.inset)
            .padding(.top, 8)
            .padding(.bottom, PageMetrics.inset)
        }
        .pageHeader(PageTitle("Home"))
    }

    /// A section title, 20 pt tall whatever sits beside it, so every section starts the same way.
    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .frame(height: 20)
    }
}

/// The first-run state: what shows up here and the one step that makes it happen.
private struct EmptyReplies: View {
    let openConnections: () -> Void

    var body: some View {
        EmptyCard(title: "No replies yet",
                  // Connecting a tool switches on reading every reply (owner, 2026-11-26); the
                  // switches just above show which tools do.
                  message: "Connect a coding tool and ask it anything. Replies show up here as they come in, and Readback reads them out loud for each tool switched on above.") {
            Button("Open Connections", action: openConnections)
        }
    }
}

/// A soft card with a headline, a line of explanation and one action.
private struct EmptyCard<Action: View>: View {
    let title: String
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}

// MARK: History

struct HistoryPage: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    /// The one session to show, from Home's "See all N replies"; nil shows every session.
    @Binding var session: SessionSummary?
    let openConnections: () -> Void
    @State private var search = ""
    @State private var tool: Tool?
    /// What the last Clear removed, while it can still be undone.
    @State private var cleared: [Reply] = []
    @State private var undoExpiry: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let saveError = replies.saveError { unsavedBar(saveError) }
                if !cleared.isEmpty { undoBar }
                if replies.all.isEmpty {
                    EmptyReplies(openConnections: openConnections)
                } else if filtered.isEmpty {
                    EmptyCard(title: noMatchTitle,
                              message: session == nil ? "Try other words, or look through every tool." : "Try other words, or show replies from every session.") {
                        Button("Show all replies") {
                            search = ""
                            tool = nil
                            session = nil
                        }
                    }
                }
                ForEach(days, id: \.day) { group in
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.replies) { reply in
                        ReplyCard(app: app, reply: reply, isPlaying: reader.isSpeaking && reader.replyID == reply.id)
                            .transition(ReplyCard.arrives(reduceMotion))
                    }
                }
            }
            .animation(Motion.spring(reduceMotion), value: filtered.map(\.id))
            .padding(.horizontal, PageMetrics.inset)
            .padding(.bottom, PageMetrics.inset)
        }
        .pageHeader(PageTitle("History") {
                // One session shows as a chip in the tool menu's place: the session already says
                // which tool. Its ✕ goes back to every session.
                if let session {
                    SessionChip(session: session) { self.session = nil }
                } else {
                    Dropdown("Show replies from", selection: $tool,
                             options: [("All tools", Tool?.none)] + Tool.allCases.map { ($0.name, Tool?.some($0)) })
                    .fixedSize()
                }
                SearchField("Search replies", text: $search)
                // Straight away, with an undo, rather than a confirmation sheet: the sheet was slow
                // to appear (0.6-1.3 s) and stood between you and something you can take back.
                // Hidden while one session shows, where it would read as "clear this session"
                // (owner approved, 2026-11-26).
                if session == nil {
                    Button("Clear", action: clear)
                        .buttonStyle(.readback(.destructive))
                        .disabled(replies.all.isEmpty)
                        .help("Remove every saved reply. You can undo it for a few seconds.")
                }
        })
        // One scroll view for every state, so the page keeps its shape with replies, none, or
        // none that match.
    }

    private func unsavedBar(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Readback couldn't save the history: \(reason). Changes shown here are lost when it quits. The full message is in Readback's log (About > Logs).")
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.sidebarCard)
        .accessibilityElement(children: .combine)
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Cleared \(cleared.count) \(cleared.count == 1 ? "reply" : "replies")")
            Spacer()
            Button("Undo", action: undo)
                .keyboardShortcut("z", modifiers: .command)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surface(radius: Radius.sidebarCard)
        .accessibilityElement(children: .contain)
    }

    /// Replies still waiting to be read stay; everything else goes, and can come back for 10 s.
    private func clear() {
        let gone = replies.clearForUndo()
        guard !gone.isEmpty else { return }
        cleared = gone
        undoExpiry?.cancel()
        undoExpiry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { cleared = [] }
        }
    }

    private func undo() {
        undoExpiry?.cancel()
        replies.restore(cleared)
        cleared = []
    }

    private var filter: ReplyFilter { ReplyFilter(session: session?.id, tool: tool, query: search) }

    private var noMatchTitle: String {
        if !filter.words.isEmpty { return "No replies match \u{201C}\(filter.words)\u{201D}" }
        if let session { return "No replies from \(session.project)" }
        if let tool { return "No replies from \(tool.name)" }
        return "Nothing here"
    }

    private var filtered: [Reply] { replies.all.filter(filter.matches) }

    private var days: [(day: Date, title: String, replies: [Reply])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.received) }
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) { title = "Today" }
            else if calendar.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
            return (day, title, grouped[day] ?? [])
        }
    }
}

/// The session History is showing: its tool mark, project and tool, and an ✕ back to every
/// session. A 34 pt plate like Home's setup chips (7 pt before the 20 pt mark), its edge a step
/// stronger because it's a choice that's in force. As the mockup the owner approved, 2026-11-26.
private struct SessionChip: View {
    let session: SessionSummary
    let showEverySession: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.radius, style: .continuous)
        let close = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 8) {
            ToolMark(tool: session.tool, size: 20)
            // In a narrow window the tool's name goes first, then the project name shortens.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(session.project)
                    Text(session.tool?.name ?? "Agent").foregroundStyle(.secondary)
                }
                .fixedSize()
                Text(session.project).truncationMode(.tail)
            }
            Button(action: showEverySession) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .background(hovering ? ControlMetrics.hoverFill(scheme) : .clear, in: close)
                    .contentShape(close)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focused)
            .keyboardFocusRing(focused, close)
            .onHover { hovering = $0 }
            .help("Show every session")
            .accessibilityLabel("Show every session")
        }
        .font(.system(size: 13))
        .lineLimit(1)
        // The ✕'s 24 pt square sits 5 pt from the edge, the same as above and below it.
        .padding(.leading, 7)
        .padding(.trailing, (ControlMetrics.height - 24) / 2)
        .frame(height: ControlMetrics.height)
        .background(ControlMetrics.fill(scheme), in: shape)
        .overlay { Hairline(shape, ControlMetrics.hoverEdge(scheme)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Showing \(session.project), \(session.tool?.name ?? "Agent")")
    }
}

// MARK: Shared

/// One reply as a card: where it came from, when, and its first lines. Click to hear it; the
/// chevron opens the whole reply, selectable, in place.
struct ReplyCard: View {
    /// A card coming or going: it grows in from a little smaller and fades.
    static func arrives(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity)
    }

    let app: AppDelegate
    let reply: Reply
    let isPlaying: Bool
    @State private var hovering = false
    @State private var expanded = false
    @State private var chevronHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { app.play(reply) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    header
                    if !expanded {
                        Text(reply.preview)
                            .font(.system(size: 13))
                            .foregroundStyle(isPlaying ? .primary : .secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, expanded ? 4 : 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(reply.title), \(time): \(reply.preview)")
            .accessibilityValue(isPlaying ? "playing" : reply.state == .waiting ? "waiting" : "")
            .accessibilityHint("Plays this reply")

            if expanded {
                Text(fullText)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 13)
            }
        }
        .surface(emphasis: isPlaying ? .active : hovering ? .hovered : .resting)
        .overlay(alignment: .topTrailing) {
            if canExpand { expandButton }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(Motion.spring(reduceMotion), value: isPlaying)
        .contextMenu {
            Button("Play") { app.play(reply) }
            if canExpand {
                Button(expanded ? "Show less" : "Show the whole reply") { toggle() }
            }
            Button("Copy text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reply.text, forType: .string)
            }
            Divider()
            Button("Remove from history", role: .destructive) { app.replies.remove(reply.id) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isPlaying {
                Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: app.reader.phase == .playing)
                    .accessibilityHidden(true)
            } else if reply.state == .waiting {
                Circle().fill(.primary).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(reply.title).font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if reply.state == .waiting && !isPlaying {
                Text("waiting").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            // Room for the chevron, which sits over the card rather than inside this button. Kept
            // on every card, chevron or not, so the times line up down the list.
            Color.clear.frame(width: 18, height: 1)
        }
    }

    private var expandButton: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 24, height: 24)
                .background(.quaternary.opacity(chevronHovering ? 1 : 0), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { chevronHovering = $0 }
        .padding(.top, 6)
        .padding(.trailing, 8)
        .help(expanded ? "Show less" : "Show the whole reply")
        .accessibilityLabel(expanded ? "Show less" : "Show the whole reply")
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expanded.toggle() }
    }

    private var time: String { reply.received.formatted(date: .omitted, time: .shortened) }

    /// Two lines hold about this much; anything longer has more to show.
    private var canExpand: Bool { reply.text.count > 140 }

    /// The reply as the agent wrote it, with its inline markdown (bold, code) drawn rather than shown.
    private var fullText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: reply.text, options: options)) ?? AttributedString(reply.text)
    }
}
