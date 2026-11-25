import AVFoundation
import ReadbackCore
import SwiftUI

/// The voice library: one row per engine (like superwhisper's Models library), the on-device
/// engine's install state, and the voice for the chosen engine.
struct VoicesPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var runtime: Runtime
    @ObservedObject var downloads: ModelDownloads
    let preview: () -> Void
    let downloadNow: () -> Void
    let download: (String) -> Void
    let cancelDownload: (String) -> Void
    @State private var confirmRemove = false

    private var engineIsThereOrComing: Bool {
        switch runtime.state {
        case .installing, .installed, .failed: return true
        case .notInstalled, .unsupported: return false
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(EngineKind.allCases) { engine in
                    EngineRow(engine: engine, isSelected: prefs.engine == engine, runtime: runtime,
                              downloads: downloads,
                              select: { prefs.engine = engine },
                              download: download, cancel: cancelDownload)
                }
            } header: {
                Text("Engine")
            } footer: {
                FormNote(engineNote)
            }

            // Shown whatever voice is picked once the engine is there or on its way, so Cancel and
            // Remove are always reachable.
            if prefs.engine.needsRuntime || engineIsThereOrComing {
                Section("On-device engine") {
                    runtimeRow
                    // The listed voices download from their own rows above; a custom model has none.
                    if runtime.state == .installed, prefs.engine == .custom { modelRow }
                }
            } else if runtime.state == .notInstalled {
                Section {
                    LabeledContent {
                        Button("Get it") {
                            prefs.engine = .kokoro
                            install()
                        }
                    } label: {
                        Text("Want a more natural voice?")
                        Text("Kokoro sounds like a person reading. It downloads once (about 1.8 GB in all), then runs on your Mac with no account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if prefs.engine == .custom {
                    voicePicker
                    LabeledContent("Try it") { sampleButton }
                } else if prefs.engine == .soprano {
                    // One voice: say so where the picker would be, rather than show an empty menu.
                    LabeledContent("Speaks as") {
                        HStack(spacing: 8) {
                            Text("One voice").foregroundStyle(.secondary)
                            sampleButton
                        }
                    }
                } else {
                    // The sample sits beside the voice it plays, not on a row of its own.
                    LabeledContent("Speaks as") {
                        HStack(spacing: 8) {
                            voicePicker.labelsHidden().fixedSize()
                            sampleButton
                        }
                    }
                }
                if prefs.engine == .qwen3 {
                    // Trailing, like the voice picker above it, so the rows' controls line up.
                    LabeledContent("Delivery") {
                        Picker("Delivery", selection: $prefs.qwen3Delivery) {
                            ForEach(Delivery.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityLabel("Delivery")
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                if prefs.engine == .qwen3 {
                    FormNote(deliveryNote)
                }
            }
        }
        .formStyle(CardFormStyle())
        .confirmationDialog("Remove the on-device voice engine?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { runtime.startRemoving() }
        } message: {
            Text("This deletes its Python and packages (\(Runtime.size)). Downloaded voices stay in ~/.cache/huggingface. Readback falls back to the macOS voice.")
        }
    }

    private var deliveryNote: String {
        switch prefs.qwen3Delivery {
        case .calm: return "Calm keeps every sentence at the same steady pace and tone, so long replies don't swing in mood. Play a sample to hear it."
        case .natural: return "Natural is Qwen3 as it comes: more feeling, and each sentence can come out a little different."
        case .lively: return "Lively reads with more energy and a bit faster, with more rise and fall in the voice."
        }
    }

    private var sampleButton: some View {
        Button("Play a sample", action: preview)
            .help("Reads a sentence in this voice")
    }

    /// Whether the chosen engine's model is already on this Mac, so the note can skip the download talk.
    private var modelIsHere: Bool {
        guard runtime.isInstalled, let model = prefs.engine.model else { return false }
        return ModelCache().isDownloaded(model.id, expectedBytes: model.bytes)
    }

    /// The model the chosen engine speaks with: a known one, or the custom id once there is one.
    private var chosenModel: (id: String, name: String, size: String?, bytes: Int64?)? {
        if let model = prefs.engine.model {
            return (model.id, prefs.engine.libraryName, model.size, model.bytes)
        }
        let custom = prefs.customModel.trimmingCharacters(in: .whitespaces)
        guard prefs.engine == .custom, !custom.isEmpty else { return nil }
        return (custom, custom, nil, nil)
    }

    /// The chosen model's download: how far it's got, or a button to start it now so the first
    /// reply doesn't sit through minutes of it. Nothing once it's on disk.
    @ViewBuilder private var modelRow: some View {
        if let model = chosenModel {
            if let download = downloads.status(for: model.id) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading \(model.name)")
                        Spacer()
                        Text(download.amount)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if let fraction = download.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Downloading \(model.name)")
                .accessibilityValue(download.amount)
            } else if !ModelCache().isDownloaded(model.id, expectedBytes: model.bytes) {
                let failure = downloads.failure?.model == model.id ? downloads.failure?.reason : nil
                LabeledContent {
                    Button(failure == nil ? "Download now" : "Try again", action: downloadNow)
                        .buttonStyle(.readback(.primary))
                } label: {
                    Text(failure == nil ? "\(model.name) isn't downloaded yet" : "\(model.name) didn't finish downloading")
                    Text(failure ?? downloadNote(size: model.size))
                        .font(.caption)
                        .foregroundStyle(failure == nil ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func downloadNote(size: String?) -> String {
        let amount = size.map { $0.prefix(1).uppercased() + $0.dropFirst() + ". " } ?? ""
        return "\(amount)Get it now so your first reply doesn't wait for it."
    }

    private var engineNote: String {
        switch prefs.engine {
        case .system:
            return "Uses the voices built into macOS. Nothing to download. Premium and Enhanced voices you've added in System Settings → Accessibility → Spoken Content show up here too."
        case .kokoro:
            let base = "A small model that sounds like a person reading and starts almost instantly. Runs entirely on your Mac."
            return modelIsHere ? base : base + " The first time it speaks, it downloads the voice (\(prefs.engine.model?.size ?? ""))."
        case .melo:
            let base = "The steadiest of the voices: every sentence comes out at the same pace and level, in five English accents. Runs entirely on your Mac."
            return modelIsHere ? base : base + " The first time it speaks, it downloads the voice (\(prefs.engine.model?.size ?? ""))."
        case .soprano:
            let base = "A small, quick model with steady volume and one English voice. It reads a little faster than the others, so you may like a slower speed in Reading. Runs entirely on your Mac."
            return modelIsHere ? base : base + " The first time it speaks, it downloads the voice (\(prefs.engine.model?.size ?? ""))."
        case .qwen3:
            let base = "A bigger model with more expression. It takes a second or two to start each reply. Runs entirely on your Mac."
            return modelIsHere ? base : base + " The first time it speaks, it downloads the model (\(prefs.engine.model?.size ?? "")), so that first reply can take a few minutes, unless you download it first from its row above."
        case .custom:
            return "Any text-to-speech model mlx-audio can run, by its Hugging Face id. For people who know which model they want."
        }
    }

    // MARK: Runtime

    @ViewBuilder private var runtimeRow: some View {
        switch runtime.state {
        case .unsupported:
            Text("The on-device engine needs a Mac with Apple silicon. Replies use the macOS voice.")
                .foregroundStyle(.secondary)
        case .notInstalled:
            LabeledContent {
                Button("Install") { install() }
                    .buttonStyle(.readback(.primary))
            } label: {
                Text("Not installed")
                Text(installNote).font(.caption).foregroundStyle(.secondary)
            }
        case .installing(let step):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(step)
                    Spacer()
                    Button("Cancel") { runtime.cancel() }
                }
                if let download = downloads.active {
                    // The install's last step is the voice's first download.
                    ProgressView(value: download.fraction ?? 0)
                    // Under the bar's right end, where the amount's one-width padding doesn't show.
                    Text(download.amount)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let line = runtime.lastLines.last {
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .installed:
            LabeledContent {
                Button("Remove…") { confirmRemove = true }
                    .buttonStyle(.readback(.destructive))
            } label: {
                Text("Installed")
                Text("Kept in ~/Library/Application Support/Readback/runtime.").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(runtime.removeFailed ? "The removal didn't finish" : "The install didn't finish").foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Try again") { runtime.retry(for: prefs) }
                }
            }
        }
    }

    private var installNote: String {
        let model = prefs.engine.model.map { " and the voice (\($0.size))" } ?? ""
        return "Downloads Python and mlx-audio (\(Runtime.size))\(model). Until then, replies use the macOS voice."
    }

    private func install() {
        runtime.install(for: prefs)
    }

    // MARK: Voices

    @ViewBuilder private var voicePicker: some View {
        switch prefs.engine {
        case .system:
            // Sits in the "Speaks as" row, so it takes that name rather than adding a row label of its own.
            Dropdown("Speaks as", selection: $prefs.systemVoice,
                     sections: [Dropdown.Section(title: nil, options: [.init(title: "System default", value: "")])]
                        + systemGroups.map { group in
                            Dropdown.Section(title: group.name,
                                             options: group.voices.map { .init(title: Self.label($0), value: $0.identifier) })
                        })
            .fixedSize()
        case .kokoro:
            catalogPicker(VoiceCatalog.kokoroVoices, selection: $prefs.kokoroVoice)
        case .melo:
            catalogPicker(VoiceCatalog.meloVoices, selection: $prefs.meloVoice)
        case .soprano:
            EmptyView()   // one voice; the row says so instead
        case .qwen3:
            catalogPicker(VoiceCatalog.qwen3Voices, selection: $prefs.qwen3Voice)
        case .custom:
            LabeledContent("Model") {
                TextField("Model", text: $prefs.customModel, prompt: Text("mlx-community/Kokoro-82M-bf16"))
                    .labelsHidden().frame(maxWidth: 300)
            }
            LabeledContent("Voice") {
                TextField("Voice", text: $prefs.customVoice, prompt: Text("the model's voice or speaker name"))
                    .labelsHidden().frame(maxWidth: 300)
            }
            LabeledContent("Language code") {
                TextField("Language code", text: $prefs.customLang, prompt: Text("a"))
                    .labelsHidden().frame(maxWidth: 300)
            }
        }
    }

    private func catalogPicker(_ voices: [VoiceOption], selection: Binding<String>) -> some View {
        let groups = Dictionary(grouping: voices, by: \.group)
        let order = voices.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Dropdown("Speaks as", selection: selection,
                        sections: order.map { group in
                            Dropdown.Section(title: group, options: (groups[group] ?? []).map { .init(title: $0.name, value: $0.id) })
                        })
            .fixedSize()
    }

    private var systemGroups: [(name: String, voices: [AVSpeechSynthesisVoice])] {
        let voices = SystemVoice.voices()
        let byLanguage = Dictionary(grouping: voices, by: \.language)
        return byLanguage.keys.sorted().map { code in
            (Locale.current.localizedString(forIdentifier: code) ?? code, byLanguage[code] ?? [])
        }
    }

    private static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return voice.name
        }
    }
}

/// One engine in the library: what it is, how big, how quick to start, and whether it's ready.
private struct EngineRow: View {
    let engine: EngineKind
    let isSelected: Bool
    @ObservedObject var runtime: Runtime
    @ObservedObject var downloads: ModelDownloads
    let select: () -> Void
    let download: (String) -> Void
    let cancel: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Picking the voice is the row's main action; its download control sits to the right,
            // outside it, so downloading a voice never switches to it.
            Button(action: select) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 13, weight: .medium))
                        Text(blurb).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(isSelected ? "selected" : "")
            .accessibilityHint(blurb)

            VStack(alignment: .trailing, spacing: 4) {
                Text(speed).font(.system(size: 11.5)).foregroundStyle(.secondary)
                downloadControl
                    .transition(.opacity)
                    .id(placeKind)
            }
            .animation(Motion.spring(reduceMotion), value: placeKind)
            // Its natural width: the select button beside it takes all the spare room, and without
            // this the column got squeezed until the download meter's text was cut off.
            .fixedSize()
            .frame(minWidth: 150, alignment: .trailing)
        }
    }

    // MARK: The download control

    private enum Place: Equatable {
        case plain(String)          // a caption, nothing to do
        case download(String)       // not on this Mac: a button and its size
        case waiting(String)        // another voice is downloading
        case downloading(ModelDownloads.Status)
        case failed(String)
        case downloaded
    }

    private var place: Place {
        switch engine {
        case .system: return .plain("Ready")
        case .custom: return .plain(runtime.isInstalled ? "Engine installed" : "Needs the engine")
        case .kokoro, .melo, .soprano, .qwen3:
            guard let model = engine.model else { return .plain("") }
            if !runtime.isInstalled { return .plain("Needs the engine \u{00B7} \(model.size)") }
            if let status = downloads.status(for: model.id) { return .downloading(status) }
            // Follows the cache's links to the real files: a folder with only the small config
            // files in it (a download cut short) doesn't count.
            if ModelCache().isDownloaded(model.id, expectedBytes: model.bytes) { return .downloaded }
            if downloads.failure?.model == model.id, let reason = downloads.failure?.reason { return .failed(reason) }
            if let other = downloads.active?.model, other != model.id {
                return .waiting(EngineKind.allCases.first { $0.model?.id == other }?.libraryName ?? "another voice")
            }
            return .download(model.size.replacingOccurrences(of: "about ", with: ""))
        }
    }

    /// Which kind of control the row shows, so Download → meter → Downloaded animates as a change
    /// of control, and the meter's own ticks don't.
    private var placeKind: String {
        switch place {
        case .plain: return "plain"
        case .download: return "download"
        case .waiting: return "waiting"
        case .downloading: return "downloading"
        case .failed: return "failed"
        case .downloaded: return "downloaded"
        }
    }

    @ViewBuilder private var downloadControl: some View {
        switch place {
        case .plain(let text):
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        case .download(let size):
            HStack(spacing: 8) {
                Text(size).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary)
                Button("Download") { if let id = engine.model?.id { download(id) } }
                    .controlSize(.small)
                    .help("Download \(name) now, without switching to it")
                    .accessibilityLabel("Download \(name), \(size)")
            }
        case .waiting(let other):
            HStack(spacing: 8) {
                Text("After \(other)").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Button("Download") {}
                    .controlSize(.small)
                    .disabled(true)
                    .help("One voice downloads at a time")
            }
        case .downloading(let status):
            HStack(spacing: 8) {
                // The percent under the bar's left end, the amount under its right end. The amount
                // keeps one width (DownloadAmount), so neither it nor the bar moves as it counts up.
                VStack(spacing: 3) {
                    if let fraction = status.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    HStack(spacing: 6) {
                        if let percent = status.percent { Text(percent) }
                        Spacer(minLength: 0)
                        Text(status.amount)
                    }
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                // "99%" and "3.08 of 3.08 GB" come to 110 pt at this size.
                .frame(width: 120)
                Button {
                    if let id = engine.model?.id { cancel(id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel the download and delete what it fetched")
                .accessibilityLabel("Cancel downloading \(name)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Downloading \(name)")
            .accessibilityValue(status.amount)
        case .failed(let reason):
            HStack(spacing: 8) {
                Text("Didn't finish")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .help(reason)
                Button("Retry") { if let id = engine.model?.id { download(id) } }
                    .controlSize(.small)
                    .accessibilityLabel("Retry downloading \(name)")
            }
        }
    }

    private var name: String { engine.libraryName }

    private var blurb: String {
        switch engine {
        case .system: return "Built into macOS"
        case .kokoro: return "Natural, 41 voices, 7 languages"
        case .melo: return "Steadiest, 5 English accents"
        case .soprano: return "Steady and quick, 1 English voice"
        case .qwen3: return "Most expressive, 9 speakers"
        case .custom: return "Any mlx-audio model, by its id"
        }
    }

    /// From timings on Apple silicon: Kokoro makes a sentence in about 0.1 s, Qwen3 in about 1.4 s.
    private var speed: String {
        switch engine {
        case .system, .kokoro, .melo, .soprano: return "Starts at once"
        case .qwen3: return "Starts in a second or two"
        case .custom: return "Depends on the model"
        }
    }
}

extension EngineKind {
    /// The name the voice library gives it.
    var libraryName: String {
        switch self {
        case .system: return "macOS voice"
        case .kokoro: return "Kokoro 82M"
        case .melo: return "MeloTTS"
        case .soprano: return "Soprano 80M"
        case .qwen3: return "Qwen3-TTS 1.7B"
        case .custom: return "Custom model"
        }
    }
}
