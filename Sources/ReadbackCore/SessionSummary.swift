import Foundation

/// One row of Home's Sessions list: the recent replies of one Claude Code session, Codex chat or
/// OpenCode project, grouped so a person sees which agent said what lately. Replies that carry no
/// session (OpenCode's) group by their folder and tool instead.
public struct SessionSummary: Identifiable, Equatable {
    /// The replies' `session`, or `cwd:<cwd>|<source>` when they have none.
    public let id: String
    public let tool: Tool?
    /// The last part of the folder the agent worked in, or the tool's name when there's no folder.
    public let project: String
    public let count: Int
    public let newest: Reply
    /// The session's replies, newest first.
    public let replies: [Reply]
    /// Replies nobody heard, oldest first: filled once replies carry an unheard mark (Piece 4).
    public let unheard: [Reply]

    /// The `limit` most recent sessions, newest first.
    public static func sessions(from replies: [Reply], limit: Int = 8) -> [SessionSummary] {
        let groups = Dictionary(grouping: replies, by: { key(of: $0) })
        let summaries = groups.map { id, group -> SessionSummary in
            let sorted = group.sorted { ($0.received, $1.id.uuidString) > ($1.received, $0.id.uuidString) }
            let newest = sorted[0]
            return SessionSummary(id: id, tool: newest.source.flatMap(Tool.init(source:)), project: project(of: newest), count: sorted.count,
                                  newest: newest, replies: sorted, unheard: [])
        }
        // Newest first; a tie (History keeps whole seconds) always breaks the same way, by id, so
        // the rows never swap places from one redraw to the next.
        return Array(summaries.sorted { ($0.newest.received, $1.id) > ($1.newest.received, $0.id) }.prefix(limit))
    }

    /// The session a reply belongs to, as Home groups it: its `session`, or folder and tool when
    /// it has none. History's filter uses the same key, so "See all" finds the same replies.
    public static func key(of reply: Reply) -> String {
        if let session = reply.session, !session.isEmpty { return session }
        return "cwd:\(reply.cwd ?? "")|\(reply.source ?? "")"
    }

    private static func project(of reply: Reply) -> String {
        let folder = (reply.cwd ?? "").split(separator: "/").last.map(String.init) ?? ""
        return folder.isEmpty ? (reply.source.flatMap(Tool.init(source:))?.name ?? "Agent") : folder
    }
}
