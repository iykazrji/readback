import AppKit
import ReadbackCore
import SwiftUI

/// Home's Sessions: one row per recent session (project, its latest line, tool, how many replies
/// and when), newest first. The play button plays the session's newest reply; clicking the row
/// opens its replies in place. Laid out as the owner signed off on 2026-11-25: the mark's top is
/// level with the top of the project name, the chevron and play button centre on the mark, and
/// the tool · replies · time line sits under the content.
struct SessionsList: View {
    let app: AppDelegate
    let sessions: [SessionSummary]
    @ObservedObject var reader: Reader
    @State private var openID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { WindowColors.hairline.frame(height: 1).padding(.leading, Spacing.l) }
                SessionRow(app: app, session: session, reader: reader, open: openID == session.id) {
                    withAnimation(reveal) { openID = openID == session.id ? nil : session.id }
                }
            }
        }
        .surface()
        // A row's highlight can only round where the card itself rounds.
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // No system focus highlight anywhere in the list: it drew its own rounded block over a
        // clicked session. Rows show Readback's neutral ring for keyboard focus instead.
        .focusEffectDisabled()
    }

    /// Opening a session eases out with no bounce, so the rows below don't wobble.
    private var reveal: Animation { Motion.reveal(reduceMotion) }
}

private struct SessionRow: View {
    let app: AppDelegate
    let session: SessionSummary
    @ObservedObject var reader: Reader
    let open: Bool
    let toggle: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    /// From the top of the row's content to the top of the project name's capitals, at 13 pt in a
    /// 20 pt line: where the mark's top edge goes.
    private static let capTop: CGFloat = 5
    private static let markSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10, height: 10)
                        .padding(.top, Self.capTop + (Self.markSize - 10) / 2)
                    ToolMark(tool: session.tool, size: Self.markSize)
                        .padding(.top, Self.capTop)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(session.project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            if !session.unheard.isEmpty { UnheardBadge(count: session.unheard.count) }
                        }
                        .frame(height: 20)
                        Text(firstLine(session.newest.text))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(meta)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the play button, which sits over the row's trailing edge.
                    Color.clear.frame(width: ControlMetrics.smallHeight, height: 1)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // No system focus highlight (it drew a separate rounded block after a click); a
            // neutral ring inside the row when it's reached by keyboard instead.
            .focusEffectDisabled()
            .focused($focused)
            .overlay { KeyboardRingInside(focused: focused) }
            .overlay(alignment: .topTrailing) {
                IconPlate("play.fill", help: playHelp) { app.play(session.newest) }
                    .padding(.top, 14 + Self.capTop + (Self.markSize - ControlMetrics.smallHeight) / 2)
                    .padding(.trailing, Spacing.l)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(session.project), \(meta)")
            .accessibilityValue(open ? "open" : "closed")
            .accessibilityHint("Shows this session's replies")

            if open {
                VStack(spacing: 6) {
                    ForEach(session.replies.prefix(10)) { reply in
                        SessionReply(app: app, reply: reply, unheard: session.unheard.contains { $0.id == reply.id },
                                     playing: reader.isSpeaking && reader.replyID == reply.id)
                    }
                }
                // Lines up with the project name: chevron 10 + 12 + mark 30 + 12.
                .padding(.leading, Spacing.l + 10 + 12 + Self.markSize + 12)
                .padding(.trailing, Spacing.l)
                .padding(.bottom, 14)
                .transition(.opacity)
            }
        }
        // One highlight for the whole session, header and replies together, square-edged inside
        // the card, and kept while it's open so it reads as one piece (owner, 2026-11-25: the
        // header alone lit up as a separate rounded block above its replies).
        .background { Rectangle().fill(open || hovering ? WindowColors.rowHighlight : .clear) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var meta: String {
        let tool = session.tool?.name ?? "Agent"
        let replies = session.count == 1 ? "1 reply" : "\(session.count) replies"
        return "\(tool) · \(replies) · \(ShortTime.when(session.newest.received))"
    }

    private var playHelp: String { "Play \(session.project)'s newest reply" }

    private func firstLine(_ text: String) -> String {
        SpeechText.clean(text).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// One reply inside an open session. Every row keeps the unheard dot's room, so the text starts
/// on one edge whether or not it has the dot. Clicking plays it.
private struct SessionReply: View {
    let app: AppDelegate
    let reply: Reply
    let unheard: Bool
    let playing: Bool
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { app.play(reply) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Color.primary).frame(width: 6, height: 6).opacity(unheard ? 1 : 0)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                if playing { Waveform(playing: true, height: 10) }
                Text(SpeechText.clean(reply.text).split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(ShortTime.when(reply.received)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .keyboardFocusRing(focused, RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityLabel(unheard ? "Unheard reply" : "Reply")
        .accessibilityHint("Plays it now")
    }
}

/// "2 unheard": a small solid plate (the owner tried frosted and kept solid, 2026-11-25).
struct UnheardBadge: View {
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("\(count) unheard")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(ControlMetrics.primaryText(scheme))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(ControlMetrics.primaryFill(scheme), in: Capsule())
    }
}

/// Readback's neutral keyboard ring drawn just inside a row, for rows that sit flush inside a
/// clipped card where a ring outside would be cut off. Shows only for keyboard focus.
private struct KeyboardRingInside: View {
    let focused: Bool
    @State private var viaKeyboard = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .strokeBorder(ControlMetrics.focusRing(scheme), lineWidth: 2)
            .opacity(focused && viaKeyboard ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: focused) { _, now in viaKeyboard = now && NSApp.currentEvent?.type == .keyDown }
    }
}
