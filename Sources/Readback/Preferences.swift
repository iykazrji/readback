import Foundation
import ReadbackCore

/// Every setting, saved to UserDefaults the moment it changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var engine: EngineKind { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    @Published var kokoroVoice: String { didSet { defaults.set(kokoroVoice, forKey: "voice.kokoro") } }
    @Published var qwen3Voice: String { didSet { defaults.set(qwen3Voice, forKey: "voice.qwen3") } }
    /// MeloTTS's accent, by its speaker id (EN-US, EN-BR, ...).
    @Published var meloVoice: String { didSet { defaults.set(meloVoice, forKey: "voice.melo") } }
    /// How Qwen3 reads; calm unless changed.
    @Published var qwen3Delivery: Delivery { didSet { defaults.set(qwen3Delivery.rawValue, forKey: "voice.qwen3.delivery") } }
    /// An AVSpeechSynthesisVoice identifier; "" means the system's default voice.
    @Published var systemVoice: String { didSet { defaults.set(systemVoice, forKey: "voice.system") } }
    @Published var customModel: String { didSet { defaults.set(customModel, forKey: "custom.model") } }
    @Published var customVoice: String { didSet { defaults.set(customVoice, forKey: "custom.voice") } }
    @Published var customLang: String { didSet { defaults.set(customLang, forKey: "custom.lang") } }
    /// Seconds the player stays after a reply ends; 0 keeps it until it's closed.
    @Published var hideAfter: Double { didSet { defaults.set(hideAfter, forKey: "hideAfter") } }
    @Published var escCloses: Bool { didSet { defaults.set(escCloses, forKey: "escCloses") } }
    /// A macOS sound (by name, as in /System/Library/Sounds) played before a reply starts reading
    /// by itself, a second ahead of the voice; "" for none.
    @Published var cueSound: String { didSet { defaults.set(cueSound, forKey: "cueSound") } }
    /// A reply that should be read arrives while another is playing: wait its turn, or cut in.
    @Published var switchToNewReplies: Bool { didSet { defaults.set(switchToNewReplies, forKey: "switchToNewReplies") } }
    /// Read every reply from a tool, whatever its sessions say.
    @Published private(set) var autoRead: [Tool: Bool]

    /// Kokoro on Apple silicon: natural and quick. Until its engine is installed, replies use the
    /// macOS voice (see AppDelegate.speaker()). Intel Macs can't run the engine.
    static var defaultEngine: EngineKind {
        #if arch(arm64)
        return .kokoro
        #else
        return .system
        #endif
    }

    private init() {
        engine = EngineKind(rawValue: defaults.string(forKey: "engine") ?? "") ?? Self.defaultEngine
        kokoroVoice = defaults.string(forKey: "voice.kokoro") ?? VoiceCatalog.defaultVoice(for: .kokoro)
        qwen3Voice = defaults.string(forKey: "voice.qwen3") ?? VoiceCatalog.defaultVoice(for: .qwen3)
        meloVoice = defaults.string(forKey: "voice.melo") ?? VoiceCatalog.defaultVoice(for: .melo)
        qwen3Delivery = Delivery(rawValue: defaults.string(forKey: "voice.qwen3.delivery") ?? "") ?? .calm
        systemVoice = defaults.string(forKey: "voice.system") ?? ""
        customModel = defaults.string(forKey: "custom.model") ?? ""
        customVoice = defaults.string(forKey: "custom.voice") ?? ""
        customLang = defaults.string(forKey: "custom.lang") ?? "a"
        hideAfter = defaults.object(forKey: "hideAfter") as? Double ?? 4
        escCloses = defaults.object(forKey: "escCloses") as? Bool ?? true
        switchToNewReplies = defaults.bool(forKey: "switchToNewReplies")
        cueSound = defaults.string(forKey: "cueSound") ?? "Pop"
        autoRead = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, UserDefaults.standard.bool(forKey: "autoRead.\($0.rawValue)")) })
    }

    func setAutoRead(_ tool: Tool, _ on: Bool) {
        autoRead[tool] = on
        defaults.set(on, forKey: "autoRead.\(tool.rawValue)")
        Log.info("auto-read for \(tool.name) is \(on ? "on" : "off")")
    }

    // MARK: Sessions

    /// Sessions that turned read-aloud on for themselves (Claude Code's /speak on), newest last.
    private var sessionsOn: [String] {
        get { defaults.stringArray(forKey: "sessionsOn") ?? [] }
        set { defaults.set(Array(newValue.suffix(500)), forKey: "sessionsOn") }
    }

    func isSessionOn(_ id: String) -> Bool { sessionsOn.contains(id) }

    func setSession(_ id: String, _ on: Bool) {
        var list = sessionsOn.filter { $0 != id }
        if on { list.append(id) }
        sessionsOn = list
        Log.info("read-aloud \(on ? "on" : "off") for session \(id)")
    }

    // MARK: What to speak with

    struct VoiceSetup: Equatable {
        var engine: EngineKind
        var model: String
        var voice: String
        var lang: String
        /// Only Qwen3 does anything with it.
        var delivery: Delivery = .natural
    }

    var voiceSetup: VoiceSetup {
        switch engine {
        case .system:
            return VoiceSetup(engine: .system, model: "", voice: systemVoice, lang: "")
        case .kokoro:
            return VoiceSetup(engine: .kokoro, model: VoiceCatalog.kokoroModel, voice: kokoroVoice,
                              lang: VoiceCatalog.lang(for: kokoroVoice, engine: .kokoro))
        case .melo:
            return VoiceSetup(engine: .melo, model: VoiceCatalog.meloModel, voice: meloVoice, lang: "")
        case .soprano:
            return VoiceSetup(engine: .soprano, model: VoiceCatalog.sopranoModel, voice: "", lang: "")
        case .qwen3:
            return VoiceSetup(engine: .qwen3, model: VoiceCatalog.qwen3Model, voice: qwen3Voice, lang: "auto",
                              delivery: qwen3Delivery)
        case .custom:
            return VoiceSetup(engine: .custom, model: customModel, voice: customVoice, lang: customLang)
        }
    }
}
