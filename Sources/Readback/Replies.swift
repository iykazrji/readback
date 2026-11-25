import Foundation
import ReadbackCore

/// The reply history the player and menu show, saved to
/// ~/Library/Application Support/Readback/history.json so it survives a restart.
@MainActor
final class Replies: ObservableObject {
    @Published private(set) var history: ReplyHistory
    /// Whether the player shows its list of replies.
    @Published var showingList = false

    private let file = ReadbackPaths().support.appendingPathComponent("history.json")

    init() {
        var loaded = ReplyHistory.load(from: file) ?? ReplyHistory()
        // Anything left waiting when the app last quit isn't news any more: keep it, don't queue it.
        for reply in loaded.replies where reply.state == .waiting { loaded.mark(reply.id, .kept) }
        history = loaded
    }

    var all: [Reply] { history.replies }
    var waitingCount: Int { history.waitingCount }
    var nextWaiting: Reply? { history.nextWaiting }
    var newest: Reply? { history.replies.first }

    func add(_ reply: Reply) { change { $0.add(reply) } }
    func mark(_ id: UUID, _ state: Reply.State) { change { $0.mark(id, state) } }
    func clear() { change { $0.clear() } }
    func clearForUndo() -> [Reply] {
        var gone: [Reply] = []
        change { gone = $0.clearForUndo() }
        return gone
    }
    func restore(_ cleared: [Reply]) { change { $0.restore(cleared) } }
    func remove(_ id: UUID) { change { $0.remove(id) } }

    // MARK: All-time numbers for Home (the history itself keeps only the latest 50)

    @Published private(set) var repliesRead = UserDefaults.standard.integer(forKey: "stats.repliesRead")
    @Published private(set) var wordsHeard = UserDefaults.standard.integer(forKey: "stats.wordsHeard")

    func countPlay(of reply: Reply) {
        repliesRead += 1
        wordsHeard += SpeechText.clean(reply.text).split(whereSeparator: \.isWhitespace).count
        UserDefaults.standard.set(repliesRead, forKey: "stats.repliesRead")
        UserDefaults.standard.set(wordsHeard, forKey: "stats.wordsHeard")
    }

    private func change(_ edit: (inout ReplyHistory) -> Void) {
        edit(&history)
        do {
            try history.save(to: file)
        } catch {
            Log.error("couldn't save the reply history: \(error)")
        }
    }
}
