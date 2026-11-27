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
    /// Turn other apps' sound down while a reply plays. Off unless switched on: it needs macOS's
    /// System Audio Recording permission (see OtherAudioLowerer).
    @Published var lowerOtherAudio: Bool { didSet { defaults.set(lowerOtherAudio, forKey: "lowerOtherAudio") } }
    /// Read every reply from a tool, whatever its sessions say. Published here for the Reading
    /// page; saved through `switches`, which the CLI reads too.
    @Published private(set) var autoRead: [Tool: Bool]
    /// When "read replies out loud" comes back on, while it's off (`Date.distantFuture`: when the
    /// person turns it on). Published for Home, Reading and the menu bar; saved through `switches`.
    @Published private(set) var readingOffUntil: Date?
    /// The muted threads (SessionSummary keys), for Home's rows and the player.
    @Published private(set) var muted: Set<String>
    let switches = ReadingSwitches(defaults: .standard)

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
        lowerOtherAudio = defaults.bool(forKey: "lowerOtherAudio")
        cueSound = defaults.string(forKey: "cueSound") ?? "Pop"
        let switches = ReadingSwitches(defaults: .standard)
        autoRead = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, switches.readsEveryReply($0)) })
        readingOffUntil = switches.readingOff()
        muted = Set(switches.mutedThreads)
    }

    /// Read from the saved settings each time, not the published copy: `readback connect` can
    /// switch it on from another process while the app runs (review 2026-11-26).
    func readsEveryReply(_ tool: Tool) -> Bool { switches.readsEveryReply(tool) }

    /// Brings the published switches (the Reading page, Home's row) up to the saved settings.
    /// Called when the window opens and when those pages appear.
    func reloadReadingSwitches() {
        let saved = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, switches.readsEveryReply($0)) })
        if saved != autoRead { autoRead = saved }
        let off = switches.readingOff()
        if off != readingOffUntil { readingOffUntil = off }
        let mutedNow = Set(switches.mutedThreads)
        if mutedNow != muted { muted = mutedNow }
    }

    // MARK: Reading off, and muted threads

    var isReadingOff: Bool { switches.readingOff() != nil }

    /// Off until `until` (`Date.distantFuture`: until turned back on), or back on with nil.
    func setReadingOff(until: Date?) {
        switches.setReadingOff(until: until)
        readingOffUntil = switches.readingOff()
        Log.info(until.map { $0 == .distantFuture ? "reading switched off until turned back on" : "reading switched off until \($0)" }
                 ?? "reading switched back on")
    }

    func isMuted(_ thread: String) -> Bool { switches.isMuted(thread) }

    func setMuted(_ thread: String, _ on: Bool) {
        switches.setMuted(thread, on)
        muted = Set(switches.mutedThreads)
        Log.info("a thread was \(on ? "muted" : "unmuted")")
    }

    func setReadsEveryReply(_ tool: Tool, _ on: Bool) {
        autoRead[tool] = on
        switches.setReadsEveryReply(tool, on)
        Log.info("auto-read for \(tool.name) is \(on ? "on" : "off")")
    }

    /// A tool was just connected: a new connection reads every reply, unless the switch was set
    /// before (ReadingSwitches.applyNewConnection).
    func connected(_ tool: Tool, isNew: Bool) {
        guard switches.applyNewConnection(of: tool, isNew: isNew) else { return }
        autoRead[tool] = true
        Log.info("auto-read for \(tool.name) is on: a new connection")
    }

    func isSessionOn(_ id: String) -> Bool { switches.isSessionOn(id) }

    /// /speak on or off: off mutes the thread, on lifts a mute and reads it (ReadingSwitches.setSession).
    func setSession(_ id: String, _ on: Bool) {
        switches.setSession(id, on)
        muted = Set(switches.mutedThreads)
        Log.info("read-aloud \(on ? "on" : "muted") for a session")
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
            // Trimmed here, once, so what's shown and what's loaded are the same model.
            return VoiceSetup(engine: .custom, model: customModel.trimmingCharacters(in: .whitespaces),
                              voice: customVoice.trimmingCharacters(in: .whitespaces),
                              lang: customLang.trimmingCharacters(in: .whitespaces))
        }
    }
}
