import AppKit
import Combine
import ReadbackCore

/// Readback's app: owns the voice, the reader, the reply history, the floating player, the main
/// window and the local control server the coding tools' hooks talk to.
///
/// Every reply a hook hands over goes into the history. It's read when its hook asks outright
/// (`autoplay`: /read, `readback say`), when its session switched read-aloud on (/speak on), or when
/// its tool's "read every reply" switch is on. If something is already playing, it waits its turn
/// (or cuts in, if the person chose that); when a reply ends, the oldest waiting one plays next.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let prefs = Preferences.shared
    let downloads = ModelDownloads()
    lazy var voiceServer = VoiceServer(downloads: downloads)
    lazy var runtime = Runtime(server: voiceServer)
    lazy var reader = Reader(makeSpeaker: { [unowned self] in self.speaker() })
    lazy var connections: Connections = {
        let connections = Connections()
        connections.connected = { [prefs] home, before in prefs.connected(home.tool, from: before) }
        return connections
    }()
    lazy var replies = Replies()
    /// Check for updates, from the sidebar's version card. Never runs by itself.
    let updater = Updater()

    private var panel: PlayerPanelController?
    private var mainWindow: MainWindowController?
    private var server: ControlServer?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var advanceTask: Task<Void, Never>?
    /// Stops the voice engine after `idleStopAfter` with nothing read, to free its memory.
    private var idleStop: Task<Void, Never>?
    /// Chosen by the owner on 2026-11-23: an hour keeps it warm through breaks and frees the
    /// memory (850 MB to 3.5 GB, by model) overnight. The next reply then takes 2-3 s longer.
    /// A hidden `idleStopAfter` default (seconds) overrides it, for testing.
    static var idleStopAfter: TimeInterval { UserDefaults.standard.object(forKey: "idleStopAfter") as? Double ?? 3600 }
    /// "Lower other sounds while reading": when (`ducking`) and how (`otherAudio`).
    private var ducking = OtherAudioDucking()
    private let otherAudio = OtherAudioLowerer()
    private var restoreOtherAudio: Task<Void, Never>?
    private let replayItem = NSMenuItem(title: "Read last reply", action: #selector(replay), keyEquivalent: "")
    private let stopItem = NSMenuItem(title: "Stop", action: #selector(stopFromMenu), keyEquivalent: "")

    /// Started by a hook or the mod (`--background`) or at login: stay in the menu bar.
    /// Started by a person (Finder, Spotlight, the Dock): show the window.
    private var launchedInBackground = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch event is only available this early.
        var atLogin = false
        if let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication {
            atLogin = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        }
        launchedInBackground = CommandLine.arguments.contains("--background") || atLogin
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearQuarantine()
        removeLeftoverAudio()
        panel = PlayerPanelController(app: self)
        setUpMainMenu()
        setUpStatusMenu()
        startControlServer()
        connections.refreshPlugin()
        Log.info("Readback \(Bundle.main.version) started")
        // The one answer the version card shows and the install acts on, at the click and again
        // just before the swap.
        updater.waitingOn = { [unowned self] in
            let installing: Bool
            if case .installing = runtime.state { installing = true } else { installing = false }
            return UpdateWait.of(voiceDownload: downloads.active != nil, engineInstall: installing,
                                 connecting: connections.rows.values.contains { $0.busy != nil },
                                 engineRemoval: runtime.removing)
        }
        updater.afterLaunch(lowerOtherAudio: prefs.lowerOtherAudio) { otherAudio.askPermission() }

        reader.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.readerMoved(to: phase) }
            .store(in: &cancellables)
        // The switch: on asks macOS for the permission now, while the person is looking at it.
        // (@Published sends the new value before the property holds it, so it's passed along.)
        prefs.$lowerOtherAudio
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                if on, Self.otherAudioReading(self.reader.phase) == .stopped { self.otherAudio.askPermission() }
                self.otherAudioChanged(Self.otherAudioReading(self.reader.phase), switchedOn: on)
            }
            .store(in: &cancellables)

        // An engine installed before a new package was added (MeloTTS's) gets it now; the
        // warm-up waits for that, so the engine starts with everything it needs.
        if runtime.needsUpdate {
            Log.info("the voice engine is missing packages from this version; updating it")
            runtime.update { [weak self] in self?.warmUp() }
        } else {
            warmUp()
        }
        let firstRun = !UserDefaults.standard.bool(forKey: "onboarded")
        UserDefaults.standard.set(true, forKey: "onboarded")
        if firstRun {
            if mainWindow == nil { mainWindow = MainWindowController(app: self) }
            mainWindow?.showSetup()
        } else if !launchedInBackground {
            openWindow(.home)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        otherAudio.stopNow()
        reader.close()
        let server = voiceServer
        let done = DispatchSemaphore(value: 0)
        Task.detached { await server.stop(); done.signal() }
        _ = done.wait(timeout: .now() + 1)
    }

    /// Opening the app again from Finder, Spotlight or the Dock shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow(nil)
        return false
    }

    /// A downloaded copy carries macOS's "from the internet" flag on every file. Once the person
    /// has opened the app, the flag only gets in the way: Claude Code running the `readback`
    /// helper from a hook would be stopped by it. So the app clears it from its own bundle.
    private func clearQuarantine() {
        let bundle = Bundle.main.bundleURL.path
        guard getxattr(bundle, "com.apple.quarantine", nil, 0, 0, 0) >= 0
            || getxattr(AppBundle(url: Bundle.main.bundleURL).cli.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 else { return }
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", bundle]
        do {
            try xattr.run()
            xattr.waitUntilExit()
            if xattr.terminationStatus == 0 {
                Log.info("cleared the download flag from \(bundle)")
            } else {
                Log.error("couldn't clear the download flag from \(bundle) (xattr exit \(xattr.terminationStatus))")
            }
        } catch {
            Log.error("couldn't run xattr: \(error)")
        }
    }

    /// Each reading keeps its audio in a temp folder that goes when the reading closes. A crash
    /// or a force quit skips that, so anything left from an earlier run goes at launch. Only
    /// names Readback makes (`readback-<uuid>`, `readback-warm-<uuid>.wav`) are touched.
    private func removeLeftoverAudio() {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: temp.path) } catch {
            Log.error("couldn't look for leftover audio in \(temp.path): \(error)")
            return
        }
        var removed = 0
        for name in names {
            let id: String
            if name.hasPrefix("readback-warm-"), name.hasSuffix(".wav") {
                id = String(name.dropFirst("readback-warm-".count).dropLast(".wav".count))
            } else if name.hasPrefix("readback-") {
                id = String(name.dropFirst("readback-".count))
            } else { continue }
            guard UUID(uuidString: id) != nil else { continue }
            do {
                try fm.removeItem(at: temp.appendingPathComponent(name))
                removed += 1
            } catch {
                Log.error("couldn't remove leftover audio \(name): \(error)")
            }
        }
        if removed > 0 { Log.info("removed \(removed) leftover audio folder(s) from an earlier run") }
    }

    // MARK: Voice

    /// The speech maker for the current settings; the macOS voice while the engine isn't installed.
    private func speaker() -> SpeechMaker {
        let setup = prefs.voiceSetup
        if setup.engine.needsRuntime {
            if runtime.isInstalled, !setup.model.isEmpty {
                return NeuralVoice(server: voiceServer, model: setup.model, voice: setup.voice, lang: setup.lang,
                                   delivery: setup.delivery)
            }
            Log.info("\(setup.engine.title) needs the on-device engine, which isn't installed; using the macOS voice")
        }
        return SystemVoice(voiceID: prefs.systemVoice)
    }

    func resetPanelPosition() { panel?.resetPosition() }
    func panelPolicyFlipped(to name: String) { panel?.policyFlipped(to: name) }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleStopAfter))
            // isSpeaking, not isActive: a finished reply can sit in the player for good ("Keep it
            // open"), and that's not reading.
            guard let self, !Task.isCancelled, !self.reader.isSpeaking else { return }
            // Never in the middle of a download or an engine install: try again later.
            if self.downloads.active != nil || { if case .installing = self.runtime.state { return true }; return false }() {
                self.scheduleIdleStop()
                return
            }
            guard await self.voiceServer.isRunning else { return }
            Log.info("nothing read for \(Int(Self.idleStopAfter)) s: stopping the voice engine to free its memory")
            await self.voiceServer.stop()
        }
    }

    /// Starts the engine and loads the chosen voice, so the first reply starts quickly.
    private func warmUp() {
        guard runtime.isInstalled, prefs.engine.needsRuntime else { return }
        let setup = prefs.voiceSetup
        Task { [voiceServer] in
            do { try await voiceServer.ensureRunning(warming: setup.model, voice: setup.voice, lang: setup.lang) }
            catch { Log.error("voice warm-up failed: \(error)") }
        }
    }

    /// Downloads and loads the chosen voice now (Voices' "Download now"), so the first reply
    /// doesn't wait for it. Progress and any failure show through `downloads`.
    func downloadVoice() {
        let setup = prefs.voiceSetup
        guard runtime.isInstalled, setup.engine.needsRuntime, !setup.model.isEmpty else { return }
        Task { [voiceServer] in
            do { try await voiceServer.ensureRunning(warming: setup.model, voice: setup.voice, lang: setup.lang) }
            catch SpeechError.downloadCancelled { }   // the person stopped it; already logged
            catch { Log.error("downloading the voice from Voices failed: \(error)") }
        }
    }

    /// Downloads a voice's model now, without switching to it or loading it (Voices' Download
    /// buttons). Progress and any failure show through `downloads`.
    func download(_ model: String) {
        guard runtime.isInstalled else { return }
        Task { [voiceServer] in
            do { try await voiceServer.download(model) }
            catch SpeechError.downloadCancelled { }   // the person stopped it; already logged
            catch { Log.error("downloading \(model) from Voices failed: \(error)") }
        }
    }

    /// Stops a model's download and deletes what it had fetched.
    func cancelDownload(_ model: String) {
        Task { [voiceServer] in await voiceServer.cancelDownload(model) }
    }

    /// A sample of the current voice. Not a reply, so it stays out of the history.
    func preview() {
        reader.start(SpeakRequest(text: "Hi. This is how I'll sound when I read your replies out loud.",
                                  source: "Readback", autoplay: true))
    }

    // MARK: Replies

    /// What the reader is on, as the queue sees it.
    private var reading: ReplyQueue.Reading? {
        reader.isActive ? .init(replyID: reader.replyID, session: reader.owner, isSpeaking: reader.isSpeaking) : nil
    }

    /// Whether this reading's audio has been heard yet: it counts once in the all-time numbers,
    /// and a failure after that doesn't make the reply unheard. Reset for every new reading.
    private var heardThisReading = false

    /// A reading ending, by finishing or failing, hands over to the next waiting reply, and the
    /// engine's idle clock runs whenever nothing is being voiced. `phase` is the new one:
    /// @Published sends it before `reader.phase` changes, so decisions use it, not the reader's.
    private func readerMoved(to phase: Reader.Phase) {
        switch phase {
        case .playing:
            if !heardThisReading, reader.replyID != nil {
                heardThisReading = true
                replies.countPlay(spoken: reader.chunks.joined(separator: " "))
            }
        case .finished:
            playNextWaiting(after: 0.8)
        case .failed:
            if let id = reader.replyID, !heardThisReading { _ = replies.decide { $0.readingFailed(id); return .nothing } }
            playNextWaiting(after: 0.8)
        case .idle, .preparing, .paused:
            break
        }
        switch phase {
        case .preparing, .playing, .paused: idleStop?.cancel()
        case .idle, .finished, .failed: scheduleIdleStop()
        }
        otherAudioChanged(Self.otherAudioReading(phase), switchedOn: prefs.lowerOtherAudio)
    }

    private static func otherAudioReading(_ phase: Reader.Phase) -> OtherAudioDucking.Reading {
        switch phase {
        case .preparing: return .preparing
        case .playing: return .playing
        case .idle, .paused, .finished, .failed: return .stopped
        }
    }

    /// Other apps' sound follows the reading: taken over while it prepares, down while the voice
    /// plays, back a moment after it stops.
    private func otherAudioChanged(_ reading: OtherAudioDucking.Reading, switchedOn: Bool) {
        carryOut(ducking.readingChanged(reading, switchedOn: switchedOn))
    }

    private func carryOut(_ step: OtherAudioDucking.Step) {
        switch step {
        case .nothing:
            break
        case .takeOver:
            restoreOtherAudio?.cancel()
            otherAudio.takeOver()
        case .lower:
            restoreOtherAudio?.cancel()
            otherAudio.lower()
        case .keepLowered, .keepTakenOver:
            restoreOtherAudio?.cancel()
        case .restoreAfter(let seconds):
            restoreOtherAudio?.cancel()
            restoreOtherAudio = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                self.carryOut(self.ducking.restoreDue(Self.otherAudioReading(self.reader.phase)))
            }
        case .restore:
            restoreOtherAudio?.cancel()
            otherAudio.restore()
        case .release:
            restoreOtherAudio?.cancel()
            otherAudio.release()
        }
    }

    private func carryOut(_ step: ReplyQueue.Step) {
        switch step {
        case .nothing:
            break
        case .play(let reply, let cue):
            advanceTask?.cancel()
            heardThisReading = false
            reader.start(reply.request, replyID: reply.id, cueSound: cue ? prefs.cueSound : nil)
        case .stopThenNext:
            reader.close()
            playNextWaiting(after: 0.3)
        case .quiet:
            advanceTask?.cancel()
            replies.showingList = false
            reader.close()
        }
    }

    /// Plays a reply from the history now, whatever is playing.
    func play(_ reply: Reply) {
        carryOut(replies.decide { $0.play(reply.id) })
    }

    /// Close, Esc or the menu's Stop.
    func stopEverything() {
        carryOut(replies.decide { $0.stopAll() })
    }

    private func playNextWaiting(after delay: Double) {
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.carryOut(self.replies.decide { [reading = self.reading] in $0.playNext(reading: reading) })
        }
    }

    // MARK: Control server

    private func startControlServer() {
        let server = ControlServer { [unowned self] request in self.handle(request) }
        do {
            try server.start()
        } catch {
            Log.error("couldn't start the control server on port \(server.port): \(error)")
        }
        self.server = server
    }

    private func handle(_ request: ControlRequest) -> Data {
        switch request {
        case .health:
            return HTTPResponse.json(200, health)
        case .speak(let speak):
            if !SpeechText.isSpeakable(speak.text) {
                Log.info("a reply from \(speak.tool?.name ?? "a reply without a tool") had nothing to read; kept, not played")
            }
            let switchedOn = prefs.switches.wantsReading(tool: speak.tool, session: speak.session)
            carryOut(replies.decide { [reading] in $0.received(speak, switchedOn: switchedOn, reading: reading, cutIn: prefs.switchToNewReplies) })
            return HTTPResponse.json(202, ["accepted": true])
        case .stop(let session, let newTurn):
            if let session {
                carryOut(replies.decide { [reading] in $0.stop(session: session, reading: reading, newTurn: newTurn) })
            } else {
                stopEverything()
            }
            return HTTPResponse.json(200, ["ok": true])
        case .command(let command):
            return HTTPResponse.json(200, CommandReply(text: answer(command)))
        case .replay(let session):
            let step = replies.decide { $0.readLast(session: session) }
            carryOut(step)
            if case .play = step { return HTTPResponse.json(200, ["played": true]) }
            return HTTPResponse.json(200, ["played": false])
        case .session(let body):
            if let enabled = body.enabled { setSession(body.session, enabled) }
            return HTTPResponse.json(200, ["session": body.session, "enabled": prefs.isSessionOn(body.session)])
        case .auto(let body):
            if let enabled = body.enabled { prefs.setReadsEveryReply(body.tool, enabled) }
            return HTTPResponse.json(200, ["tool": body.tool.rawValue, "enabled": prefs.readsEveryReply(body.tool)])
        case .voice(let body):
            switch setVoice(body) {
            case .success(let current): return HTTPResponse.json(200, current)
            case .failure(let invalid): return HTTPResponse.json(400, ["error": invalid.message])
            }
        case .engine(let action):
            switch action {
            case .install?:
                if runtime.state == .notInstalled || { if case .failed = runtime.state { return true }; return false }() {
                    runtime.install(for: prefs)
                }
            case .remove?:
                if runtime.state == .installed || runtime.removeFailed { runtime.startRemoving() }
            case nil:
                break
            }
            return HTTPResponse.json(200, ["runtime": runtimeState])
        }
    }

    /// Switching a session off also stops what it's reading.
    private func setSession(_ id: String, _ on: Bool) {
        prefs.setSession(id, on)
        if !on { carryOut(replies.decide { [reading] in $0.stop(session: id, reading: reading) }) }
    }

    /// /speak and /read typed in a tool: Claude Code's mod and Codex's prompt hook both show this.
    private func answer(_ command: CommandRequest) -> String {
        switch command.command {
        case .speak:
            let session = command.session ?? ""
            if let enabled = command.enabled { setSession(session, enabled) }
            return CommandAnswer.speak(asked: command.enabled, isOn: prefs.isSessionOn(session),
                                       everyReply: prefs.readsEveryReply(command.tool), tool: command.tool)
        case .read:
            let asSent = command.text.map { SpeakRequest(text: $0, source: command.tool.rawValue, cwd: command.cwd, session: command.session) }
            let step = replies.decide { $0.readLast(session: command.session, asSent: asSent) }
            carryOut(step)
            if case .play = step { return CommandAnswer.read(played: true, tool: command.tool) }
            return CommandAnswer.read(played: false, tool: command.tool)
        }
    }

    struct InvalidVoice: Error { let message: String }

    /// `readback voice …`: the same choices as the Voices page, from the terminal. Everything is
    /// checked first, so a request that fails changes nothing.
    private func setVoice(_ request: VoiceRequest) -> Result<[String: Any], InvalidVoice> {
        var engine = prefs.engine
        if let name = request.engine {
            guard let picked = EngineKind(rawValue: name.lowercased()) else {
                return .failure(.init(message: "unknown engine \(name): use \(EngineKind.allCases.map(\.rawValue).joined(separator: ", "))"))
            }
            engine = picked
        }
        let voice = request.voice.map { $0.trimmingCharacters(in: .whitespaces) }
        if let voice, let problem = VoiceCatalog.problem(voice: voice, for: engine,
                                                         systemVoiceExists: { id in SystemVoice.voices().contains { $0.identifier == id } }) {
            return .failure(.init(message: problem))
        }
        prefs.engine = engine
        if let voice {
            switch engine {
            case .system: prefs.systemVoice = voice
            case .kokoro: prefs.kokoroVoice = voice
            case .melo: prefs.meloVoice = voice
            case .qwen3: prefs.qwen3Voice = voice
            case .custom: prefs.customVoice = voice
            case .soprano: break
            }
        }
        if let model = request.model { prefs.customModel = model.trimmingCharacters(in: .whitespaces) }
        if let lang = request.lang { prefs.customLang = lang.trimmingCharacters(in: .whitespaces) }
        let setup = prefs.voiceSetup
        return .success(["engine": setup.engine.rawValue, "model": setup.model, "voice": setup.voice, "lang": setup.lang])
    }

    private var health: Health {
        let phase: String
        switch reader.phase {
        case .idle: phase = "idle"
        case .preparing: phase = "preparing"
        case .playing: phase = "playing"
        case .paused: phase = "paused"
        case .finished: phase = "finished"
        case .failed: phase = "failed"
        }
        return Health(speaking: reader.isSpeaking, phase: phase, session: reader.owner,
                      current: reader.current, count: reader.chunks.count, speed: reader.speed,
                      waiting: replies.waitingCount, history: replies.all.count,
                      auto: Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0.rawValue, prefs.readsEveryReply($0)) }),
                      engine: prefs.engine.rawValue, runtime: runtimeState, version: Bundle.main.version,
                      menuBarIcon: menuBarIconState)
    }

    /// Whether the menu bar icon can be seen: a MacBook notch, a full-screen app or the system's
    /// Menu Bar settings can hide it. Then the window is still one Spotlight search away.
    private var menuBarIconState: String {
        guard let item = statusItem, let window = item.button?.window else { return "missing" }
        if !item.isVisible { return "removed" }
        let f = window.frame
        let where_ = "at x=\(Int(f.minX)) y=\(Int(f.minY))"
        return window.occlusionState.contains(.visible)
            ? "on screen \(where_)"
            : "in the menu bar \(where_), not visible right now (a full-screen app or an auto-hiding menu bar hides it)"
    }

    var runtimeState: String {
        if runtime.removing { return "removing" }
        switch runtime.state {
        case .unsupported: return "unsupported"
        case .notInstalled: return "not installed"
        case .installing(let step): return "installing: \(step)"
        case .installed: return "installed"
        case .failed(let message): return "failed: \(message)"
        }
    }

    // MARK: Window and menus

    func openWindow(_ section: MainSection?) {
        if mainWindow == nil { mainWindow = MainWindowController(app: self) }
        mainWindow?.show(section)
    }

    @objc private func openFromMenu() { openWindow(nil) }
    @objc private func openHistory() { openWindow(.history) }

    /// The app menu bar, for when the window is open and Readback is a regular app: Quit, the
    /// window shortcut, and Edit so copy and paste work in text fields.
    private func setUpMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Readback", action: #selector(openAbout), keyEquivalent: "").withTarget(self))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",").withTarget(self))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Readback", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit Readback", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    @objc private func openAbout() { openWindow(.about) }
    @objc func openSettings(_ sender: Any?) { openWindow(.voices) }

    /// Cadence, the app icon's mark, as an 18 pt template (1× and 2× in Resources) so macOS
    /// tints it for a light or dark menu bar. The waveform symbol if the files are missing.
    private static var menuBarIcon: NSImage? {
        if let mark = Bundle.main.image(forResource: "MenuBarIcon") {
            mark.isTemplate = true
            mark.size = NSSize(width: 18, height: 18)
            mark.accessibilityDescription = "Readback"
            return mark
        }
        Log.error("MenuBarIcon is missing from the app's Resources; using the waveform symbol")
        return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Readback")
    }

    private func setUpStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon
        let menu = NSMenu()
        menu.delegate = self
        // menuNeedsUpdate sets each item's state; automatic enabling would override it
        // (it enables anything whose action is reachable, so Stop showed while nothing played).
        menu.autoenablesItems = false
        for entry in [replayItem, stopItem] { entry.target = self; menu.addItem(entry) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "").withTarget(self))
        menu.addItem(NSMenuItem(title: "Open Readback", action: #selector(openFromMenu), keyEquivalent: "o").withTarget(self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Readback", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        replayItem.isEnabled = replies.newest != nil
        stopItem.isEnabled = reader.isActive
    }

    @objc private func replay() { if let newest = replies.newest { play(newest) } }
    @objc private func stopFromMenu() { stopEverything() }
}

extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}

extension Bundle {
    var version: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
