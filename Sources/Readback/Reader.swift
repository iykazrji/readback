import AppKit
import AVFoundation
import Foundation
import ReadbackCore

/// One reply being read aloud: its chunks, which one is playing, and the controls.
/// Audio for each chunk is made in order in the background; playback starts as soon as
/// the first chunk is ready and waits ("preparing") if it catches up with generation.
@MainActor
final class Reader: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, playing, paused, finished
        case failed(String)
    }

    static let speeds: [Double] = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75]

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var chunks: [String] = []
    @Published private(set) var current = 0
    @Published private(set) var title = ""
    @Published private(set) var progress = 0.0
    @Published private(set) var speed: Double

    /// The tool session the reply came from, when it said (so a session stops only its own reading).
    @Published private(set) var owner: String?
    /// The history entry being read, so the list can mark it.
    @Published private(set) var replyID: UUID?
    /// The model this reading's voice downloads before it speaks; nil for the macOS voice. Another
    /// model's download (one started from Voices) isn't this reading's to show or cancel.
    @Published private(set) var voiceModel: String?
    /// While waiting for a sentence's audio ("preparing"): whether it plays or waits paused once
    /// it's ready. The play button flips it, so a pause or a seek made while waiting holds.
    @Published private(set) var startsPlaying = true
    /// How far into the waited-for sentence it starts (0...1), from a seek.
    private var pendingOffset = 0.0

    var isActive: Bool { phase != .idle }
    var isSpeaking: Bool { phase == .playing || phase == .preparing || phase == .paused }

    /// Picks the voice for each reply, from the current settings.
    private let makeSpeaker: @MainActor () -> SpeechMaker
    private let player = AVPlayer()
    private var audio: [Int: URL] = [:]
    private var durations: [Int: Double] = [:]
    private var run = UUID()   // one per reading; work from an older reading is dropped
    private var workDir: URL?
    private var generation: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    /// The cue to play once the first sentence is ready, a second ahead of the voice.
    private var pendingCue: String?
    /// Held while it plays: an NSSound nothing holds can stop early.
    private var cue: NSSound?

    /// How long the voice waits after the cue sound starts.
    static let cueLead: TimeInterval = 1.0

    init(makeSpeaker: @escaping @MainActor () -> SpeechMaker) {
        self.makeSpeaker = makeSpeaker
        let saved = UserDefaults.standard.double(forKey: "speed")
        speed = Self.speeds.contains(saved) ? saved : 1.0
        player.automaticallyWaitsToMinimizeStalling = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateProgress() }
        }
    }

    // MARK: Starting and stopping

    /// `cueSound`: a macOS sound played when the first sentence is ready, the voice starting
    /// `cueLead` after it. Played then, not when the reply arrives, so it always means "about
    /// to read" even when the voice takes a while to get going (a first download, Qwen3).
    func start(_ request: SpeakRequest, replyID: UUID? = nil, cueSound: String? = nil) {
        let chunks = SpeechText.voicedChunks(request.text)
        guard !chunks.isEmpty else {
            Log.info("nothing speakable in a reply from \(request.tool?.name ?? "a reply without a tool")")
            return
        }
        close()
        let run = UUID()
        self.run = run
        self.chunks = chunks
        owner = request.session
        self.replyID = replyID
        title = request.title
        current = 0
        progress = 0
        pendingOffset = 0
        startsPlaying = true
        phase = .preparing
        pendingCue = (cueSound?.isEmpty == false) ? cueSound : nil

        let speaker = makeSpeaker()
        voiceModel = speaker.downloadModel
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readback-\(run.uuidString)", isDirectory: true)
        workDir = dir
        generation = Task {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try await speaker.prepare()
                for index in chunks.indices {
                    try Task.checkCancellation()
                    let file = dir.appendingPathComponent("\(index).\(speaker.fileExtension)")
                    // The player shows the reply as written; the voice says it for the ear
                    // (paths as their file, no commit hashes, symbols as words: SpokenText).
                    try await speaker.make(SpokenText.rewrite(chunks[index]), to: file)
                    guard self.run == run else { return }
                    self.audio[index] = file
                    self.durations[index] = Self.duration(of: file)
                    if index == self.current && self.phase == .preparing { self.playAfterCue(index, run: run) }
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.run == run else { return }
                Log.error("couldn't make speech: \(error)")
                self.player.pause()
                self.phase = .failed("Couldn't read this reply: \(error). Change the voice in Readback's Settings.")
            }
        }
    }

    func setSpeed(_ value: Double) {
        guard Self.speeds.contains(value) else { return }
        speed = value
        UserDefaults.standard.set(speed, forKey: "speed")
        if phase == .playing { player.rate = Float(speed) }
    }


    /// Stops playback and forgets the reply. The player hides when phase is idle.
    func close() {
        generation?.cancel()
        generation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
        workDir = nil
        audio = [:]
        durations = [:]
        run = UUID()
        owner = nil
        voiceModel = nil
        replyID = nil
        pendingOffset = 0
        startsPlaying = true
        phase = .idle
    }

    /// Starts the first sentence: straight away, or, with a cue, the cue now and the voice a
    /// second later. Later sentences keep being made meanwhile.
    private func playAfterCue(_ index: Int, run: UUID) {
        // Paused before it began: no cue now, and none later in the middle of the reply.
        guard let name = pendingCue, startsPlaying else { pendingCue = nil; startPending(index); return }
        pendingCue = nil
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            Log.error("no macOS sound named \(name); reading without the cue")
            startPending(index)
            return
        }
        cue = sound
        sound.play()
        Log.info("cue: \(name), voice in \(Self.cueLead) s")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.cueLead))
            guard let self, self.run == run, self.phase == .preparing, self.current == index else { return }
            self.startPending(index)
        }
    }

    /// Starts the sentence that was waited for, where and how the person left it.
    private func startPending(_ index: Int) {
        let offset = pendingOffset, autoplay = startsPlaying
        pendingOffset = 0
        startsPlaying = true
        play(index, from: offset, autoplay: autoplay)
    }

    // MARK: Controls

    func togglePlay() {
        switch phase {
        case .playing:
            player.pause()
            phase = .paused
        case .paused:
            player.playImmediately(atRate: Float(speed))
            phase = .playing
        case .finished:
            play(0)
        case .preparing:
            startsPlaying.toggle()
        default:
            break
        }
    }

    /// Back one chunk, or to the start of this one if it's been playing a while.
    func back() {
        guard !chunks.isEmpty else { return }
        if player.currentTime().seconds > 1.5 { play(current) } else { play(max(0, current - 1)) }
    }

    func forward() {
        guard current + 1 < chunks.count else { return }
        play(current + 1)
    }

    func restart() {
        guard !chunks.isEmpty else { return }
        play(0)
    }

    /// Jumps to a point on the whole reply, 0...1. Each chunk is an equal share of the line
    /// (later chunks' lengths aren't known until they're made). Paused stays paused.
    func seek(to fraction: Double) {
        guard !chunks.isEmpty else { return }
        let scaled = min(max(fraction, 0), 1) * Double(chunks.count)
        let index = min(Int(scaled), chunks.count - 1)
        let autoplay = phase == .preparing ? startsPlaying : phase != .paused
        play(index, from: min(scaled - Double(index), 0.999), autoplay: autoplay)
    }

    func cycleSpeed() {
        let i = Self.speeds.firstIndex(of: speed) ?? 0
        setSpeed(Self.speeds[(i + 1) % Self.speeds.count])
    }

    // MARK: Playback

    /// Plays chunk `index`, starting `offset` (0...1) of the way in.
    private func play(_ index: Int, from offset: Double = 0, autoplay: Bool = true) {
        if case .failed = phase { return }
        current = index
        guard let file = audio[index] else {
            // Not generated yet: wait ("preparing"); the generation loop starts it as asked.
            player.pause()
            pendingOffset = offset
            startsPlaying = autoplay
            phase = .preparing
            updateProgress()
            return
        }
        let item = AVPlayerItem(url: file)
        item.audioTimePitchAlgorithm = .timeDomain   // keeps voice pitch natural at other speeds
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.chunkEnded() }
        }
        player.replaceCurrentItem(with: item)
        if offset > 0, let length = durations[index] {
            player.seek(to: CMTime(seconds: offset * length, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if autoplay {
            player.playImmediately(atRate: Float(speed))
            phase = .playing
        } else {
            player.pause()
            phase = .paused
            progress = (Double(index) + offset) / Double(chunks.count)
        }
    }

    private static func duration(of file: URL) -> Double? {
        do {
            let audio = try AVAudioFile(forReading: file)
            return Double(audio.length) / audio.processingFormat.sampleRate
        } catch {
            Log.error("couldn't read the length of \(file.lastPathComponent): \(error)")
            return nil
        }
    }

    private func chunkEnded() {
        if current + 1 < chunks.count {
            play(current + 1)
        } else {
            phase = .finished
            progress = 1
        }
    }

    private func updateProgress() {
        guard !chunks.isEmpty, phase != .finished else { return }
        var within = 0.0
        if let item = player.currentItem, item.duration.isNumeric, item.duration.seconds > 0 {
            within = min(1, max(0, player.currentTime().seconds / item.duration.seconds))
        }
        if phase == .preparing { within = pendingOffset }
        progress = (Double(current) + within) / Double(chunks.count)
    }
}
