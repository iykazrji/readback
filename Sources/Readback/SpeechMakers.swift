import AVFoundation
import Foundation
import ReadbackCore

/// Turns one chunk of text into an audio file.
protocol SpeechMaker {
    /// File extension for what `make` writes.
    var fileExtension: String { get }
    /// Gets ready (starts a server, loads a model). Called once per reply.
    func prepare() async throws
    func make(_ text: String, to file: URL) async throws
}

enum SpeechError: Error, CustomStringConvertible {
    case noAudio
    case timedOut
    case serverDidNotStart
    case badResponse(Int, String)
    case notInstalled
    case downloadFailed(String)
    case downloadCancelled

    var description: String {
        switch self {
        case .downloadFailed(let reason): return "the voice didn't finish downloading (\(reason)). Check your internet connection and try again"
        case .downloadCancelled: return "its voice download was cancelled"
        case .noAudio: return "the voice made no audio"
        case .timedOut: return "the voice took too long"
        case .serverDidNotStart: return "the voice engine didn't start within 90 seconds"
        case .badResponse(let code, let body):
            // mlx-audio answers {"detail": "..."}; show that sentence, not the JSON around it.
            let detail = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["detail"] as? String
            return detail.map { "the voice engine said: \($0)" } ?? "the voice engine answered HTTP \(code)"
        case .notInstalled: return "the on-device voice engine isn't installed"
        }
    }
}

// MARK: macOS voice

/// macOS's own speech voices, written to a file so the player can pause, seek and change speed.
struct SystemVoice: SpeechMaker {
    let voiceID: String
    var fileExtension: String { "caf" }

    func prepare() async throws {}

    func make(_ text: String, to file: URL) async throws {
        let job = await SystemVoiceJob(text: text, voiceID: voiceID, file: file)
        try await job.run()
    }

    /// The voices worth listing: the user's languages first, best quality first.
    static func voices() -> [AVSpeechSynthesisVoice] {
        let preferred = Locale.preferredLanguages.map { String($0.prefix(2)) } + ["en"]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in preferred.contains(String(voice.language.prefix(2))) }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.language, -$0.quality.rawValue, $0.name) < ($1.language, -$1.quality.rawValue, $1.name) }
    }
}

/// One AVSpeechSynthesizer write. The synthesizer reports the end either with an empty buffer
/// or through its delegate, depending on the OS, so both are handled; a timeout covers neither.
@MainActor
private final class SystemVoiceJob: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let utterance: AVSpeechUtterance
    private let file: URL
    private var output: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var wroteFrames: AVAudioFramePosition = 0

    init(text: String, voiceID: String, file: URL) {
        utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }
        self.file = file
        super.init()
        synthesizer.delegate = self
    }

    func run() async throws {
        let seconds = 20 + Double(utterance.speechString.count) / 8
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            synthesizer.write(utterance) { [weak self] buffer in
                MainActor.assumeIsolated { self?.received(buffer) }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.finish(SpeechError.timedOut)
            }
        }
    }

    private func received(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            finish(nil)
            return
        }
        do {
            if output == nil {
                output = try AVAudioFile(forWriting: file, settings: pcm.format.settings,
                                         commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try output?.write(from: pcm)
            wroteFrames += AVAudioFramePosition(pcm.frameLength)
        } catch {
            finish(error)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        output = nil   // closes the file
        if let error {
            synthesizer.stopSpeaking(at: .immediate)
            continuation.resume(throwing: error)
        } else if wroteFrames == 0 {
            continuation.resume(throwing: SpeechError.noAudio)
        } else {
            continuation.resume()
        }
    }
}

// MARK: On-device engine

/// A model on the on-device engine (mlx-audio's OpenAI-style server).
struct NeuralVoice: SpeechMaker {
    let server: VoiceServer
    let model: String
    let voice: String
    let lang: String
    var delivery: Delivery = .natural
    var fileExtension: String { "wav" }

    func prepare() async throws {
        try await server.ensureRunning(warming: model, voice: voice, lang: lang)
    }

    func make(_ text: String, to file: URL) async throws {
        try await server.synthesize(text, model: model, voice: voice, lang: lang, to: file,
                                    options: VoiceCatalog.speechOptions(model: model, delivery: delivery, text: text))
    }
}

/// Runs mlx-audio's server from Readback's own runtime on 127.0.0.1:8909, one per app.
actor VoiceServer {
    static let port = 8909
    private let paths = ReadbackPaths()
    private let downloads: ModelDownloads
    private var child: Process?
    private var warmed: Set<String> = []
    /// One download per model, however many callers want it (the launch warm-up and a reply can overlap).
    private var downloading: [String: Task<Void, Error>] = [:]
    private var downloadProcesses: [String: Process] = [:]
    /// Models whose download the person cancelled; checked when the download ends or before it starts.
    private var cancelled: Set<String> = []
    /// Downloads in the order they were asked for; the first one runs.
    private var downloadQueue: [String] = []
    private var base: URL { URL(string: "http://127.0.0.1:\(Self.port)")! }

    init(downloads: ModelDownloads) {
        self.downloads = downloads
    }

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: paths.voiceServer.path) }

    /// The last model change asked for. An actor gives way at every await, so without this a
    /// launch warm-up, a sample and Download now could interleave: two downloads sharing one
    /// handle, or one caller restarting the engine while another is loading.
    private var transition: Task<Void, Error>?

    /// Starts the engine with `model` loaded, after any change asked for earlier is done.
    func ensureRunning(warming model: String, voice: String, lang: String) async throws {
        let earlier = transition
        let mine = Task {
            _ = await earlier?.result
            try await self.load(model, voice: voice, lang: lang)
        }
        transition = mine
        try await mine.value
    }

    private func load(_ model: String, voice: String, lang: String) async throws {
        guard isInstalled else { throw SpeechError.notInstalled }
        // A model that isn't on disk yet downloads first, with progress, instead of inside the
        // engine's first request where nothing can see how far it's got.
        if !warmed.contains(model) { try await ensureDownloaded(model) }
        // One model at a time. The engine never hands a model's memory back (MLX keeps it in its
        // own cache, even after the model is unloaded), so a switch restarts it. Measured
        // 2026-11-23, once loaded: Kokoro 850 MB, Soprano 730 MB, MeloTTS 3.1 GB, Qwen3 3.5 GB.
        if !warmed.isEmpty, !warmed.contains(model), child?.isRunning == true {
            Log.info("switching the voice engine to \(model): restarting it to free the last model's memory")
            await stop(downloads: false)
        }
        // An engine this copy didn't start (left by a crash or an earlier copy) may hold every
        // model it ever loaded; it goes, and a fresh one starts.
        if child == nil, await isUp() { await stopStray() }
        if !(await isUp()) {
            warmed = []
            if child?.isRunning != true { try start() }
            var up = false
            for _ in 0..<180 {
                if await isUp() { up = true; break }
                if child?.isRunning == false { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard up else { throw SpeechError.serverDidNotStart }
        }
        if !warmed.contains(model) {
            // The first request loads (and on first use downloads) the model.
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("readback-warm-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: scratch) }
            try await synthesize("Ready.", model: model, voice: voice, lang: lang, to: scratch, timeout: 1800)
            warmed.insert(model)
        }
    }

    func synthesize(_ text: String, model: String, voice: String, lang: String, to file: URL,
                    options: [String: Any] = [:], timeout: TimeInterval = 180) async throws {
        var request = URLRequest(url: base.appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": model, "input": text, "response_format": "wav"]
        if !voice.isEmpty { body["voice"] = voice }
        if !lang.isEmpty { body["lang_code"] = lang }
        body.merge(options) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SpeechError.badResponse(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        // A WAV header alone is 44 bytes; some models answer 200 with no audio for text they can't say.
        guard data.count > 100 else { throw SpeechError.noAudio }
        try data.write(to: file)
    }

    /// Stops the engine and waits for it to exit, so a fresh engine never meets the old one still
    /// holding the port. `downloads`: also stop any download (quitting, removing the engine); a
    /// voice switch restarts the engine but leaves a download of another voice running.
    func stop(downloads stopDownloads: Bool = true) async {
        if stopDownloads {
            for (model, process) in downloadProcesses where process.isRunning {
                Log.info("stopping the download of \(model) (pid \(process.processIdentifier))")
                process.terminate()
            }
        }
        warmed = []
        guard let child, child.isRunning else { self.child = nil; return }
        self.child = nil
        Log.info("stopping the voice engine (pid \(child.processIdentifier))")
        await Self.end(pid: child.processIdentifier) { child.isRunning }
    }

    /// Whether the engine is running, for the idle check.
    var isRunning: Bool { child?.isRunning == true }

    /// SIGTERM, up to five seconds to go, then SIGKILL.
    private static func end(pid: Int32, isRunning: () -> Bool) async {
        kill(pid, SIGTERM)
        for _ in 0..<50 where isRunning() {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if isRunning() {
            Log.error("the voice engine (pid \(pid)) didn't stop in 5 s; ending it")
            kill(pid, SIGKILL)
        }
    }

    /// Ends an engine on our port that this copy didn't start, but only one run from
    /// Readback's own runtime: anything else on the port is left alone and reported.
    private func stopStray() async {
        for pid in Self.listeners(on: Self.port) {
            let command = Self.command(of: pid)
            guard command.contains(paths.voiceServer.path) else {
                // The program's name, not its arguments, which can hold anything.
                let name = command.split(separator: " ").first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? "unknown"
                Log.error("port \(Self.port) is held by another program (\(name), pid \(pid))")
                continue
            }
            Log.info("ending a voice engine left over from before (pid \(pid)) to free its memory")
            await Self.end(pid: pid) { kill(pid, 0) == 0 }
        }
    }

    private static func listeners(on port: Int) -> [Int32] {
        run("/usr/sbin/lsof", ["-nP", "-tiTCP:\(port)", "-sTCP:LISTEN"])
            .split(whereSeparator: \.isNewline).compactMap { Int32($0) }
    }

    private static func command(of pid: Int32) -> String {
        run("/bin/ps", ["-o", "command=", "-p", String(pid)]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.error("couldn't run \(tool): \(error)")
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Downloading a model

    /// Downloads a model without loading it (Voices' Download button), so it's ready whenever
    /// it's picked. Waits for a download of another model to finish first: one at a time.
    func download(_ model: String) async throws {
        guard isInstalled else { throw SpeechError.notInstalled }
        cancelled.remove(model)   // asked for outright: an earlier Cancel doesn't stand in the way
        try await ensureDownloaded(model)
    }

    /// Stops a model's download and deletes what it had fetched. A reply waiting for that model
    /// fails with `downloadCancelled`.
    /// `evenIfNotStarted`: the install's Cancel, which can come before its download has begun;
    /// that download then doesn't begin, until `allowDownload`.
    func cancelDownload(_ model: String, evenIfNotStarted: Bool = false) {
        guard downloading[model] != nil || evenIfNotStarted else { return }
        cancelled.insert(model)
        downloadProcesses[model]?.terminate()
    }

    /// Lets `model` download again once the install that cancelled it has ended.
    func allowDownload(of model: String) { cancelled.remove(model) }

    private func ensureDownloaded(_ model: String) async throws {
        if let running = downloading[model] {
            try await running.value
            return
        }
        guard !ModelCache().isDownloaded(model, expectedBytes: VoiceCatalog.downloadBytes(for: model)) else { return }
        // Not tied to the reply that asked: closing the player shouldn't throw away a 3 GB
        // download half done, so it carries on and the next reply picks it up.
        let task = Task { try await self.downloadInTurn(model) }
        downloading[model] = task
        defer { downloading[model] = nil }
        try await task.value
    }

    /// One download at a time, first come first served: two at once would split the bandwidth
    /// and the progress line. (Waiting on "any other download" instead deadlocks when two start
    /// together, each waiting for the other.)
    private func downloadInTurn(_ model: String) async throws {
        downloadQueue.append(model)
        defer { downloadQueue.removeAll { $0 == model } }
        while let ahead = downloadQueue.first, ahead != model {
            if let task = downloading[ahead] {
                _ = try? await task.value
            }
            downloadQueue.removeAll { $0 == ahead }
        }
        if cancelled.remove(model) != nil { throw SpeechError.downloadCancelled }
        try await download(fetching: model)
    }

    /// Runs `ModelDownloadScript` in the engine's Python and passes its progress to `downloads`.
    private func download(fetching model: String) async throws {
        Log.info("downloading \(model)")
        // Opened before the download is announced: a log that can't be opened fails it like any
        // download that stops short, with Try again, rather than leaving a row that never ends.
        let engineLog: FileHandle
        do { engineLog = try logHandle() } catch {
            Log.error("downloading \(model) couldn't start: couldn't open the engine's log: \(error)")
            await downloads.failed(model, reason: "Readback couldn't open its log file")
            throw SpeechError.downloadFailed("couldn't open the engine's log")
        }
        // What the cache held before, so Cancel takes back only what this download adds.
        let before = ModelCache().inventory(of: model)
        await downloads.started(model)
        let lines = DownloadLines { [downloads] event in
            if case .progress(let received, let total) = event {
                Task { @MainActor in downloads.progress(model, received: received, total: total) }
            }
        }
        let process = Process()
        process.executableURL = paths.python
        process.currentDirectoryURL = paths.runtime
        process.arguments = ["-I", "-c", ModelDownloadScript.source, model]
        var env = ProcessInfo.processInfo.environment
        env["NLTK_DATA"] = paths.nltkData.path
        process.environment = env
        makeNLTKFolder()
        let out = Pipe()
        process.standardOutput = out
        process.standardError = engineLog   // Python's own warnings and tracebacks
        out.fileHandleForReading.readabilityHandler = { lines.add($0.availableData) }
        downloadProcesses[model] = process
        let status: Int32
        do {
            status = try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: error)
                }
            }
        } catch {
            // The download step couldn't start: the same Try again as one that stopped short.
            out.fileHandleForReading.readabilityHandler = nil
            downloadProcesses[model] = nil
            Log.error("downloading \(model) couldn't start: \(error)")
            await downloads.ended(model)
            await downloads.failed(model, reason: "the download couldn't start")
            throw SpeechError.downloadFailed("the download couldn't start")
        }
        out.fileHandleForReading.readabilityHandler = nil
        lines.add(out.fileHandleForReading.readDataToEndOfFile())   // whatever came after the last read
        downloadProcesses[model] = nil
        if cancelled.remove(model) != nil {
            // Cancelled: nothing half-fetched stays behind to look like a broken download, and
            // nothing that was there before it started goes.
            do {
                let freed = try ModelCache().discardDownload(of: model, since: before)
                Log.info("cancelled downloading \(model); removed \(freed.formatted(.byteCount(style: .file))) it had fetched")
            } catch {
                Log.error("cancelled downloading \(model), but couldn't remove what it had fetched: \(error)")
            }
            await downloads.cancelled(model)
            throw SpeechError.downloadCancelled
        }
        await downloads.ended(model)
        guard status == 0, lines.finished else {
            let reason = lines.failure ?? "it stopped (exit \(status))"
            Log.error("downloading \(model) failed: \(reason)")
            await downloads.failed(model, reason: reason)
            throw SpeechError.downloadFailed(reason)
        }
        Log.info("downloaded \(model)")
    }

    /// nltk downloads into NLTK_DATA only when that folder already exists; otherwise it makes
    /// ~/nltk_data in the person's home. So the folder is made first.
    private func makeNLTKFolder() {
        do {
            try FileManager.default.createDirectory(at: paths.nltkData, withIntermediateDirectories: true)
        } catch {
            Log.error("couldn't make \(paths.nltkData.path): \(error)")
        }
    }

    private func logHandle() throws -> FileHandle {
        try PrivateFiles.makeFolder(paths.logs)
        let logURL = paths.logs.appendingPathComponent("voice-engine.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        PrivateFiles.narrow(logURL)   // created 0644 before this version
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        return handle
    }

    private func isUp() async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("v1/models"))
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func start() throws {
        let handle = try logHandle()
        let process = Process()
        process.executableURL = paths.voiceServer
        process.currentDirectoryURL = paths.runtime
        // mlx-audio allows every origin unless told otherwise ("*"). Its own origin is one no
        // web page has, so browsers can neither read its answers nor send it JSON. Readback's
        // requests come from URLSession, which sends no Origin.
        process.arguments = ["--host", "127.0.0.1", "--port", String(Self.port),
                             "--allowed-origins", "http://127.0.0.1:\(Self.port)",
                             "--log-dir", paths.logs.appendingPathComponent("voice-engine").path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["NLTK_DATA"] = paths.nltkData.path
        process.environment = env
        makeNLTKFolder()
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        child = process
        Log.info("started the voice engine on port \(Self.port) (pid \(process.processIdentifier))")
    }
}

/// Splits the download step's output into lines as it arrives (reads can end mid-line) and
/// remembers how it ended. Fed from a pipe's background queue, so it locks.
final class DownloadLines: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var sawFinish = false
    private var lastFailure: String?
    private let onEvent: (ModelDownloadEvent) -> Void

    init(onEvent: @escaping (ModelDownloadEvent) -> Void) {
        self.onEvent = onEvent
    }

    var finished: Bool { lock.withLock { sawFinish } }
    var failure: String? { lock.withLock { lastFailure } }

    func add(_ data: Data) {
        guard !data.isEmpty else { return }
        let events: [ModelDownloadEvent] = lock.withLock {
            buffer.append(data)
            var found: [ModelDownloadEvent] = []
            while let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...end)
                guard let event = ModelDownloadEvent.parse(line) else { continue }
                switch event {
                case .finished: sawFinish = true
                case .failed(let reason): lastFailure = reason
                case .progress: break
                }
                found.append(event)
            }
            return found
        }
        events.forEach(onEvent)
    }
}
