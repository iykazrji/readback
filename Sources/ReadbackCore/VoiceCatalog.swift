import Foundation

/// Where speech comes from.
public enum EngineKind: String, CaseIterable, Codable, Identifiable {
    /// macOS's own voices. Always there, no download.
    case system
    /// Kokoro 82M through the on-device engine: natural and very fast.
    case kokoro
    /// MeloTTS English (VITS2) through the on-device engine: the steadiest of the new ones,
    /// five English accents. Picked by ear on 2026-11-23 with Soprano and Kokoro.
    case melo
    /// Soprano 1.1 (80M) through the on-device engine: steady volume, quick, one voice.
    case soprano
    /// Qwen3-TTS 1.7B through the on-device engine: more expressive, slower to start.
    case qwen3
    /// Any other mlx-audio model, by its Hugging Face id.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "macOS voice"
        case .kokoro: return "Kokoro (natural, fast)"
        case .melo: return "MeloTTS (steady)"
        case .soprano: return "Soprano (steady, quick)"
        case .qwen3: return "Qwen3-TTS (expressive)"
        case .custom: return "Custom model"
        }
    }

    /// Needs the on-device engine (Python + mlx-audio) installed.
    public var needsRuntime: Bool { self != .system }

    /// The model it downloads the first time it speaks, roughly how big that is, and the exact
    /// bytes (measured from a full download on 2026-11-23, mlx-audio 0.6.7's file list).
    public var model: (id: String, size: String, bytes: Int64)? {
        switch self {
        case .kokoro: return (VoiceCatalog.kokoroModel, "about 355 MB", VoiceCatalog.kokoroBytes)
        case .melo: return (VoiceCatalog.meloModel, "about 650 MB", VoiceCatalog.meloBytes)
        case .soprano: return (VoiceCatalog.sopranoModel, "about 285 MB", VoiceCatalog.sopranoBytes)
        case .qwen3: return (VoiceCatalog.qwen3Model, "about 3.1 GB", VoiceCatalog.qwen3Bytes)
        default: return nil
        }
    }
}

public struct VoiceOption: Hashable, Identifiable {
    public var id: String       // what the engine is sent
    public var name: String     // what the picker shows
    public var group: String    // the picker's section
    public var lang: String     // lang_code the engine is sent
}

public enum VoiceCatalog {
    public static let kokoroModel = "mlx-community/Kokoro-82M-bf16"
    public static let qwen3Model = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
    public static let meloModel = "mlx-community/MeloTTS-English-MLX"
    public static let sopranoModel = "mlx-community/Soprano-1.1-80M-bf16"
    /// What each model's first download comes to on disk, so progress has a total from the start.
    public static let kokoroBytes: Int64 = 355_322_783
    public static let qwen3Bytes: Int64 = 3_080_138_901
    public static let meloBytes: Int64 = 645_477_125
    public static let sopranoBytes: Int64 = 283_880_888

    /// The download size of a model Readback knows, by its Hugging Face id.
    public static func downloadBytes(for model: String) -> Int64? {
        EngineKind.allCases.compactMap(\.model).first { $0.id == model }?.bytes
    }

    /// Kokoro's voices that produce audio with the packages the installer sets up
    /// (checked 2026-11-22: Japanese and Chinese voices return empty audio, so they're left out).
    /// Checked 2026-11-23 by transcribing a sentence per language back with Whisper large-v3-turbo:
    /// English, Spanish, French, Italian, Portuguese and Hindi all came back word for word.
    /// The first letter of an id is its language, the second its gender.
    public static let kokoroVoices: [VoiceOption] = {
        let ids = """
        af_heart af_alloy af_aoede af_bella af_jessica af_kore af_nicole af_nova af_river af_sarah af_sky
        am_adam am_echo am_eric am_fenrir am_liam am_michael am_onyx am_puck am_santa
        bf_alice bf_emma bf_isabella bf_lily bm_daniel bm_fable bm_george bm_lewis
        ef_dora em_alex em_santa ff_siwis hf_alpha hf_beta hm_omega hm_psi
        if_sara im_nicola pf_dora pm_alex pm_santa
        """.split(whereSeparator: \.isWhitespace).map(String.init)
        return ids.compactMap(kokoroVoice)
    }()

    public static func kokoroVoice(_ id: String) -> VoiceOption? {
        let languages: [Character: String] = [
            "a": "English (US)", "b": "English (UK)", "e": "Spanish", "f": "French",
            "h": "Hindi", "i": "Italian", "p": "Portuguese (Brazil)",
        ]
        let parts = id.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2, let langChar = parts[0].first,
              let language = languages[langChar], let genderChar = parts[0].last else { return nil }
        let gender = genderChar == "f" ? "female" : "male"
        let name = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        return VoiceOption(id: id, name: "\(name) (\(gender))", group: language, lang: String(langChar))
    }

    /// Qwen3-TTS CustomVoice speakers, from the model's config. Language is detected from the text.
    public static let qwen3Voices: [VoiceOption] = [
        ("ryan", "Ryan", "English"), ("aiden", "Aiden", "English"),
        ("serena", "Serena", "Chinese"), ("vivian", "Vivian", "Chinese"), ("uncle_fu", "Uncle Fu", "Chinese"),
        ("ono_anna", "Ono Anna", "Japanese"), ("sohee", "Sohee", "Korean"),
        ("eric", "Eric", "Chinese (Sichuan)"), ("dylan", "Dylan", "Chinese (Beijing)"),
    ].map { VoiceOption(id: $0.0, name: $0.1, group: $0.2, lang: "auto") }

    /// MeloTTS English's speakers, from the model's config (spk2id): one voice in five accents.
    public static let meloVoices: [VoiceOption] = [
        ("EN-US", "American"), ("EN-BR", "British"), ("EN-AU", "Australian"),
        ("EN_INDIA", "Indian"), ("EN-Default", "Neutral"),
    ].map { VoiceOption(id: $0.0, name: $0.1, group: "English", lang: "") }

    public static func defaultVoice(for engine: EngineKind) -> String {
        switch engine {
        case .kokoro: return "af_heart"
        case .melo: return "EN-US"
        case .qwen3: return "ryan"
        case .system, .soprano, .custom: return ""
        }
    }

    /// lang_code for a voice id on an engine.
    public static func lang(for voice: String, engine: EngineKind) -> String {
        switch engine {
        case .kokoro: return kokoroVoice(voice)?.lang ?? "a"
        case .qwen3: return "auto"
        case .system, .melo, .soprano, .custom: return ""
        }
    }
}

/// How Qwen3 reads: its CustomVoice model takes a plain-English style instruction and the usual
/// sampling settings. Measured on Ryan with the same sentences and seeds (2026-11-23):
/// "calm" barely changes pitch movement inside a sentence, but with temperature 0.6 sentences
/// come out more alike, so there's less of a mood swing from one to the next; "lively" moves
/// pitch about 40% more and reads faster. Kokoro and the macOS voices take no instruction.
public enum Delivery: String, CaseIterable, Codable, Identifiable {
    case calm, natural, lively

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .calm: return "Calm"
        case .natural: return "Natural"
        case .lively: return "Lively"
        }
    }

    static let calmInstruction = "Speak in a calm, even, neutral tone, like reading notes aloud to a colleague."
    static let livelyInstruction = "Read this in a lively, upbeat, engaged voice."
}

extension VoiceCatalog {
    /// Extra fields for the engine's speech request. Only Qwen3 takes any.
    ///
    /// Every Qwen3 request also caps how long it may talk: at a low temperature it can miss its
    /// end and run on to its 8,192-token limit (seen at 0.3: minutes of the engine at full CPU
    /// after the request had given up). It makes about 5 tokens a word, so 20 a word plus 60 is
    /// four times a normal reading and never cut a real sentence in testing.
    public static func speechOptions(model: String, delivery: Delivery, text: String) -> [String: Any] {
        guard model == qwen3Model else { return [:] }
        var options: [String: Any] = ["max_tokens": text.split(whereSeparator: \.isWhitespace).count * 20 + 60]
        switch delivery {
        case .calm:
            // Temperature 0.6 is the floor: lower ran on and swung wildly between sentences
            // (0.3 with top_k 10: 5 run-ons in 45; 0.45: 2 in 45). Keeping only the ten likeliest
            // sounds at 0.6 had none in 60, reads slower (137 against 148 words a minute) and
            // moves a little less within a sentence.
            options["instruct"] = Delivery.calmInstruction
            options["temperature"] = 0.6
            options["top_k"] = 10
        case .natural:
            break
        case .lively:
            options["instruct"] = Delivery.livelyInstruction
        }
        return options
    }
}
