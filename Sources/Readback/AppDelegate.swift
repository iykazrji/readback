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
    lazy var connections = Connections()
    lazy var replies = Replies()

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

        // When a reply finishes on its own, the next one waiting plays.
        reader.$phase
            .removeDuplicates()
            .sink { [weak self] phase in if phase == .finished { self?.playNextWaiting(after: 0.8) } }
            .store(in: &cancellables)

        // The idle clock runs while nothing is reading, and stops while something is.
        reader.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                if phase == .idle || phase == .finished { self?.scheduleIdleStop() } else { self?.idleStop?.cancel() }
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
            || getxattr(bundle + "/Contents/Helpers/readback", "com.apple.quarantine", nil, 0, 0, 0) >= 0 else { return }
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
            catch { Log.error("downloading the voice from Voices failed: \(error)") }
        }
    }

    /// A sample of the current voice. Not a reply, so it stays out of the history.
    func preview() {
        reader.start(SpeakRequest(text: "Hi. This is how I'll sound when I read your replies out loud.",
                                  source: "Readback", autoplay: true))
    }

    // MARK: Replies

    /// Plays a reply from the history now, whatever is playing. `cue`: it started by itself
    /// (auto-read, the next in the queue), so the cue sound gives a second's warning first.
    func play(_ reply: Reply, cue: Bool = false) {
        advanceTask?.cancel()
        replies.mark(reply.id, .played)
        replies.countPlay(of: reply)
        reader.start(reply.request, replyID: reply.id, cueSound: cue ? prefs.cueSound : nil)
    }

    /// Close, Esc or the menu's Stop: the person wants quiet, so nothing waiting plays after it.
    /// What was waiting stays in the history.
    func stopEverything() {
        advanceTask?.cancel()
        for reply in replies.all where reply.state == .waiting { replies.mark(reply.id, .kept) }
        replies.showingList = false
        reader.close()
    }

    private func playNextWaiting(after delay: Double) {
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.reader.isSpeaking, let next = self.replies.nextWaiting else { return }
            self.play(next, cue: true)
        }
    }

    private func speak(_ request: SpeakRequest) {
        let sessionOn = request.session.map(prefs.isSessionOn) ?? false
        let toolOn = request.tool.map { prefs.autoRead[$0] ?? false } ?? false
        let explicit = request.autoplay == true
        let wanted = request.autoplay ?? (sessionOn || toolOn)

        // /read of a reply the Stop hook already handed over: the same entry, not a copy.
        // Only for that explicit ask: a hook sending the same words again ("Done.") is a new reply.
        let reply: Reply
        if explicit, let existing = replies.all.prefix(20).first(where: { $0.text == request.text && $0.session == request.session }) {
            reply = existing
        } else {
            reply = Reply(request, state: wanted ? .waiting : .kept)
            replies.add(reply)
        }
        guard wanted else { return }
        if explicit || !reader.isSpeaking || prefs.switchToNewReplies {
            // /read and `readback say` were asked for just now: no warning needed.
            play(reply, cue: !explicit)
        }
    }

    /// A tool's "new message" hook: stop that session's reading and drop what it had waiting
    /// (the person moved on there). Other sessions' replies carry on.
    private func stopSession(_ session: String?) {
        guard let session else { stopEverything(); return }
        for reply in replies.all where reply.state == .waiting && reply.session == session {
            replies.mark(reply.id, .kept)
        }
        if reader.owner == nil || reader.owner == session {
            reader.close()
            playNextWaiting(after: 0.3)
        }
    }

    // MARK: Control server

    private func startControlServer() {
        let server = ControlServer(handlers: .init(
            speak: { [unowned self] request in self.speak(request) },
            stop: { [unowned self] session in self.stopSession(session) },
            replay: { [unowned self] session in
                guard let newest = self.replies.all.first(where: { $0.session == session }) else { return false }
                self.play(newest)
                return true
            },
            session: { [unowned self] id, enabled in
                if let enabled {
                    self.prefs.setSession(id, enabled)
                    if !enabled { self.stopSession(id) }
                }
                return self.prefs.isSessionOn(id)
            },
            auto: { [unowned self] tool, enabled in
                if let enabled { self.prefs.setAutoRead(tool, enabled) }
                return self.prefs.autoRead[tool] ?? false
            },
            voice: { [unowned self] request in self.setVoice(request) },
            engine: { [unowned self] action in
                switch action {
                case "install":
                    if self.runtime.state == .notInstalled || { if case .failed = self.runtime.state { return true }; return false }() {
                        self.runtime.install(for: self.prefs)
                    }
                case "remove":
                    if self.runtime.state == .installed { Task { await self.runtime.remove() } }
                default: break
                }
                return self.runtimeState
            },
            status: { [unowned self] in self.status() }
        ))
        do {
            try server.start()
        } catch {
            Log.error("couldn't start the control server on port \(ControlServer.port): \(error)")
        }
        self.server = server
    }

    /// `readback voice …`: the same choices as the Voices page, from the terminal.
    private func setVoice(_ request: ControlServer.VoiceRequest) -> Result<[String: Any], ControlServer.VoiceRequest.Invalid> {
        if let name = request.engine {
            guard let engine = EngineKind(rawValue: name.lowercased()) else {
                return .failure(.init(message: "unknown engine \(name): use system, kokoro, melo, soprano, qwen3 or custom"))
            }
            prefs.engine = engine
        }
        if let voice = request.voice {
            switch prefs.engine {
            case .system:
                guard voice.isEmpty || SystemVoice.voices().contains(where: { $0.identifier == voice }) else {
                    return .failure(.init(message: "no macOS voice with id \(voice)"))
                }
                prefs.systemVoice = voice
            case .kokoro:
                guard VoiceCatalog.kokoroVoice(voice) != nil else {
                    return .failure(.init(message: "Kokoro has no voice \(voice): try af_heart, am_michael, bf_emma"))
                }
                prefs.kokoroVoice = voice
            case .melo:
                guard VoiceCatalog.meloVoices.contains(where: { $0.id == voice }) else {
                    return .failure(.init(message: "MeloTTS has no accent \(voice): try EN-US, EN-BR, EN-AU, EN_INDIA or EN-Default"))
                }
                prefs.meloVoice = voice
            case .soprano:
                return .failure(.init(message: "Soprano has one voice; there's nothing to pick"))
            case .qwen3:
                guard VoiceCatalog.qwen3Voices.contains(where: { $0.id == voice }) else {
                    return .failure(.init(message: "Qwen3-TTS has no speaker \(voice): try ryan or aiden"))
                }
                prefs.qwen3Voice = voice
            case .custom:
                prefs.customVoice = voice
            }
        }
        if let model = request.model { prefs.customModel = model }
        if let lang = request.lang { prefs.customLang = lang }
        let setup = prefs.voiceSetup
        return .success(["engine": setup.engine.rawValue, "model": setup.model, "voice": setup.voice, "lang": setup.lang])
    }

    private func status() -> [String: Any] {
        let phase: String
        switch reader.phase {
        case .idle: phase = "idle"
        case .preparing: phase = "preparing"
        case .playing: phase = "playing"
        case .paused: phase = "paused"
        case .finished: phase = "finished"
        case .failed: phase = "failed"
        }
        let auto = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0.rawValue, prefs.autoRead[$0] ?? false) })
        return ["speaking": reader.isSpeaking, "phase": phase, "session": reader.owner ?? NSNull(),
                "current": reader.current, "count": reader.chunks.count, "speed": reader.speed,
                "waiting": replies.waitingCount, "history": replies.all.count,
                "auto": auto, "engine": prefs.engine.rawValue, "runtime": runtimeState, "version": Bundle.main.version,
                "menuBarIcon": menuBarIconState]
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
