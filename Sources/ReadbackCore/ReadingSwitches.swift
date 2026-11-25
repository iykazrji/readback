import Foundation

/// The switches that decide whether a reply is read without being asked: a session's read-aloud
/// (/speak on) and a tool's "read every reply". Saved in the app's UserDefaults. The CLI reads them
/// straight from there, so a hook never has to start the app just to ask; both go through this.
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
    /// Sessions are kept newest last; the oldest go past this many.
    private static let sessionLimit = 500

    public func readsEveryReply(_ tool: Tool) -> Bool {
        defaults.bool(forKey: Self.everyReplyKey(tool))
    }

    public func setReadsEveryReply(_ tool: Tool, _ on: Bool) {
        defaults.set(on, forKey: Self.everyReplyKey(tool))
    }

    public func isSessionOn(_ id: String) -> Bool {
        sessions.contains(id)
    }

    public func setSession(_ id: String, _ on: Bool) {
        var list = sessions.filter { $0 != id }
        if on { list.append(id) }
        defaults.set(Array(list.suffix(Self.sessionLimit)), forKey: Self.sessionsKey)
    }

    /// Whether a reply from this tool and session is read without being asked.
    public func wantsReading(tool: Tool?, session: String?) -> Bool {
        if let tool, readsEveryReply(tool) { return true }
        return session.map(isSessionOn) ?? false
    }

    private var sessions: [String] { defaults.stringArray(forKey: Self.sessionsKey) ?? [] }
}
