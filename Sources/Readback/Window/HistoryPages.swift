import AppKit
import ReadbackCore
import SwiftUI

// MARK: Home

struct HomePage: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @ObservedObject var connections: Connections
    let seeAll: () -> Void
    let openConnections: () -> Void

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    stats
                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent replies").font(.system(size: 15, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("See all", action: seeAll)
                            .buttonStyle(.borderless)
                            .disabled(replies.all.isEmpty)
                    }
                    if replies.all.isEmpty {
                        EmptyReplies(openConnections: openConnections)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(replies.all.prefix(5)) { reply in
                                ReplyCard(app: app, reply: reply, isPlaying: reader.isActive && reader.replyID == reply.id)
                            }
                        }
                        .padding(.top, -12)   // the cards belong to the heading above them
                    }
                }
                .padding(.horizontal, PageMetrics.inset)
                .padding(.top, 8)
                .padding(.bottom, PageMetrics.inset)
        }
        .pageHeader(PageTitle("Home"))
    }

    private var stats: some View {
        HStack(spacing: 0) {
            Stat(symbol: "text.bubble", value: replies.repliesRead.formatted(), label: "Replies read",
                 help: "Replies Readback has read to you, all time")
            Stat(symbol: "clock", value: listening, label: "Listening time",
                 help: "An estimate: the words read, at about 165 words a minute")
            Stat(symbol: "text.word.spacing", value: replies.wordsHeard.formatted(), label: "Words heard",
                 help: "Words Readback has read to you, all time")
            Stat(symbol: "terminal", value: "\(connectedCount) of \(Tool.allCases.count)", label: "Tools connected",
                 help: "Claude Code, Codex and OpenCode, in Connections")
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 6)
        .surface()
    }

    private var connectedCount: Int {
        connections.rows.values.filter { $0.status == .connected }.count
    }

    /// An estimate from the words read at about 165 a minute, so it says "~".
    private var listening: String {
        let minutes = Double(replies.wordsHeard) / 165
        if replies.wordsHeard == 0 { return "0 min" }
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "~\(Int(minutes.rounded())) min" }
        return "~\((minutes / 60).formatted(.number.precision(.fractionLength(0...1)))) h"
    }
}

private struct Stat: View {
    let symbol: String
    let value: String
    let label: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.replacingOccurrences(of: "~", with: "about "))
        .accessibilityHint(help)
    }
}

/// The first-run state: what shows up here and the one step that makes it happen.
private struct EmptyReplies: View {
    let openConnections: () -> Void

    var body: some View {
        EmptyCard(title: "No replies yet",
                  message: "Connect your coding tools, then type /speak on in a Claude Code session or turn on \u{201C}Read every reply\u{201D} in Reading. Replies show up here as they come in.") {
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
    let openConnections: () -> Void
    @State private var search = ""
    @State private var tool: Tool?
    /// What the last Clear removed, while it can still be undone.
    @State private var cleared: [Reply] = []
    @State private var undoExpiry: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !cleared.isEmpty { undoBar }
                if replies.all.isEmpty {
                    EmptyReplies(openConnections: openConnections)
                } else if filtered.isEmpty {
                    EmptyCard(title: noMatchTitle, message: "Try other words, or look through every tool.") {
                        Button("Show all replies") {
                            search = ""
                            tool = nil
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
                        ReplyCard(app: app, reply: reply, isPlaying: reader.isActive && reader.replyID == reply.id)
                    }
                }
            }
            .padding(.horizontal, PageMetrics.inset)
            .padding(.bottom, PageMetrics.inset)
        }
        .pageHeader(PageTitle("History") {
                Picker("Tool", selection: $tool) {
                    Text("All tools").tag(Tool?.none)
                    ForEach(Tool.allCases) { Text($0.name).tag(Tool?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Show replies from")
                SearchField(text: $search, prompt: "Search replies")
                    .frame(width: 190)
                // Straight away, with an undo, rather than a confirmation sheet: the sheet was slow
                // to appear (0.6-1.3 s) and stood between you and something you can take back.
                Button("Clear", action: clear)
                    .disabled(replies.all.isEmpty)
                    .help("Remove every saved reply. You can undo it for a few seconds.")
        })
        // One scroll view for every state, so the page keeps its shape with replies, none, or
        // none that match.
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

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var noMatchTitle: String {
        if !query.isEmpty { return "No replies match \u{201C}\(query)\u{201D}" }
        if let tool { return "No replies from \(tool.name)" }
        return "Nothing here"
    }

    private var filtered: [Reply] {
        let query = query.lowercased()
        return replies.all.filter { reply in
            (tool == nil || reply.request.tool == tool)
                && (query.isEmpty || reply.text.lowercased().contains(query) || reply.title.lowercased().contains(query))
        }
    }

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

/// The Mac's own search field: a magnifier, a clear button, and Esc to empty it.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel(prompt)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @MainActor @objc func changed(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }
    }
}

// MARK: Shared

/// One reply as a card: where it came from, when, and its first lines. Click to hear it; the
/// chevron opens the whole reply, selectable, in place.
struct ReplyCard: View {
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
