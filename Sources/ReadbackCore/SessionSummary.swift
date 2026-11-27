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
    /// `replies` in History's order, newest first: that order is how they arrived, so it breaks
    /// a tie in time (deep review 2026-11-26, P2-9), and the rows never swap from one redraw to
    /// the next.
    public static func sessions(from replies: [Reply], limit: Int = 8) -> [SessionSummary] {
        let arrival = Dictionary(replies.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func newerFirst(_ a: Reply, _ b: Reply) -> Bool {
            a.received != b.received ? a.received > b.received : arrival[a.id, default: 0] < arrival[b.id, default: 0]
        }
        let groups = Dictionary(grouping: replies, by: { key(of: $0) })
        let summaries = groups.map { id, group -> SessionSummary in
            let sorted = group.sorted(by: newerFirst)
            let newest = sorted[0]
            return SessionSummary(id: id, tool: newest.source.flatMap(Tool.init(source:)), project: project(of: newest), count: sorted.count,
                                  newest: newest, replies: sorted, unheard: [])
        }
        return Array(summaries.sorted { newerFirst($0.newest, $1.newest) }.prefix(limit))
    }

    /// The session a reply belongs to, as Home groups it: its `session`, or folder and tool when
    /// it has none. History's filter uses the same key, so "See all" finds the same replies.
    public static func key(of reply: Reply) -> String {
        key(session: reply.session, cwd: reply.cwd, source: reply.source)
    }

    /// The same key from a reply's parts, for one still on its way in (a SpeakRequest). Muting a
    /// thread uses it too, so a muted OpenCode folder is the same row Home shows.
    public static func key(session: String?, cwd: String?, source: String?) -> String {
        if let session, !session.isEmpty { return session }
        return "cwd:\(cwd ?? "")|\(source ?? "")"
    }

    private static func project(of reply: Reply) -> String {
        let folder = (reply.cwd ?? "").split(separator: "/").last.map(String.init) ?? ""
        return folder.isEmpty ? (reply.source.flatMap(Tool.init(source:))?.name ?? "Agent") : folder
    }
}
