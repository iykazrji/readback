import Foundation

/// Which replies History shows: one session (Home's "See all N replies"), one tool (History's
/// menu), and search words. A session already says which tool, so with a session set the tool
/// doesn't narrow anything further.
public struct ReplyFilter: Equatable {
    /// A `SessionSummary` id, the same key Home groups by.
    public var session: String?
    public var tool: Tool?
    public var query: String

    public init(session: String? = nil, tool: Tool? = nil, query: String = "") {
        self.session = session
        self.tool = tool
        self.query = query
    }

    /// The search words as matched: trimmed, any case.
    public var words: String { query.trimmingCharacters(in: .whitespaces) }

    /// Whether anything is narrowed at all.
    public var isNarrowed: Bool { session != nil || tool != nil || !words.isEmpty }

    public func matches(_ reply: Reply) -> Bool {
        if let session {
            guard SessionSummary.key(of: reply) == session else { return false }
        } else if let tool, reply.request.tool != tool {
            return false
        }
        let words = words
        guard !words.isEmpty else { return true }
        return reply.text.localizedCaseInsensitiveContains(words) || reply.title.localizedCaseInsensitiveContains(words)
    }
}
