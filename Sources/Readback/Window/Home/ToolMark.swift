import ReadbackCore
import SwiftUI

/// A tool's mark: its glyph on a small pane of frosted glass. A top-lit gradient over a blur, a
/// one-pixel edge, and a hairline of light along the top edge; no drop shadow. The owner chose
/// frosted over plain coloured tiles on 2026-11-25 ("Frosted is better. We'd change it later if
/// it doesn't work").
struct ToolMark: View {
    let tool: Tool?
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: tool?.symbol ?? "sparkles")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(scheme == .dark ? Color.white : Color(white: 0.07))
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: glass, startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay { Hairline(shape, edge) }
            .overlay {
                // Light catching the top edge of the glass, clipped to the rounded corners.
                VStack(spacing: 0) {
                    Rectangle().fill(highlight).frame(height: 1)
                    Spacer(minLength: 0)
                }
                .padding(.top, 0.5)
                .mask(shape.inset(by: 0.5))
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }

    private var glass: [Color] {
        scheme == .dark ? [Color.white.opacity(0.22), Color.white.opacity(0.06)] : [Color.white, Color.white.opacity(0.55)]
    }
    private var edge: Color { scheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1) }
    private var highlight: Color { scheme == .dark ? Color.white.opacity(0.3) : Color.white }
}

extension Tool {
    /// The glyph Connections and Home show for the tool. Generic symbols, not the tools' logos.
    var symbol: String {
        switch self {
        case .claude: return "terminal"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "curlybraces"
        }
    }
}

/// "just now", "4 min", "3:12 PM", "Yesterday", "24 Nov": how long ago a reply came in, short.
enum ShortTime {
    static func when(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The voice picked, and what's actually heard until its engine is in: the sidebar's Voice card
/// and Home's Setup chip say the same thing.
enum VoiceSummary {
    @MainActor
    static func of(_ prefs: Preferences, _ runtime: Runtime) -> (engine: String, name: String) {
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
