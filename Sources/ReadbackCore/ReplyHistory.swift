import Foundation

/// One reply Readback was handed, read or not.
public struct Reply: Codable, Identifiable, Equatable {
    public enum State: String, Codable {
        /// Meant to be read, waiting for its turn.
        case waiting
        /// Has been (or is being) read.
        case played
        /// Nobody asked to read it; kept so it can be played from the history.
        case kept
    }

    public let id: UUID
    public var text: String
    public var source: String?
    public var cwd: String?
    public var session: String?
    public var received: Date
    public var state: State
    /// When /read played this as the tool's last reply. Until that turn's Stop hook comes in
    /// (at most `ReplyQueue.hookWait`, and never past the session's next prompt), the hook's
    /// copy joins this one rather than being a second reply.
    public var awaitingHookSince: Date?

    public init(id: UUID = UUID(), text: String, source: String?, cwd: String?, session: String?,
                received: Date = Date(), state: State) {
        self.id = id
        self.text = text
        self.source = source
        self.cwd = cwd
        self.session = session
        self.received = received
        self.state = state
    }

    public init(_ request: SpeakRequest, state: State, received: Date = Date()) {
        self.init(text: request.text, source: request.source, cwd: request.cwd, session: request.session,
                  received: received, state: state)
    }

    public var request: SpeakRequest {
        SpeakRequest(text: text, source: source, cwd: cwd, autoplay: true, session: session)
    }

    public var title: String { request.title }

    /// The first words of the reply as it would be read, on one line.
    public var preview: String {
        let spoken = SpeechText.clean(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return spoken.count > 140 ? String(spoken.prefix(140)) + "…" : spoken
    }
}

/// Recent replies, newest first, capped. Replies still waiting to be read, and the one being
/// read, are never dropped to make room; the oldest finished ones go first.
public struct ReplyHistory: Codable, Equatable {
    public private(set) var replies: [Reply] = []
    public var limit: Int
    /// The reply being read. It stays while it's read, even past the cap, so a reading that fails
    /// before it's heard can keep it to play again. Not saved: after a relaunch nothing is reading.
    public var beingRead: UUID?

    private enum CodingKeys: String, CodingKey { case replies, limit }

    public init(limit: Int = 50) {
        self.limit = limit
    }

    public mutating func add(_ reply: Reply) {
        replies.insert(reply, at: 0)
        trim()
    }

    /// A reply that stops waiting can be dropped again, so the cap applies here too.
    public mutating func mark(_ id: UUID, _ state: Reply.State) {
        guard let i = replies.firstIndex(where: { $0.id == id }) else { return }
        replies[i].state = state
        trim()
    }

    public mutating func update(_ id: UUID, _ change: (inout Reply) -> Void) {
        guard let i = replies.firstIndex(where: { $0.id == id }) else { return }
        change(&replies[i])
    }

    /// Marks every reply that matches, then applies the cap once, so the newest survive.
    public mutating func markAll(where matches: (Reply) -> Bool, _ state: Reply.State) {
        for i in replies.indices where matches(replies[i]) { replies[i].state = state }
        trim()
    }

    public func reply(_ id: UUID) -> Reply? { replies.first { $0.id == id } }

    /// The reply that has waited longest: replies play in the order they arrived.
    public var nextWaiting: Reply? { replies.last { $0.state == .waiting } }

    public var waitingCount: Int { replies.filter { $0.state == .waiting }.count }

    public mutating func remove(_ id: UUID) {
        replies.removeAll { $0.id == id }
    }

    public mutating func clear() {
        replies.removeAll { $0.state != .waiting }
    }

    /// Clears like `clear()` and hands back what went, so it can be undone.
    public mutating func clearForUndo() -> [Reply] {
        let gone = replies.filter { $0.state != .waiting }
        clear()
        return gone
    }

    /// Puts cleared replies back among whatever arrived since: newest first, nothing twice,
    /// and within the limit (the oldest finished ones give way, as in `add`).
    public mutating func restore(_ cleared: [Reply]) {
        let present = Set(replies.map(\.id))
        // Both lists are newest first, and what arrived since comes before what was cleared, so
        // a tie in time keeps that order (a plain sort isn't stable).
        let merged = (replies + cleared.filter { !present.contains($0.id) }).enumerated()
        replies = merged.sorted { $0.element.received != $1.element.received ? $0.element.received > $1.element.received : $0.offset < $1.offset }
            .map(\.element)
        trim()
    }

    /// Over the limit, the oldest finished replies go; waiting ones and the one being read never do.
    private mutating func trim() {
        while replies.count > limit, let i = replies.lastIndex(where: { $0.state != .waiting && $0.id != beingRead }) {
            replies.remove(at: i)
        }
    }

    // MARK: Saving

    /// nil when there's no saved history yet. Throws when there is one it can't read, so the
    /// caller can keep that file rather than save over it.
    public static func load(from url: URL) throws -> ReplyHistory? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // Fractional seconds since 0.5; whole seconds before.
            guard let date = Self.timeFormat(fractional: true).date(from: text) ?? Self.timeFormat(fractional: false).date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 time"))
            }
            return date
        }
        return try decoder.decode(ReplyHistory.self, from: Data(contentsOf: url))
    }

    /// Times keep their fractions of a second: two replies within one second otherwise come back
    /// tied, and Home could show the older one as a session's newest (deep review 2026-11-26, P2-9).
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        let format = Self.timeFormat(fractional: true)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format.string(from: date))
        }
        try PrivateFiles.write(encoder.encode(self), to: url)
    }

    private static func timeFormat(fractional: Bool) -> ISO8601DateFormatter {
        let format = ISO8601DateFormatter()
        format.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return format
    }
}
