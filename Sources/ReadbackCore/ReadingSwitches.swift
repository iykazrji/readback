import Foundation

/// The switches that decide whether a reply is read without being asked: the overall "read replies
/// out loud" (which can be off for a while), a thread's mute, a session's read-aloud (/speak on) and
/// a tool's "read every reply". Saved in the app's UserDefaults. The CLI reads them straight from
/// there, so a hook never has to start the app just to ask; both go through this.
///
/// A thread is a SessionSummary key: the tool's session id (OpenCode's plugin sends one too), or
/// folder and tool for a reply that came without one.
public struct ReadingSwitches {
    private let defaults: UserDefaults

    /// The app passes `.standard` (its own domain). Anything else uses `forCLI()`.
    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// The app's settings, from another process.
    public static func forCLI() -> ReadingSwitches? {
        UserDefaults(suiteName: ReadbackApp.bundleID).map(ReadingSwitches.init(defaults:))
    }

    private static func everyReplyKey(_ tool: Tool) -> String { "autoRead.\(tool.rawValue)" }
    private static let sessionsKey = "sessionsOn"
    private static let mutedKey = "sessionsMuted"
    private static let offUntilKey = "readingOffUntil"
    /// Each list keeps its newest last; the oldest go past this many.
    private static let sessionLimit = 500

    // MARK: A tool's "read every reply"

    public func readsEveryReply(_ tool: Tool) -> Bool {
        defaults.bool(forKey: Self.everyReplyKey(tool))
    }

    public func setReadsEveryReply(_ tool: Tool, _ on: Bool) {
        defaults.set(on, forKey: Self.everyReplyKey(tool))
    }

    /// Whether "read every reply" was ever set for `tool`, on or off.
    public func hasSetEveryReply(_ tool: Tool) -> Bool {
        defaults.object(forKey: Self.everyReplyKey(tool)) != nil
    }

    /// Whether a connection of `tool` switches "read every reply" on. A new connection reads every
    /// reply out loud, and the person switches it off in Reading (owner, 2026-11-26). `isNew` comes
    /// from IntegrationFiles.connect: an update, a repair or moving to this copy isn't new. And a
    /// switch set before stays as it was, so an earlier off wins (owner, 2026-11-26).
    public func switchesOn(forNewConnectionOf tool: Tool, isNew: Bool) -> Bool {
        isNew && !hasSetEveryReply(tool)
    }

    /// Switches it on when `switchesOn(forNewConnectionOf:isNew:)` says so, checked at the moment
    /// of writing, so an off saved since anyone last looked still wins. True when it switched on.
    @discardableResult
    public func applyNewConnection(of tool: Tool, isNew: Bool) -> Bool {
        guard switchesOn(forNewConnectionOf: tool, isNew: isNew) else { return false }
        setReadsEveryReply(tool, true)
        return true
    }

    // MARK: A thread: on, muted, or as its tool says

    /// /speak on: this thread reads even when its tool doesn't read every reply.
    public func isSessionOn(_ thread: String) -> Bool {
        list(Self.sessionsKey).contains(thread)
    }

    /// /speak off, or a mute in the app: this thread stays quiet even when its tool reads every
    /// reply (owner, 2026-11-26, at a user's request; before that /speak off couldn't beat it).
    public func isMuted(_ thread: String) -> Bool {
        list(Self.mutedKey).contains(thread)
    }

    /// Every muted thread, oldest first.
    public var mutedThreads: [String] { list(Self.mutedKey) }

    /// /speak on or off typed in the thread. On reads it and lifts a mute; off mutes it.
    public func setSession(_ thread: String, _ on: Bool) {
        setList(Self.sessionsKey, thread, on)
        setList(Self.mutedKey, thread, !on)
    }

    /// The app's mute buttons. Unmuting puts the thread back as it was before the mute: on if
    /// /speak on had it on, otherwise as its tool's switch says. A mute beats /speak on in
    /// `wantsReading`, so muting leaves that in place for the unmute (review round 1, 2026-11-26).
    public func setMuted(_ thread: String, _ muted: Bool) {
        setList(Self.mutedKey, thread, muted)
    }

    // MARK: Everything: "read replies out loud"

    /// When reading comes back on by itself, while it's off: `Date.distantFuture` means only when
    /// the person turns it back on. Nil while reading is on, including once a timed off has passed.
    public func readingOff(now: Date = Date()) -> Date? {
        guard let until = defaults.object(forKey: Self.offUntilKey) as? Date, until > now else { return nil }
        return until
    }

    /// Off until `until` (`Date.distantFuture` for "until I turn it back on"), or on with nil.
    public func setReadingOff(until: Date?) {
        if let until { defaults.set(until, forKey: Self.offUntilKey) } else { defaults.removeObject(forKey: Self.offUntilKey) }
    }

    /// Drops a timed off that has ended, so a clock set back can't bring it back unseen. The app
    /// calls it whenever it brings the menu bar icon in line.
    public func forgetEndedOff(now: Date = Date()) {
        guard let until = defaults.object(forKey: Self.offUntilKey) as? Date, until <= now else { return }
        defaults.removeObject(forKey: Self.offUntilKey)
    }

    // MARK: The answer

    /// Whether a reply from this tool and thread is read without being asked. Reading off beats
    /// everything, a mute beats the tool's switch, and /speak on reads a thread its tool doesn't.
    /// What the person asks for (/read, a play button) never comes through here: it always plays.
    public func wantsReading(tool: Tool?, thread: String?, now: Date = Date()) -> Bool {
        if readingOff(now: now) != nil { return false }
        if let thread, isMuted(thread) { return false }
        if let tool, readsEveryReply(tool) { return true }
        return thread.map(isSessionOn) ?? false
    }

    private func list(_ key: String) -> [String] { defaults.stringArray(forKey: key) ?? [] }

    private func setList(_ key: String, _ thread: String, _ member: Bool) {
        var items = list(key).filter { $0 != thread }
        if member { items.append(thread) }
        defaults.set(Array(items.suffix(Self.sessionLimit)), forKey: key)
    }
}
