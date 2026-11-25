import ReadbackCore
import SwiftUI

/// Home's top card: what's being read, with the reader's controls, and the replies waiting behind
/// it as a stack that peeks out under the card. Only there while something is reading or paused;
/// with nothing reading it's gone, not a "Nothing reading" placeholder (spec, Piece 3). The owner
/// signed off this layout in the home-plates mockup on 2026-11-25.
struct NowCard: View {
    let app: AppDelegate
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @State private var open = false
    /// Whether the card is up. It follows the reader, but stays through the instant between one
    /// reply stopping and the next starting, so playing another reply doesn't drop the card and
    /// bring it back (that bounced the whole page, owner, 2026-11-25).
    @State private var shown = false
    @State private var hideTask: Task<Void, Never>?
    /// The card's real height, measured, so the stack starts exactly under it.
    @State private var cardHeight: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// Waiting replies in the order they'll play.
    private var waiting: [Reply] { replies.all.filter { $0.state == .waiting }.reversed() }
    private var playing: Reply? { reader.replyID.flatMap { id in replies.all.first { $0.id == id } } }

    var body: some View {
        Group {
            if shown { content }
        }
        .onAppear { shown = reader.isSpeaking }
        .onChange(of: reader.isSpeaking) { _, speaking in
            hideTask?.cancel()
            if speaking {
                if !shown { withAnimation(Motion.reveal(reduceMotion)) { shown = true } }
            } else {
                hideTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, !reader.isSpeaking else { return }
                    withAnimation(Motion.reveal(reduceMotion)) { shown = false }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if true {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .top) {
                    stack
                    card.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                }
                // Folded, the stack takes only the card and its two 8 pt peeks.
                .frame(height: open ? nil : cardHeight + CGFloat(min(waiting.count, 2)) * 8, alignment: .top)
                if !waiting.isEmpty { toggle }
            }
            .animation(Motion.reveal(reduceMotion), value: open)
            .animation(Motion.reveal(reduceMotion), value: waiting.map(\.id))
            .onChange(of: waiting.isEmpty) { _, empty in if empty { open = false } }
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: The card

    private var card: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayPauseButton(playing: reader.phase == .playing, action: reader.togglePlay)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(project).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Waveform(playing: reader.phase == .playing, height: 12)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 12) {
                    LineScrubber(progress: reader.progress, steps: max(1, reader.chunks.count), onSeek: reader.seek(to:))
                    Text("\(min(reader.current + 1, max(reader.chunks.count, 1)))/\(max(reader.chunks.count, 1))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                        .accessibilityLabel("Sentence \(reader.current + 1) of \(reader.chunks.count)")
                }
                .padding(.top, 4)
            }
            IconPlate("arrow.counterclockwise", help: "Start over", action: reader.restart)
        }
        .padding(16)
        .background(nowFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay { Hairline(RoundedRectangle(cornerRadius: Radius.card, style: .continuous), WindowColors.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now reading")
    }

    /// Solid, so the stack under it never shows through.
    private var nowFill: Color { scheme == .dark ? Color(white: 0.18) : Color(white: 0.985) }

    private var project: String {
        guard let reply = playing else { return reader.title }
        return SessionSummary.sessions(from: [reply]).first?.project ?? reader.title
    }

    private var subtitle: String {
        let tool = playing.flatMap { $0.source.flatMap(Tool.init(source:))?.name }
        let first = playing.map { firstLine($0.text) } ?? reader.title
        return [tool, first].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: The stack

    /// Folded, the first two waiting replies peek 8 pt each under the card; open, they're rows.
    private var stack: some View {
        VStack(spacing: open ? 6 : 0) {
            ForEach(Array(waiting.enumerated()), id: \.element.id) { index, reply in
                WaitingRow(reply: reply, place: index, play: { app.play(reply) })
                    .opacity(open ? 1 : (index < 2 ? 1 : 0))
                    .scaleEffect(open ? 1 : (index == 0 ? 0.94 : 0.88), anchor: .bottom)
                    .offset(y: open ? 0 : CGFloat(index + 1) * 8 - CGFloat(index) * 46)
                    .allowsHitTesting(open)
                    .zIndex(Double(-index))
            }
        }
        .padding(.top, open ? cardHeight + 6 : cardHeight - 46)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(!open)
    }

    private var toggle: some View {
        HStack {
            Spacer()
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(open ? "Hide" : "\(waiting.count) waiting")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.readback(.quiet))
            .controlSize(.small)
            .accessibilityLabel(open ? "Hide the waiting replies" : "Show the \(waiting.count) waiting replies")
        }
        .padding(.top, 6)
    }

    private func firstLine(_ text: String) -> String {
        SpeechText.clean(text).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// One waiting reply in the unfolded stack: its tool, project and place in line. Clicking plays it now.
private struct WaitingRow: View {
    let reply: Reply
    let place: Int
    let play: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tool = reply.source.flatMap(Tool.init(source:))
        Button(action: play) {
            HStack(spacing: 10) {
                ToolMark(tool: tool, size: 20)
                Text(SessionSummary.sessions(from: [reply]).first?.project ?? "")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(tool?.name ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(place == 0 ? "next" : "\(place + 1) in line").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { Hairline(RoundedRectangle(cornerRadius: 12, style: .continuous), WindowColors.hairline) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .keyboardFocusRing(focused, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityLabel("Play \(tool?.name ?? "reply") in \(SessionSummary.sessions(from: [reply]).first?.project ?? "") now")
    }

    private var fill: Color {
        if scheme == .dark { return Color(white: hovering ? 0.215 : 0.185 - Double(min(place, 1)) * 0.02) }
        return Color(white: hovering ? 1 : 0.985 - Double(min(place, 1)) * 0.02)
    }
}

/// The play/pause button on Home: a 38 pt circle in the solid plate, no shadow.
struct PlayPauseButton: View {
    let playing: Bool
    let action: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .offset(x: playing ? 0 : 1.5)   // a triangle looks centred a little to the right
                .foregroundStyle(ControlMetrics.primaryText(scheme))
                .frame(width: 38, height: 38)
                .background(ControlMetrics.primaryFill(scheme), in: Circle())
        }
        .buttonStyle(PressScale())
        .focusEffectDisabled()
        .focused($focused)
        .keyboardFocusRing(focused, Circle())
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private struct PressScale: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(Motion.spring(reduceMotion), value: configuration.isPressed)
        }
    }
}

/// A plain line you can click or drag along to move the reading, with a knob under the pointer.
/// The jump happens when the drag ends, so scrubbing doesn't stutter the voice (as the player's).
struct LineScrubber: View {
    let progress: Double
    let steps: Int
    let onSeek: (Double) -> Void
    @State private var drag: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let shown = drag ?? progress
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(WindowColors.hairline).frame(height: 3)
                Capsule().fill(Color.primary).frame(width: CGFloat(shown) * width, height: 3)
                Circle().fill(Color.primary).frame(width: 10, height: 10)
                    .offset(x: CGFloat(shown) * width - 5)
                    .opacity(hovering || drag != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag = min(max($0.location.x / width, 0), 1) }
                    .onEnded { drag = nil; onSeek(min(max($0.location.x / width, 0), 1)) }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(progress * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(steps)
            switch direction {
            case .increment: onSeek(min(1, progress + step))
            case .decrement: onSeek(max(0, progress - step))
            @unknown default: break
            }
        }
    }
}
