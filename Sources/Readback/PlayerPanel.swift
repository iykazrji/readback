import AppKit
import Carbon.HIToolbox
import Combine
import ReadbackCore
import SwiftUI

/// A floating panel that never steals focus from the app you're typing in. It shows when a
/// reply starts (or the reply list is opened), hides when it's closed, and hides by itself a few
/// seconds after the reply ends unless the pointer is over it or the list is open.
/// While it's showing, Esc closes it.
@MainActor
final class PlayerPanelController {
    private unowned let app: AppDelegate
    private var reader: Reader { app.reader }
    private var prefs: Preferences { app.prefs }
    private var replies: Replies { app.replies }
    private let panel: FloatingPanel
    private let host: FirstClickHostingView<PlayerView>
    private let escape = EscapeHotKey()
    private var cancellables: Set<AnyCancellable> = []
    private var hideTimer: Timer?
    /// Ends the "Muted …" note after the player's usual few seconds.
    private var noticeTimer: Timer?
    private var hovering = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    /// Old absolute position (migrated once, then removed) and the current screen-relative one.
    private static let originKey = "panelOrigin"
    private static let offsetKey = "panelOffsetFromScreenBottomCentre"

    init(app: AppDelegate) {
        self.app = app
        panel = FloatingPanel()
        host = FirstClickHostingView(rootView: PlayerView(reader: app.reader, replies: app.replies, downloads: app.downloads,
                                                          runtime: app.runtime, prefs: app.prefs,
                                                          onClose: {}, onPlay: { _ in }, onHover: { _ in }, onDrag: { _, _ in }))
        // Rebuild with the real handlers now that self exists.
        host.rootView = PlayerView(
            reader: app.reader,
            replies: app.replies,
            downloads: app.downloads,
            runtime: app.runtime,
            prefs: app.prefs,
            onClose: { [weak app] in app?.stopEverything() },
            onCancelDownload: { [weak app] model in app?.cancelDownload(model) },
            openVoices: { [weak app] in app?.openWindow(.voices) },
            onMuteThread: { [weak app] in app?.muteCurrentThread() },
            onUnmute: { [weak app] thread in
                app?.setMuted(thread, false)
                app?.replies.mutedNotice = nil
            },
            onPlay: { [weak app] reply in app?.play(reply) },
            onHover: { [weak self] in self?.hoverChanged($0) },
            onDrag: { [weak self] translation, ended in self?.dragged(translation, ended: ended) }
        )
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        escape.onPress = { [weak app] in app?.stopEverything() }
        migrateOldOrigin()
        observeSpacesAndScreens()

        reader.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.phaseChanged(phase) }
            .store(in: &cancellables)
        // Settings changed while the player is up take effect now, not at the next reply.
        // (@Published sends the new value before the property changes, so it's used as sent.)
        prefs.$escCloses
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self, self.panel.isVisible, self.shouldBeShowing else { return }
                if on { self.escape.register() } else { self.escape.unregister() }
            }
            .store(in: &cancellables)
        prefs.$hideAfter
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] seconds in
                guard let self else { return }
                // The muted note's own few seconds follow the new setting too.
                if let notice = self.replies.mutedNotice { self.mutedNoticeChanged(notice, hideAfter: seconds) }
                guard self.reader.phase == .finished else { return }
                self.scheduleHide(after: seconds)
            }
            .store(in: &cancellables)
        replies.$showingList
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] showing in
                // The view updates first; size the panel to it on the next turn.
                DispatchQueue.main.async { self?.listToggled(showing) }
            }
            .store(in: &cancellables)
        replies.$mutedNotice
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] notice in
                DispatchQueue.main.async { self?.mutedNoticeChanged(notice) }
            }
            .store(in: &cancellables)
    }

    private func phaseChanged(_ phase: Reader.Phase) {
        hideTimer?.invalidate()
        switch phase {
        case .idle:
            // Muting from the player stops the reading; the player stays to say so.
            if !replies.showingList && replies.mutedNotice == nil { hide() }
        case .finished:
            show()
            scheduleHide()
        default:
            // Another reply started: it takes the player's place over the muted note.
            if replies.mutedNotice != nil { replies.mutedNotice = nil }
            show()
        }
    }

    /// "Muted <thread>. Unmute": shown for the player's usual few seconds (at least three, so
    /// there's time to read it and reach Unmute), or until closed when the player stays open.
    /// `hideAfter`: the setting as just changed (it arrives before `prefs` has it).
    private func mutedNoticeChanged(_ notice: Replies.MutedNotice?, hideAfter: Double? = nil) {
        noticeTimer?.invalidate()
        guard notice != nil else {
            resizeToFit()
            if !shouldBeShowing { hide() }
            return
        }
        show()
        resizeToFit()
        let seconds = hideAfter ?? prefs.hideAfter
        guard seconds > 0 else { return }   // 0: stays until closed
        noticeTimer = Timer.scheduledTimer(withTimeInterval: max(seconds, 3), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.replies.mutedNotice == notice else { return }
                if self.hovering && self.panel.isVisible && self.panel.isOnActiveSpace {
                    self.mutedNoticeChanged(notice)   // they're reaching for Unmute: wait
                } else {
                    self.replies.mutedNotice = nil
                }
            }
        }
    }

    private func listToggled(_ showing: Bool) {
        if showing {
            show()
            resizeToFit()
        } else {
            resizeToFit()
            // The muted note keeps it up: hiding now would leave it faded out but still there.
            if !reader.isActive && replies.mutedNotice == nil { hide() }
            if reader.phase == .finished { scheduleHide() }
        }
    }

    /// Opens the player with its reply list, even when nothing is playing (menu bar → History).
    func showList() {
        replies.showingList = true
    }

    /// Grows or shrinks the panel to its content, keeping its bottom edge where it is and the
    /// whole panel on screen.
    private func resizeToFit() {
        let size = host.fittingSize
        var frame = panel.frame
        frame.size = size
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - size.height)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - size.width)
        }
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    /// True while the player has a reason to be on screen: reading, just finished (before its
    /// own hide), or the reply list open.
    private var shouldBeShowing: Bool {
        reader.isActive || reader.phase == .finished || replies.showingList || replies.mutedNotice != nil
    }

    private func show() {
        // Also runs when a new reply lands mid fade-out: the panel is still "visible" then,
        // so always animate back to full opacity, or it ends up invisible and click-through.
        if !panel.isVisible {
            // Hidden to showing: the one moment it may pick another screen. Never mid reading.
            panel.setContentSize(host.fittingSize)
            panel.setFrameOrigin(placement(on: targetScreen()))
            panel.alphaValue = 0
            hovering = false
            panel.collectionBehavior = FloatingPanel.everySpace
            panel.orderFrontRegardless()
        } else if !panel.isOnActiveSpace {
            // Re-ordering a panel macOS attached to another Space does nothing; it has to
            // leave the screen list and come back.
            rehome("off active space at show", force: true)
        } else {
            panel.collectionBehavior = FloatingPanel.everySpace
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        if prefs.escCloses { escape.register() } else { escape.unregister() }
    }

    /// Brings a showing panel onto the Space the user is on now. Without `force` it only acts
    /// when the panel is not on the active Space. Logs when it actually does something.
    func rehome(_ reason: String, force: Bool = false) {
        guard panel.isVisible, shouldBeShowing else { return }
        let stranded = !panel.isOnActiveSpace
        guard force || stranded else { return }
        Log.info("player re-homed (\(reason)); wasOnActiveSpace=\(!stranded) frame=\(NSStringFromRect(panel.frame))")
        hovering = false   // mouse-exit never arrives for a panel on another Space
        panel.orderOut(nil)
        panel.collectionBehavior = FloatingPanel.everySpace
        panel.setFrame(clampedToConnectedScreen(panel.frame), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    /// An activation-policy flip: re-home now, and check again once the system has settled.
    func policyFlipped(to name: String) {
        rehome("activation policy -> \(name)", force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated { self?.rehome("still off active space after policy -> \(name)") }
        }
    }

    private func observeSpacesAndScreens() {
        let space = NSWorkspace.shared.notificationCenter
        spaceObserver = space.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The panel's Space state updates a beat after the notification.
                self.rehome("space change")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    MainActor.assumeIsolated { self?.rehome("space change (settled)") }
                }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                if self.shouldBeShowing {
                    self.rehome("screens changed", force: true)
                } else {
                    self.panel.setFrame(self.clampedToConnectedScreen(self.panel.frame), display: false)
                }
            }
        }
    }

    /// Puts the player back at its default spot (bottom centre, 24pt up, on the screen it is on).
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.offsetKey)
        if panel.isVisible {
            panel.setFrameOrigin(placement(on: screen(of: panel.frame) ?? NSScreen.main ?? NSScreen.screens[0]))
        }
    }

    private func hide() {
        escape.unregister()
        guard panel.isVisible else { hovering = false; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new reading started during the fade: stay.
                guard let self, !self.reader.isActive, !self.replies.showingList, self.replies.mutedNotice == nil else { return }
                self.panel.orderOut(nil)
                self.hovering = false
            }
        })
    }

    private func scheduleHide(after seconds: Double? = nil) {
        hideTimer?.invalidate()
        let seconds = seconds ?? prefs.hideAfter
        guard seconds > 0 else { return }   // 0: stays until closed
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reader.phase == .finished else { return }
                // A hover that can't be real (panel off the active Space) must not keep it alive.
                if self.hovering && (!self.panel.isVisible || !self.panel.isOnActiveSpace) { self.hovering = false }
                if self.hovering || self.replies.showingList { self.scheduleHide() } else { self.reader.close() }
            }
        }
    }

    private func hoverChanged(_ isHovering: Bool) {
        hovering = isHovering
    }

    /// Moves the panel with the mouse in screen coordinates, so the panel moving under the
    /// pointer doesn't feed back into the drag. The gesture's first report already includes a
    /// few points of movement; subtracting it puts the drag's true start where the click was.
    /// The panel stays fully on the screen it's on.
    private func dragged(_ translation: CGSize, ended: Bool) {
        if ended {
            dragStart = nil
            saveOffset()
            return
        }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (NSPoint(x: mouse.x - translation.width, y: mouse.y + translation.height), panel.frame.origin)
        }
        guard let start = dragStart else { return }
        var origin = NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                             y: start.origin.y + mouse.y - start.mouse.y)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? panel.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: Placement

    /// The saved placement: offset of the panel's bottom-centre from the bottom-centre of the
    /// screen's visible frame (stored as a point: x = dx, y = dy). Default bottom centre, 24pt up.
    private func savedOffset() -> PlayerGeometry.Offset {
        guard let saved = UserDefaults.standard.string(forKey: Self.offsetKey) else { return .standard }
        let p = NSPointFromString(saved)
        return PlayerGeometry.Offset(dx: p.x, dy: p.y)
    }

    private func placement(on screen: NSScreen) -> NSPoint {
        PlayerGeometry.frame(for: savedOffset(), size: panel.frame.size, in: screen.visibleFrame).origin
    }

    private func saveOffset() {
        guard panel.isVisible, let screen = screen(of: panel.frame) else { return }
        let off = PlayerGeometry.offset(of: panel.frame, in: screen.visibleFrame)
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: off.dx, y: off.dy)), forKey: Self.offsetKey)
    }

    /// One-time: the old absolute `panelOrigin` becomes an offset on the screen it sat on.
    private func migrateOldOrigin() {
        let defaults = UserDefaults.standard
        guard let old = defaults.string(forKey: Self.originKey) else { return }
        if defaults.string(forKey: Self.offsetKey) == nil,
           let off = PlayerGeometry.migrate(oldOrigin: NSPointFromString(old), size: panel.frame.size,
                                            visibleFrames: NSScreen.screens.map(\.visibleFrame)) {
            defaults.set(NSStringFromPoint(NSPoint(x: off.dx, y: off.dy)), forKey: Self.offsetKey)
            Log.info("player position migrated: \(old) -> offset (\(off.dx), \(off.dy))")
        }
        defaults.removeObject(forKey: Self.originKey)
    }

    /// The screen a frame mostly sits on, by visible frame.
    private func screen(of frame: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        return PlayerGeometry.indexWithLargestIntersection(of: frame, in: screens.map(\.frame)).map { screens[$0] }
    }

    private func clampedToConnectedScreen(_ frame: NSRect) -> NSRect {
        let screen = screen(of: frame) ?? NSScreen.main ?? NSScreen.screens[0]
        return PlayerGeometry.clamp(frame, into: screen.visibleFrame)
    }

    /// The screen of the focused window: the frontmost app's frontmost normal window (read from
    /// the window list, no Accessibility needed), else Readback's own key window when it is the
    /// frontmost app, else the mouse, else main.
    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        if let app = NSWorkspace.shared.frontmostApplication {
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                if let w = NSApp.keyWindow ?? NSApp.mainWindow, w !== panel, let s = w.screen { return s }
            } else if let cg = frontmostWindowBounds(pid: app.processIdentifier), let primary = screens.first {
                let rect = PlayerGeometry.cocoaRect(fromCG: cg, primaryScreenHeight: primary.frame.height)
                if let i = PlayerGeometry.indexWithLargestIntersection(of: rect, in: frames) { return screens[i] }
            }
        }
        if let i = PlayerGeometry.indexContaining(NSEvent.mouseLocation, in: frames) { return screens[i] }
        return NSScreen.main ?? screens[0]
    }

    /// Bounds (CG coordinates) of the first on-screen layer-0 window owned by `pid`, front to back.
    private func frontmostWindowBounds(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 1, rect.height > 1 else { continue }
            return rect
        }
        return nil
    }
}

/// Borderless, non-activating, floats above normal windows on every Space.
final class FloatingPanel: NSPanel {
    /// On every Space, over full-screen apps too, and left alone by Mission Control.
    static let everySpace: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Theme.width, height: 150),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = Self.everySpace
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Readback"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The SwiftUI content resizes the panel by itself when it grows (the reply list opening),
    /// and AppKit keeps the top edge where it was, so the panel grew down and the controls ran
    /// off under the pointer to the bottom of the screen. Keep the bottom edge instead: the bar
    /// stays put and new content opens above it. A move (same size) or a frame placed on purpose
    /// (top edge not kept) goes through untouched.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible, rect.size != frame.size, rect.maxY == frame.maxY {
            rect.origin.y = frame.origin.y
            if let visible = screen?.visibleFrame, rect.maxY > visible.maxY {
                rect.origin.y = visible.maxY - rect.height   // grew past the top: slide it down
            }
        }
        super.setFrame(rect, display: flag)
    }
}

/// Lets the first click on a button work without first focusing the panel. Dragging is done
/// by a WindowDragGesture on the background in PlayerView, not here: marking the whole view
/// as draggable made AppKit treat some button clicks as the start of a window drag.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Esc as a global hotkey, only registered while the panel is showing (the same way
/// superwhisper's recorder takes Esc while it's up). Needs no accessibility permission.
@MainActor
final class EscapeHotKey {
    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<EscapeHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { me.onPress() } }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            if status != noErr { Log.error("couldn't install the Esc handler (OSStatus \(status))") }
        }
        let id = EventHotKeyID(signature: OSType(0x5244_4B31), id: 1)   // "RDK1"
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            Log.error("couldn't register Esc (OSStatus \(status)); another app may own it")
            hotKey = nil
        }
    }

    func unregister() {
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
    }
}
