import Foundation

/// Which reply is read when. Every reply a hook hands over goes into the history; the queue decides
/// whether it's read now, waits its turn, or is only kept, and what plays after it. The app tells
/// it what the reader is doing and carries out the `Step` it returns.
public struct ReplyQueue: Equatable {
    public var history: ReplyHistory

    /// What the reader is on, as far as the queue cares. nil when the player is closed.
    public struct Reading: Equatable {
        /// nil: not a reply from the history (a voice sample).
        public var replyID: UUID?
        public var session: String?
        /// Preparing, playing or paused. False once it finished and only sits in the player.
        public var isSpeaking: Bool

        public init(replyID: UUID?, session: String?, isSpeaking: Bool) {
            self.replyID = replyID
            self.session = session
            self.isSpeaking = isSpeaking
        }
    }

    public enum Step: Equatable {
        case nothing
        /// Read this reply now, in place of whatever is playing. `cue`: it started by itself, so
        /// the cue sound warns first.
        case play(Reply, cue: Bool)
        /// Stop this reading, then, after a moment, ask `playNext`: the session moved on, others carry on.
        case stopThenNext
        /// Stop, and play nothing after: the person wants quiet.
        case quiet
    }

    /// How long a reply /read added waits for its own Stop hook: the hooks' timeout. Past that,
    /// the hook isn't coming (it skipped the reply, Readback wasn't running).
    public static let hookWait: TimeInterval = 15

    /// When each session's latest turn began: its prompt hook's stop. A reply that arrived before
    /// then is an earlier turn's, even when it says the same words, so /read never takes it for
    /// this turn's. Every tool sends that stop (Claude Code's UserPromptSubmit, Codex's prompt
    /// hook, OpenCode's busy event); the mod's /read and /speak run without one.
    private var turnStarted: [String: Date] = [:]

    /// Anything left waiting when the app last quit isn't news any more: it's kept, not queued.
    public init(restoring history: ReplyHistory = ReplyHistory()) {
        self.history = history
        self.history.markAll(where: { $0.state == .waiting }, .kept)
        // A hook that was on its way when the app quit isn't coming to this run.
        for reply in history.replies where reply.awaitingHookSince != nil {
            self.history.update(reply.id) { $0.awaitingHookSince = nil }
        }
    }

    /// A hook handed over a reply. `switchedOn`: its session or tool reads replies without being
    /// asked. `cutIn`: the person chose new replies over waiting their turn.
    public mutating func received(_ request: SpeakRequest, switchedOn: Bool, reading: Reading?, cutIn: Bool, now: Date = Date()) -> Step {
        let asked = request.autoplay == true
        let wanted = request.autoplay ?? switchedOn
        // /read already added (and read) this one from the tool's copy, moments ago.
        if !asked, let early = history.replies.first(where: {
            $0.session == request.session && $0.text == request.text
                && $0.awaitingHookSince.map { now.timeIntervalSince($0) < Self.hookWait } == true
        }) {
            history.update(early.id) { $0.awaitingHookSince = nil }
            return .nothing
        }
        let reply = Reply(request, state: wanted ? .waiting : .kept, received: now)
        history.add(reply)
        guard wanted else { return .nothing }
        // Asked for just now (`readback say`): read it, no warning.
        if asked { return start(reply.id, cue: false) }
        if cutIn { return start(reply.id, cue: true) }
        // Nothing reading: the oldest waiting one goes first, which is this one unless others
        // are queued ahead of it.
        return playNext(reading: reading)
    }

    /// /read: the session's last reply now. `asSent`: the reply as the tool has it, used when the
    /// history doesn't have it (Readback wasn't running when it finished).
    public mutating func readLast(session: String?, asSent: SpeakRequest? = nil, now: Date = Date()) -> Step {
        let newest = history.replies.first { $0.session == session }
        guard let asSent else {
            return newest.map { start($0.id, cue: false) } ?? .nothing
        }
        // The tool's last reply is the session's newest one here, or it never arrived. An older
        // reply with the same words, or the newest from before this turn's prompt, is another
        // turn. Either way this turn's Stop hook may still be on its way, and its copy is this one.
        let id: UUID
        let turn = session.flatMap { turnStarted[$0] }
        if let newest, newest.text == asSent.text, turn.map({ newest.received >= $0 }) ?? true {
            id = newest.id
        } else {
            let reply = Reply(asSent, state: .waiting, received: now)
            history.add(reply)
            id = reply.id
        }
        history.update(id) { $0.awaitingHookSince = now }
        return start(id, cue: false)
    }

    /// A person picked a reply: the player's list, History, the menu's Read last reply.
    public mutating func play(_ id: UUID) -> Step {
        start(id, cue: false)
    }

    /// The oldest waiting reply, if nothing is reading.
    public mutating func playNext(reading: Reading?) -> Step {
        guard reading?.isSpeaking != true else { return .nothing }
        while let next = history.nextWaiting {
            let step = start(next.id, cue: true)
            if step != .nothing { return step }
        }
        return .nothing
    }

    /// A session's new-message hook: the person moved on there, so its waiting replies are only
    /// kept, and its reading stops. Other sessions' replies, a sample and `readback say` carry on.
    /// `newTurn`: a prompt hook's stop. The person started a new turn, so the next Stop hook here
    /// is that turn's reply, not the one /read already played. A Stop button only stops.
    public mutating func stop(session: String, reading: Reading?, newTurn: Bool = false, now: Date = Date()) -> Step {
        history.markAll(where: { $0.state == .waiting && $0.session == session }, .kept)
        if newTurn {
            turnStarted[session] = now
            for reply in history.replies where reply.session == session && reply.awaitingHookSince != nil {
                history.update(reply.id) { $0.awaitingHookSince = nil }
            }
        }
        guard let reading, reading.replyID != nil, reading.session == session else { return .nothing }
        return .stopThenNext
    }

    /// The reader couldn't voice it (the engine failed). It was never heard, so it's kept to be
    /// played again from the history; the caller then moves on with `playNext`.
    public mutating func readingFailed(_ id: UUID) {
        if history.reply(id)?.state == .played { history.mark(id, .kept) }
        if history.beingRead == id { history.beingRead = nil }
    }

    /// Close, Esc, the menu's Stop: quiet. What was waiting stays in the history, unplayed.
    public mutating func stopAll() -> Step {
        history.markAll(where: { $0.state == .waiting }, .kept)
        return .quiet
    }

    /// Marks it played and hands it to the reader, or, with nothing in it to say, keeps it.
    private mutating func start(_ id: UUID, cue: Bool) -> Step {
        guard let reply = history.reply(id) else { return .nothing }
        guard SpeechText.isSpeakable(reply.text) else {
            if reply.state == .waiting { history.mark(id, .kept) }
            return .nothing
        }
        var played = reply
        played.state = .played
        // It stays in the history while it's read, even past the cap; the last one read gives way
        // once this one takes its place.
        history.beingRead = id
        history.mark(id, .played)
        return .play(played, cue: cue)
    }
}
