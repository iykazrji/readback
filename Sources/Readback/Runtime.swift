import Combine
import Foundation
import ReadbackCore

/// Installs and removes the on-device voice engine: a private Python with mlx-audio, set up by
/// the copy of `uv` inside the app, all under ~/Library/Application Support/Readback/runtime.
/// Models download to the Hugging Face cache the first time they speak.
@MainActor
final class Runtime: ObservableObject {
    enum State: Equatable {
        case unsupported            // not Apple silicon: MLX can't run
        case notInstalled
        case installing(String)     // the step it's on
        case installed
        case failed(String)
    }

    /// Pinned so every install gets the same, tested engine.
    /// Adding one here updates existing installs at the next launch (see `needsUpdate`).
    static let packages = [
        "mlx-audio[tts,server]==0.6.7",
        "g2p_en==2.1.0",   // MeloTTS's pronunciation step
        "misaki[en]",
        "en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl",
    ]
    static let size = "about 1.4 GB"

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var lastLines: [String] = []

    /// Which part of an install is running, for the setup sheet's steps.
    typealias Step = EngineInstall.Step
    @Published private(set) var step: Step?
    /// Bytes an install has fetched so far: Python plus uv's download folder, measured on disk
    /// every second (uv runs without progress output, so this is the honest number there is).
    @Published private(set) var fetchedBytes: Int64 = 0
    /// What a whole install fetches before the voice model, measured 2026-11-24 with
    /// the pinned packages on Apple silicon. A meter holds short of full until the step ends.
    static let expectedFetchBytes: Int64 = 1_507_504_128   // 1,472,172 KB: Python 54,660 + uv cache 1,417,512

    /// The model the running install ends by loading; nil outside an install (an update loads none).
    @Published private(set) var installTarget: String?

    /// What Home and the player say about the natural voice, if anything (EngineInstall.nudge).
    func nudge(for prefs: Preferences) -> EngineInstall.Nudge? {
        let situation: EngineInstall.Situation
        switch state {
        case .unsupported: situation = .unsupported
        case .notInstalled: situation = .notInstalled
        case .installing: situation = installTarget == nil ? .updating : .installing
        case .installed: situation = .installed
        case .failed: situation = removeFailed ? .removalFailed : .failed
        }
        return EngineInstall.nudge(wantsNatural: prefs.engine.needsRuntime, engine: situation)
    }

    /// The running install as one meter, engine and voice together: the setup sheet and Voices
    /// both draw this, so the numbers agree wherever the person looks. Nil outside an install.
    func progress(with downloads: ModelDownloads) -> EngineInstall.Progress? {
        guard case .installing = state, let model = installTarget else { return nil }
        let download = downloads.status(for: model)
        let voice: EngineInstall.VoiceFetch
        if step != .voice {
            voice = .pending
        } else if let download {
            voice = .downloading(received: download.received)
        } else if let bytes = downloads.finished(model) {
            voice = .fetched(bytes)
        } else {
            voice = voiceWasOnDisk ? .onDisk : .pending
        }
        // The download's total is already the larger of the catalog's and what it reported.
        return EngineInstall.progress(step: step, engineFetched: fetchedBytes, engineTotal: Self.expectedFetchBytes,
                                      voice: voice, voiceTotal: download?.total ?? VoiceCatalog.downloadBytes(for: model))
    }

    /// The install's voice was in the cache when the voice step began (a reinstall).
    private var voiceWasOnDisk = false

    /// The engine kind whose model the running install loads, for "Kokoro · downloading".
    var installingEngine: EngineKind? {
        installTarget.flatMap { target in EngineKind.allCases.first { $0.model?.id == target } }
    }

    private let paths = ReadbackPaths()
    private let server: VoiceServer
    private var task: Task<Void, Never>?
    private var current: Process?
    private var meter: Task<Void, Never>?

    init(server: VoiceServer) {
        self.server = server
        refresh()
    }

    var isInstalled: Bool { state == .installed }

    /// Installed from an older package list (before MeloTTS, say): `update` adds what's new.
    var needsUpdate: Bool {
        guard state == .installed else { return false }
        do {
            let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.runtimeReceipt)) as? [String: Any]
            return receipt?["packages"] as? String != Self.packages.joined(separator: ", ")
        } catch {
            Log.error("couldn't read the engine's install receipt: \(error)")
            return false
        }
    }

    /// The last thing that failed was an update, not a fresh install, so Try again updates.
    private(set) var updateFailed = false

    /// Installs the packages an older install is missing into the existing engine. A minute
    /// at most: what's there already is left alone.
    func update(then: @escaping @MainActor () -> Void = {}) {
        guard task == nil else { return }
        lastLines = []
        updateFailed = false
        state = .installing("Updating the voice engine\u{2026}")
        task = Task {
            defer { task = nil; current = nil }
            do {
                guard let uv = AppBundle(url: Bundle.main.bundleURL).uv as URL?,
                      FileManager.default.isExecutableFile(atPath: uv.path) else {
                    throw InstallError("this copy of Readback has no uv inside it")
                }
                try await run(uv, ["pip", "install", "--python", paths.python.path] + Self.packages)
                let receipt = ["installed": ISO8601DateFormatter().string(from: Date()), "packages": Self.packages.joined(separator: ", ")]
                try JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted).write(to: paths.runtimeReceipt)
                do { try FileManager.default.removeItem(at: paths.runtime.appendingPathComponent("uv-cache")) } catch {
                    Log.error("couldn't clear the update cache: \(error)")
                }
                state = .installed
                Log.info("voice engine updated")
                then()
            } catch is CancellationError {
                readState()
            } catch where Task.isCancelled {
                // Cancelled mid-step: the step's own error (a killed process) isn't the news.
                readState()
            } catch {
                Log.error("voice engine update failed: \(error)")
                updateFailed = true
                state = .failed("\(error)")
            }
        }
    }

    /// Voices' Try again: an update again if that's what failed, else the install again, which
    /// starts at the voice when the engine is already in (EngineInstall.firstStep).
    func retry(for prefs: Preferences) {
        if removeFailed { startRemoving() } else if updateFailed { update() } else { install(for: prefs) }
    }

    /// Leaves a failed removal showing (files may be half gone, so the disk alone would read as
    /// "not installed"), until a retry of the removal works.
    func refresh() {
        if case .installing = state { return }
        if removeFailed { return }
        readState()
    }

    /// What's on disk, whatever the last state said. The engine counts as installed once its
    /// packages are in (the receipt); whether a voice's model is downloaded shows apart from that.
    private func readState() {
        #if arch(arm64)
        state = paths.engineIsInstalled ? .installed : .notInstalled
        #else
        state = .unsupported
        #endif
    }

    /// Installs the engine for the current settings (Settings' button and `readback engine install`).
    /// A custom engine with no model yet loads Kokoro, so the install always ends with a voice.
    func install(for prefs: Preferences) {
        var setup = prefs.voiceSetup
        var size = prefs.engine.model?.size
        if !setup.engine.needsRuntime || setup.model.isEmpty {
            setup = Preferences.VoiceSetup(engine: .kokoro, model: VoiceCatalog.kokoroModel, voice: prefs.kokoroVoice,
                                          lang: VoiceCatalog.lang(for: prefs.kokoroVoice, engine: .kokoro))
            size = EngineKind.kokoro.model?.size
        }
        // Asked for from the macOS voice: switch to Kokoro once it's in, unless the person picked
        // something else (the macOS voice again included) while it downloaded.
        let startedOnSystem = prefs.engine == .system
        var changedSince = false
        let watch = prefs.$engine.dropFirst().sink { _ in changedSince = true }
        install(thenLoad: setup.model, voice: setup.voice, lang: setup.lang, modelSize: size ?? "a few hundred MB") {
            watch.cancel()
            if startedOnSystem, !changedSince { prefs.engine = .kokoro }
        }
    }

    /// Installs the engine, then loads `model` once so its download happens now, not mid-reply.
    func install(thenLoad model: String, voice: String, lang: String, modelSize: String, onDone: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        lastLines = []
        fetchedBytes = 0
        installTarget = model
        voiceWasOnDisk = false
        state = .installing("Starting…")   // so anyone asking right away sees it's under way
        task = Task {
            defer {
                task = nil; current = nil; meter?.cancel(); meter = nil; step = nil; installTarget = nil
                // A Cancel blocks this model's download only while the install it ended is going.
                if let model = installingModel { Task { [server] in await server.allowDownload(of: model) } }
                installingModel = nil
            }
            do {
                guard let uv = AppBundle(url: Bundle.main.bundleURL).uv as URL?,
                      FileManager.default.isExecutableFile(atPath: uv.path) else {
                    throw InstallError("this copy of Readback has no uv inside it")
                }
                // Try again after the voice's download failed: the engine is in, so only the
                // voice is left, and the environment that works is never cleared.
                if EngineInstall.firstStep(engineInstalled: paths.engineIsInstalled) == .python {
                    try FileManager.default.createDirectory(at: paths.runtime, withIntermediateDirectories: true)
                    startMeter()
                    step = .python
                    state = .installing("Getting Python…")
                    try await run(uv, EngineInstall.venvArguments(at: paths.runtime.appendingPathComponent(".venv").path))
                    step = .engine
                    state = .installing("Installing the voice engine (\(Self.size))…")
                    try await run(uv, ["pip", "install", "--python", paths.python.path] + Self.packages)
                    meter?.cancel()
                    meter = nil
                    let receipt = ["installed": ISO8601DateFormatter().string(from: Date()), "packages": Self.packages.joined(separator: ", ")]
                    try JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted).write(to: paths.runtimeReceipt)
                    // uv's download cache is as big as the engine and useless once it's installed.
                    let cache = paths.runtime.appendingPathComponent("uv-cache")
                    do { try FileManager.default.removeItem(at: cache) } catch {
                        Log.error("couldn't clear the install cache at \(cache.path): \(error)")
                    }
                }
                fetchedBytes = max(fetchedBytes, Self.expectedFetchBytes)
                // Asked before the step shows, so the meter never counts a model that isn't there.
                voiceWasOnDisk = ModelCache().isDownloaded(model, expectedBytes: VoiceCatalog.downloadBytes(for: model))
                step = .voice
                state = .installing("Downloading the voice (\(modelSize))…")
                installingModel = model
                await server.allowDownload(of: model)
                try Task.checkCancellation()
                try await server.ensureRunning(warming: model, voice: voice, lang: lang)
                // The warm-up isn't tied to this task, so a Cancel during it lands here.
                try Task.checkCancellation()
                state = .installed
                Log.info("voice engine installed and \(model) loaded")
                onDone()
            } catch is CancellationError {
                readState()
            } catch where Task.isCancelled {
                readState()
            } catch {
                Log.error("voice engine install failed: \(error)")
                state = .failed("\(error)")
            }
        }
    }

    /// The model the install is fetching, once it gets that far.
    private var installingModel: String?

    /// Ends whatever the install is doing: an installer step, or its own voice's download (not
    /// one a reply started).
    func cancel() {
        current?.terminate()
        task?.cancel()
        if let model = installingModel { Task { [server] in await server.cancelDownload(model, evenIfNotStarted: true) } }
    }

    /// Measures what the install has fetched, every second, off the main thread.
    private func startMeter() {
        meter?.cancel()
        let folders = [paths.runtime.appendingPathComponent("python"), paths.runtime.appendingPathComponent("uv-cache")]
        meter = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let bytes = folders.reduce(Int64(0)) { $0 + Runtime.bytes(in: $1) }
                await MainActor.run { [weak self] in
                    guard let self, self.meter != nil else { return }
                    self.fetchedBytes = bytes
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Everything under `folder`, as allocated on disk; 0 when it isn't there yet.
    nonisolated static func bytes(in folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// True while `remove` runs, so anyone asking (`readback engine`) hears "removing" until it's
    /// gone, not the state from before.
    @Published private(set) var removing = false

    /// Stops the engine and deletes it, already "removing" when this returns. The one way in
    /// (Voices' Remove and `readback engine remove`), so two can't overlap. Downloaded models
    /// stay in the Hugging Face cache.
    /// The last failure was a removal: Try again removes, and Voices says it's the removal.
    @Published private(set) var removeFailed = false

    func startRemoving() {
        guard !removing else { return }
        removing = true
        removeFailed = false
        Task {
            await server.stop()
            do {
                if FileManager.default.fileExists(atPath: paths.runtime.path) {
                    try FileManager.default.removeItem(at: paths.runtime)
                }
                Log.info("voice engine removed")
                readState()
            } catch {
                // Part may be gone already (the receipt first), so say what failed rather than
                // whatever the disk now looks like.
                Log.error("couldn't remove the voice engine: \(error)")
                removeFailed = true
                state = .failed("Couldn't remove the voice engine: \(error.localizedDescription)")
            }
            removing = false
        }
    }

    struct InstallError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Runs one installer step, keeping the last lines of its output for the Settings window.
    private func run(_ tool: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = paths.runtime
        process.environment = [
            "HOME": paths.home.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            // Keep Python, uv's cache and settings inside Readback's folder, away from any of the
            // user's own Python setups, so removing Readback's engine removes all of it.
            "UV_PYTHON_INSTALL_DIR": paths.runtime.appendingPathComponent("python").path,
            "UV_CACHE_DIR": paths.runtime.appendingPathComponent("uv-cache").path,
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
            "UV_NO_PROGRESS": "1",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.lastLines = Array((self.lastLines + lines).suffix(6))
                for line in lines { Log.info("install: \(line)") }
            }
        }
        current = process
        // The handler goes on before run(), so a step that ends at once is still seen.
        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                cont.resume(throwing: error)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        try Task.checkCancellation()
        guard status == 0 else {
            throw InstallError("`uv \(arguments.first ?? "")` failed (exit \(status)): \(lastLines.last ?? "no output")")
        }
    }
}
