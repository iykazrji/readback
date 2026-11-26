import Foundation

/// What a tool's hook hands the CLI on stdin: Claude Code's and Codex's Stop and UserPromptSubmit
/// hooks, and the OpenCode plugin, which sends the same shape.
public struct HookPayload {
    private let json: [String: Any]

    public init(json: [String: Any]) { self.json = json }

    /// nil when there was something on stdin but it wasn't a JSON object. Nothing at all reads as
    /// an empty payload.
    public static func parse(_ data: Data) -> HookPayload? {
        if data.isEmpty { return HookPayload(json: [:]) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).map(HookPayload.init(json:))
    }

    public var session: String? { json["session_id"] as? String }
    public var cwd: String? { json["cwd"] as? String }
    public var prompt: String { json["prompt"] as? String ?? "" }
    public var source: String? { json["source"] as? String }
    private var transcriptPath: String? { json["transcript_path"] as? String }

    /// The reply text: last_assistant_message, or the transcript's last reply for a tool that
    /// leaves it out (Codex's is nullable).
    public func replyText() -> String? {
        if let text = json["last_assistant_message"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return transcriptReply()
    }

    /// The last assistant reply in the transcript file. Reads both layouts: Claude Code's
    /// ({"type":"assistant","message":{"content":[{"type":"text","text":…}]}}) and Codex's rollout
    /// ({"type":"event_msg","payload":{"type":"task_complete","last_agent_message":…}}, or a
    /// "response_item" whose payload is an assistant "message" with "output_text" parts).
    public func transcriptReply() -> String? { scanTranscript(finishedOnly: false) }

    private func scanTranscript(finishedOnly: Bool) -> String? {
        guard let transcriptPath, let content = Self.tail(of: transcriptPath) else { return nil }
        // A Codex item that isn't marked final (progress, or an interrupted turn) only counts
        // when no finished turn comes before it.
        var unfinished: String?
        for line in content.split(separator: "\n").reversed() {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let (text, final) = Self.reply(in: row),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if final { return text }
            if unfinished == nil { unfinished = text }
        }
        return finishedOnly ? nil : unfinished
    }

    /// The last 2 MB of the file, as whole lines: a long chat's transcript is far bigger, and a
    /// hook has seconds.
    private static func tail(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 2_000_000 ? size - 2_000_000 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let firstBreak = text.firstIndex(of: "\n") { text = String(text[text.index(after: firstBreak)...]) }
        return text
    }

    /// The reply text in a transcript line, and whether it's a finished reply.
    private static func reply(in row: [String: Any]) -> (String, Bool)? {
        func texts(_ parts: Any?, type: String) -> String? {
            let joined = (parts as? [[String: Any]] ?? []).filter { $0["type"] as? String == type }
                .compactMap { $0["text"] as? String }.joined(separator: "\n\n")
            return joined.isEmpty ? nil : joined
        }
        let payload = row["payload"] as? [String: Any]
        switch (row["type"] as? String, payload?["type"] as? String) {
        case ("assistant", _):
            return texts((row["message"] as? [String: Any])?["content"], type: "text").map { ($0, true) }
        case ("event_msg", "task_complete"?), ("event_msg", "turn_complete"?):
            return (payload?["last_agent_message"] as? String).map { ($0, true) }
        case ("response_item", "message"?) where payload?["role"] as? String == "assistant":
            let phase = payload?["phase"] as? String
            // Commentary is the agent working, never its reply.
            guard phase != "commentary" else { return nil }
            return texts(payload?["content"], type: "output_text").map { ($0, phase == "final_answer") }
        default:
            return nil
        }
    }

    /// Codex runs hooks for its own background jobs too (the app's task suggestions), whose
    /// "reply" is JSON like {"suggestions":[]}. Those threads are never saved, so their
    /// transcript_path is empty or names no file; a chat a person is in always has one.
    public func isBackgroundJob(_ tool: Tool, fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> Bool {
        guard tool == .codex else { return false }
        guard let transcriptPath, !transcriptPath.isEmpty else { return true }
        return !fileExists(transcriptPath)
    }

    /// The transcript's last finished reply only: what /read sends, so half-done text never
    /// replaces a finished reply the app already has.
    public func finishedTranscriptReply() -> String? { scanTranscript(finishedOnly: true) }

    /// The stop a new-message hook sends: only for its own session. nil when the hook named no
    /// session, so a hook can never stop every session's reading (only a person can: Close, Esc,
    /// the menu, `readback stop` typed in a terminal).
    public var stopRequest: StopRequest? {
        guard let session, !session.isEmpty else { return nil }
        // Readback's own command (Claude Code's /readback:read and /readback:speak are files, so
        // its prompt hook may see them) isn't a new turn and stops nothing: /readback:read is
        // about to read the reply this turn already has.
        guard PromptCommand(prompt: prompt) == nil else { return nil }
        return StopRequest(session: session, newTurn: true)
    }

    /// The finished reply as POST /speak takes it.
    public func speakRequest(from tool: Tool) -> SpeakRequest? {
        replyText().map { SpeakRequest(text: $0, source: tool.rawValue, cwd: cwd, session: session) }
    }
}

extension StopRequest {
    /// `readback stop`: nothing on stdin is a person (a terminal, a script, a Shortcut) and stops
    /// everything; a hook's JSON stops only its session, and nothing when it names none.
    public static func fromCLI(stdin: Data) -> StopRequest? {
        guard !stdin.isEmpty else { return StopRequest(session: nil) }
        return HookPayload.parse(stdin)?.stopRequest
    }
}
