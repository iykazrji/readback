import ReadbackCore
import SwiftUI

/// Colours and sizes, matched by eye to superwhisper's recording window: a near-black card,
/// a darker inset bar along the bottom, grey labels, and keycap chips for shortcuts.
enum Theme {
    static let panel = Color(red: 0.165, green: 0.165, blue: 0.172)
    static let bar = Color(red: 0.125, green: 0.125, blue: 0.133)
    static let border = Color.white.opacity(0.10)
    static let textActive = Color.white.opacity(0.95)
    static let textDim = Color.white.opacity(0.38)
    static let label = Color.white.opacity(0.52)
    static let keycap = Color.white.opacity(0.13)
    static let keycapText = Color.white.opacity(0.82)
    static let hover = Color.white.opacity(0.08)
    static let dot = Color.white.opacity(0.22)
    static let dotFilled = Color.white.opacity(0.75)
    /// The natural-voice line: brighter than `textDim`, which is too faint to read at 11.5 pt on
    /// the panel (proposed in the 2026-11-26 mockup the owner signed off).
    static let nudge = Color.white.opacity(0.62)

    static let width: CGFloat = 470
    static let radius: CGFloat = 16
    static let barRadius: CGFloat = 10
    static let textHeight: CGFloat = 64
}

struct PlayerView: View {
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @ObservedObject var downloads: ModelDownloads
    @ObservedObject var runtime: Runtime
    @ObservedObject var prefs: Preferences
    var onClose: () -> Void
    /// Stops a voice's download (the player's Cancel while a reply waits for its voice).
    var onCancelDownload: (String) -> Void = { _ in }
    /// The natural-voice line's link: opens Voices, where Install says the size first.
    var openVoices: () -> Void = {}
    /// Plays a reply from the list, switching away from whatever is playing.
    var onPlay: (Reply) -> Void
    var onHover: (Bool) -> Void
    /// Called while the panel is dragged, with the drag's translation so far, and when it ends.
    var onDrag: (_ translation: CGSize, _ ended: Bool) -> Void
    /// Resets by itself when a drag ends or is cancelled, even when onEnded never fires
    /// (a release off-screen, for one), so the next drag never starts from stale numbers.
    @GestureState private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if replies.showingList {
                ReplyList(replies: replies, playingID: reader.isActive ? reader.replyID : nil,
                          moving: reader.phase == .playing, onPlay: onPlay)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 12).padding(.top, 4)
            }
            if reader.isActive {
                nowPlaying
            } else {
                Text(replies.all.isEmpty ? "Replies show up here once a connected tool sends one." : "Pick a reply to hear it.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            ControlBar(reader: reader, replies: replies, onClose: onClose)
                .padding(6)
        }
        .frame(width: Theme.width)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        // Drag the panel from anywhere; buttons still take plain clicks (a drag needs movement).
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { onDrag($0.translation, false) }
        )
        .onChange(of: dragging) { _, isDragging in
            if !isDragging { onDrag(.zero, true) }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .onHover(perform: onHover)
        .environment(\.colorScheme, .dark)
        .tint(.primary)   // no accent anywhere (owner's black-and-white look, 2026-11-25)
    }

    @ViewBuilder private var nowPlaying: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                textArea
                counter
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            Group {
                if reader.phase == .preparing && reader.progress == 0, let download = downloads.status(for: reader.voiceModel) {
                    // A voice's first download: minutes for Qwen3's 3 GB, so show how far it's got.
                    HStack(spacing: 10) {
                        DotProgress(progress: download.fraction ?? 0, pulsing: download.fraction == nil)
                            .frame(height: 3)
                        // Two pieces, not "… · amount": the amount keeps one width by padding its
                        // left end (DownloadAmount), which would show as a wide gap after a "·".
                        // One width means the bar beside it never shrinks or grows as it counts.
                        HStack(spacing: 8) {
                            Text("Downloading the voice")
                            Text(download.amount)
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Downloading the voice")
                        .accessibilityValue(download.amount)
                        CancelDownloadButton { onCancelDownload(download.model) }
                    }
                    .frame(height: 16)
                    .accessibilityElement(children: .contain)
                } else if reader.phase == .preparing && reader.progress == 0 {
                    // A first load can take a while; say what's happening.
                    HStack(spacing: 8) {
                        DotProgress(progress: 0, pulsing: true).frame(width: 28, height: 3)
                        Text("Getting the voice ready…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 16)
                } else {
                    Scrubber(progress: reader.progress, pulsing: reader.phase == .preparing,
                             steps: max(1, reader.chunks.count), onSeek: reader.seek(to:))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 3)

            voiceNudge
        }
    }

    /// One quiet line while a reply reads in the macOS voice because the engine isn't in: where
    /// the person hears the flat voice is where they learn there's another (owner, 2026-11-26).
    @ViewBuilder private var voiceNudge: some View {
        let failed: Bool = { if case .failed = reader.phase { return true }; return false }()
        if !failed, let nudge = runtime.nudge(for: prefs) {
            HStack(spacing: 8) {
                switch nudge {
                case .getIt:
                    Text("Reading with the macOS voice")
                    Spacer(minLength: 8)
                    NudgeLink(title: "Get the natural voice", action: openVoices)
                case .downloading:
                    Text("macOS voice until the natural voice is in")
                    Spacer(minLength: 8)
                    Text(runtime.progress(with: downloads)?.amount ?? "")
                        .foregroundStyle(Theme.textActive)
                case .didntFinish:
                    Text("Reading with the macOS voice")
                    Spacer(minLength: 8)
                    NudgeLink(title: "Try again", action: openVoices)
                }
            }
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.nudge)
            .lineLimit(1)
            .frame(height: 20)
            .padding(.horizontal, 18)
            // Even gaps above (to the dots) and below (to the bar), seen in the 2026-11-26 check.
            .padding(.top, 2)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private var textArea: some View {
        if case .failed(let message) = reader.phase {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity, minHeight: Theme.textHeight, maxHeight: Theme.textHeight, alignment: .topLeading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(reader.chunks.enumerated()), id: \.offset) { index, chunk in
                            ChunkText(text: chunk, isCurrent: index == reader.current, isReady: reader.phase != .preparing)
                                .id(index)
                        }
                    }
                    .padding(.trailing, 34)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Theme.textHeight)
                .mask(EdgeFade())
                // The text follows the reading on its own; letting it take the mouse would
                // also swallow drags, so the whole panel stays draggable.
                .allowsHitTesting(false)
                .onChange(of: reader.current) { _, index in
                    // With Reduce Motion on, the text jumps to the next sentence instead of gliding.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .top) }
                }
                .onAppear { proxy.scrollTo(reader.current, anchor: .top) }
            }
        }
    }

    @ViewBuilder private var counter: some View {
        if reader.chunks.count > 1 {
            Text("\(min(reader.current + 1, reader.chunks.count))/\(reader.chunks.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textDim)
                .padding(.top, 2)
        }
    }
}

private struct ChunkText: View {
    let text: String
    let isCurrent: Bool
    let isReady: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 14.5, weight: .medium))
            .lineSpacing(2)
            .foregroundStyle(isCurrent ? (isReady ? Theme.textActive : Theme.label) : Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeOut(duration: 0.2), value: isCurrent)
    }
}

/// Fades the text out at the top and bottom edges of the scroll area.
private struct EdgeFade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.82),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// The progress line doubles as a seek bar: click anywhere on it to jump there, or drag
/// along it. A knob shows under the pointer while hovering or dragging; the jump happens
/// when the drag ends, so scrubbing doesn't stutter the audio.
struct Scrubber: View {
    let progress: Double
    let pulsing: Bool
    let steps: Int
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let shown = dragFraction ?? progress
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                DotProgress(progress: shown, pulsing: pulsing && dragFraction == nil)
                    .frame(height: 3)
                Circle()
                    .fill(Theme.textActive)
                    .frame(width: 9, height: 9)
                    .offset(x: CGFloat(shown) * width - 4.5)
                    .opacity(hovering || dragFraction != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = Self.clamp($0.location.x / width) }
                    .onEnded {
                        dragFraction = nil
                        onSeek(Self.clamp($0.location.x / width))
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 16)
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

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// The dotted line from superwhisper's recorder, used here as a progress bar.
/// Dots fill from the left as the reply plays; while the voice is being made they pulse.
struct DotProgress: View {
    let progress: Double
    let pulsing: Bool

    var body: some View {
        // Opacity comes from the clock while pulsing, so it can't get stuck part-way
        // the way a repeatForever animation can when it's switched off.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let opacity = pulsing ? 0.35 + 0.65 * (0.5 + 0.5 * sin(t * .pi / 0.8)) : 1
            dots.opacity(opacity)
        }
        .accessibilityHidden(true)   // the Scrubber around it is the accessible control
    }

    private var dots: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 5
            let count = max(1, Int(geo.size.width / spacing))
            let filled = Int((Double(count) * progress).rounded(.down))
            HStack(spacing: spacing - 2) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? Theme.dotFilled : Theme.dot)
                        .frame(width: 2, height: 2)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct ControlBar: View {
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    var onClose: () -> Void
    /// Stops a voice's download (the player's Cancel while a reply waits for its voice).
    var onCancelDownload: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 2) {
            // The title gives way first: the controls and chips keep their full size.
            ListToggle(reader: reader, replies: replies)

            Spacer(minLength: 8)

            Group {
                IconButton(symbol: "arrow.counterclockwise", help: "Start over", action: reader.restart)
                IconButton(symbol: "backward.fill", help: "Back a sentence", action: reader.back)
                IconButton(symbol: playSymbol, help: playHelp, size: 13, action: reader.togglePlay)
                IconButton(symbol: "forward.fill", help: "Next sentence", action: reader.forward)
            }
            .disabled(isFailed || !reader.isActive)
            .fixedSize()

            ChipButton(help: "Playback speed", action: reader.cycleSpeed) {
                Text(speedLabel)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.keycapText)
                    .frame(minWidth: 30)
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .background(Theme.keycap, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .fixedSize()
            .padding(.leading, 4)

            ChipButton(help: "Stop and close (esc)", action: onClose) {
                HStack(spacing: 6) {
                    Text("Close")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.label)
                    Text("esc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.keycapText)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Theme.keycap, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .fixedSize()
            .padding(.leading, 6)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(Theme.bar, in: RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous))
    }

    private var isFailed: Bool {
        if case .failed = reader.phase { return true }
        return false
    }

    /// While a sentence is still being made, the button shows what happens once it's ready.
    private var playSymbol: String {
        switch reader.phase {
        case .playing: return "pause.fill"
        case .preparing: return reader.startsPlaying ? "pause.fill" : "play.fill"
        default: return "play.fill"
        }
    }

    private var playHelp: String {
        switch reader.phase {
        case .playing: return "Pause"
        case .preparing: return reader.startsPlaying ? "Pause" : "Play"
        case .finished: return "Play again"
        default: return "Play"
        }
    }

    private var speedLabel: String {
        let s = reader.speed
        return s == s.rounded() ? "\(Int(s))×" : "\(s.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 11
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.keycapText : Theme.textDim)
                .frame(width: 26, height: 26)
                .background(hovering && isEnabled ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDim())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ChipButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(3)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDim())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The bar's left side: what's playing, and the switch for the list of replies. The chevron
/// points up because the list opens above; "+2" counts replies waiting their turn.
private struct ListToggle: View {
    @ObservedObject var reader: Reader
    @ObservedObject var replies: Replies
    @State private var hovering = false

    var body: some View {
        Button {
            replies.showingList.toggle()
        } label: {
            HStack(spacing: 6) {
                Waveform(playing: reader.phase == .playing, height: 12)
                    .foregroundStyle(Theme.label)
                    .frame(width: 18)
                // "Codex · readback" when it fits; just the project when it doesn't, which tells
                // two agents apart better than "Codex · rea…" does.
                ViewThatFits(in: .horizontal) {
                    titleText(title).fixedSize()
                    titleText(shortTitle).fixedSize()
                    titleText(shortTitle)
                }
                if replies.waitingCount > 0 {
                    Text("+\(replies.waitingCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.keycapText)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(Theme.keycap, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .fixedSize()
                }
                Image(systemName: replies.showingList ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize()
            }
            .padding(.horizontal, 4)
            .frame(height: 26)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDim())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(replies.showingList ? "Hide recent replies" : "Show recent replies")
        .accessibilityLabel(replies.showingList ? "Hide recent replies" : "Show recent replies")
        .accessibilityValue([reader.isActive ? title : nil, replies.waitingCount > 0 ? "\(replies.waitingCount) waiting" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private var title: String { reader.isActive ? reader.title : "Recent replies" }

    private var shortTitle: String {
        title.components(separatedBy: " · ").last ?? title
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// Recent replies, newest first. The playing one is marked; ones waiting their turn have a dot.
/// Clicking a row plays it now.
struct ReplyList: View {
    @ObservedObject var replies: Replies
    let playingID: UUID?
    /// Whether the playing reply is being read right now, rather than paused.
    var moving = true
    let onPlay: (Reply) -> Void

    var body: some View {
        let recent = Array(replies.all.prefix(20))
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 2) {
                if recent.isEmpty {
                    Text("No replies yet.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(recent) { reply in
                    ReplyRow(reply: reply, isPlaying: reply.id == playingID, moving: moving) { onPlay(reply) }
                }
            }
        }
        .frame(height: min(CGFloat(max(recent.count, 1)) * 52 + 4, 236))
    }
}

private struct ReplyRow: View {
    let reply: Reply
    let isPlaying: Bool
    var moving = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                // A fixed slot even when there's no mark, so every row's text lines up.
                ZStack { mark }.frame(width: 14, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reply.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isPlaying ? Theme.textActive : Theme.label)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.when(reply.received))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textDim)
                    }
                    Text(reply.preview)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isPlaying ? Theme.textActive : Theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isPlaying ? Theme.keycap : (hovering ? Theme.hover : .clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDim())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("\(reply.title), \(Self.when(reply.received)): \(reply.preview)")
        .accessibilityValue(isPlaying ? "playing" : reply.state == .waiting ? "waiting" : "")
        .accessibilityHint("Plays this reply")
    }

    /// "just now", "12 min", then the time today, then the day: steadier to scan than
    /// "2 sec. ago", which is stale the moment the list opens.
    static func when(_ date: Date, now: Date = Date()) -> String { ShortTime.when(date, now: now) }

    @ViewBuilder private var mark: some View {
        if isPlaying {
            Waveform(playing: moving, height: 10)
                .foregroundStyle(Theme.textActive)
        } else if reply.state == .waiting {
            Circle().fill(Theme.dotFilled).frame(width: 6, height: 6)
        }
    }
}

/// Plain buttons that dim a touch while held, so a click on the player feels taken.
private struct PressDim: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// The player's Cancel for a voice download: a quiet text button that brightens under the pointer.
/// The natural-voice line's link: text and an arrow that brighten and nudge right under the pointer.
private struct NudgeLink: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(hovering ? Theme.textActive : Theme.textActive.opacity(0.9))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.nudge)
                    .offset(x: hovering && !reduceMotion ? 2 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Opens Voices")
    }
}

private struct CancelDownloadButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button("Cancel", action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering ? Theme.textActive : Theme.label)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { hovering = $0 }
            .help("Stop the download and delete what it fetched")
            .accessibilityLabel("Cancel the voice download")
    }
}
