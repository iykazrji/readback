import Foundation
import ReadbackCore

/// The reply queue and its history, saved to ~/Library/Application Support/Readback/history.json
/// so it survives a restart.
@MainActor
final class Replies: ObservableObject {
    @Published private(set) var queue: ReplyQueue
    /// Whether the player shows its list of replies.
    @Published var showingList = false

    /// A thread just muted from the player: the player says so, with Unmute, for its usual few
    /// seconds (owner's mockup, 2026-11-26). Cleared when another reply starts or the player closes.
    struct MutedNotice: Equatable {
        let thread: String
        let project: String
    }
    @Published var mutedNotice: MutedNotice?
    /// Why the last save failed, until one works again. The history on screen is then ahead of
    /// the one on disk, and History says so.
    @Published private(set) var saveError: String?

    private let file = ReadbackPaths().support.appendingPathComponent("history.json")

    /// Set when an unreadable history couldn't be moved aside: saving would write over it, so
    /// nothing is saved this run.
    private var keepFileAsIs = false

    init() {
        var saved: ReplyHistory?
        do {
            saved = try ReplyHistory.load(from: file)
        } catch {
            // Kept for whoever wants to look, under a name of its own so an earlier one stays too.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = file.appendingPathExtension("unreadable-\(stamp)")
            do {
                try FileManager.default.moveItem(at: file, to: aside)
                // Its name, not its path: a path names the person (deep review 2026-11-26, P2-4's class).
                Log.error("couldn't read the reply history (\(error)); moved it aside as \(aside.lastPathComponent), beside the new one")
            } catch let moveError {
                keepFileAsIs = true
                Log.error("couldn't read the reply history (\(error)) or move it aside (\(moveError)); not saving over it")
            }
        }
        queue = ReplyQueue(restoring: saved ?? ReplyHistory())
        if keepFileAsIs { saveError = "the saved history couldn't be read or moved aside, so Readback won't write over it" }
    }

    var all: [Reply] { queue.history.replies }
    var waitingCount: Int { queue.history.waitingCount }
    var newest: Reply? { queue.history.replies.first }

    /// Runs a queue decision and saves what it changed.
    func decide(_ decision: (inout ReplyQueue) -> ReplyQueue.Step) -> ReplyQueue.Step {
        var step = ReplyQueue.Step.nothing
        change { step = decision(&$0) }
        return step
    }

    func clearForUndo() -> [Reply] {
        var gone: [Reply] = []
        change { gone = $0.history.clearForUndo() }
        return gone
    }
    func restore(_ cleared: [Reply]) { change { $0.history.restore(cleared) } }
    func remove(_ id: UUID) { change { $0.history.remove(id) } }

    // MARK: All-time numbers for Home (the history itself keeps only the latest 50)

    @Published private(set) var repliesRead = UserDefaults.standard.integer(forKey: "stats.repliesRead")
    @Published private(set) var wordsHeard = UserDefaults.standard.integer(forKey: "stats.wordsHeard")

    /// `spoken`: the reply as it's read (already cleaned).
    func countPlay(spoken: String) {
        repliesRead += 1
        wordsHeard += spoken.split(whereSeparator: \.isWhitespace).count
        UserDefaults.standard.set(repliesRead, forKey: "stats.repliesRead")
        UserDefaults.standard.set(wordsHeard, forKey: "stats.wordsHeard")
    }

    /// Saves only when something changed (most prompts change nothing), or to try again after a
    /// save that failed.
    private func change(_ edit: (inout ReplyQueue) -> Void) {
        var next = queue
        edit(&next)
        guard next != queue || saveError != nil else { return }
        queue = next
        guard !keepFileAsIs else { return }
        do {
            try queue.history.save(to: file)
            if saveError != nil { saveError = nil }
        } catch {
            Log.error("couldn't save the reply history: \(error)")
            saveError = "it couldn't write \((file.path as NSString).abbreviatingWithTildeInPath)"
        }
    }
}
