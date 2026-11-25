import Foundation

/// How everything finds the app: its bundle id and the control server's address.
public enum ReadbackApp {
    public static let bundleID = "local.readback"
    public static let defaultPort: UInt16 = 8908

    /// READBACK_PORT moves both the app and the CLI (a second copy side by side). The Claude Code
    /// mod can't see the environment, so it always uses 8908.
    public static func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        environment["READBACK_PORT"].flatMap(UInt16.init) ?? defaultPort
    }
}

// MARK: Request bodies

/// POST /speak: a reply to keep, and maybe read.
public struct SpeakRequest: Codable, Equatable {
    public var text: String
    public var source: String?
    public var cwd: String?
    /// true: read it now. false: only keep it. Absent: the session's and tool's switches decide.
    public var autoplay: Bool?
    /// The tool's session id, when it sent one: a session switches read-aloud on for itself and
    /// stops only its own reading.
    public var session: String?

    public init(text: String, source: String? = nil, cwd: String? = nil, autoplay: Bool? = nil, session: String? = nil) {
        self.text = text
        self.source = source
        self.cwd = cwd
        self.autoplay = autoplay
        self.session = session
    }

    public var tool: Tool? { source.flatMap(Tool.init(source:)) }

    /// "Claude Code · inkine": the tool, then the project folder it ran in.
    public var title: String {
        let tool = self.tool?.name ?? ((source?.isEmpty == false) ? source! : "Agent")
        guard let cwd, !cwd.isEmpty else { return tool }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        return folder.isEmpty || folder == "/" ? tool : "\(tool) · \(folder)"
    }
}

/// POST /stop. No session, or no body: stop everything.
public struct StopRequest: Codable, Equatable {
    public var session: String?
    /// Sent by a prompt hook: the person started a new turn there. A Stop button only stops.
    public var newTurn: Bool?
    public init(session: String?, newTurn: Bool? = nil) {
        self.session = session
        self.newTurn = newTurn
    }
}

/// POST /session: one session's read-aloud switch. No `enabled`: only say whether it's on.
public struct SessionRequest: Codable, Equatable {
    public var session: String
    public var enabled: Bool?
    public init(session: String, enabled: Bool? = nil) {
        self.session = session
        self.enabled = enabled
    }
}

/// POST /auto: a tool's "read every reply" switch. No `enabled`: only say whether it's on.
public struct AutoRequest: Codable, Equatable {
    public var tool: Tool
    public var enabled: Bool?
    public init(tool: Tool, enabled: Bool? = nil) {
        self.tool = tool
        self.enabled = enabled
    }
}

/// POST /voice: sets any of these that are given.
public struct VoiceRequest: Codable, Equatable {
    public var engine: String?
    public var voice: String?
    public var model: String?
    public var lang: String?
    public init(engine: String? = nil, voice: String? = nil, model: String? = nil, lang: String? = nil) {
        self.engine = engine
        self.voice = voice
        self.model = model
        self.lang = lang
    }
}

public enum EngineAction: String, Codable, CaseIterable {
    case install, remove
}

/// POST /engine. No action: only report the engine's state.
public struct EngineRequest: Codable, Equatable {
    public var action: EngineAction?
    public init(action: EngineAction?) { self.action = action }
}

/// POST /command: someone typed /speak or /read in a tool. The answer is the text to show there.
public struct CommandRequest: Codable, Equatable {
    public enum Command: String, Codable { case speak, read }

    public var command: Command
    public var tool: Tool
    public var session: String?
    /// /speak on or off; nil asks whether it's on.
    public var enabled: Bool?
    /// /read: the last reply as the tool has it, in case it never reached Readback (the app
    /// wasn't running when the reply finished).
    public var text: String?
    public var cwd: String?

    public init(command: Command, tool: Tool, session: String?, enabled: Bool? = nil, text: String? = nil, cwd: String? = nil) {
        self.command = command
        self.tool = tool
        self.session = session
        self.enabled = enabled
        self.text = text
        self.cwd = cwd
    }

    public init(_ asked: PromptCommand, tool: Tool, session: String?) {
        switch asked {
        case .speak(let enabled): self.init(command: .speak, tool: tool, session: session, enabled: enabled)
        case .read: self.init(command: .read, tool: tool, session: session)
        }
    }
}

public struct CommandReply: Codable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

/// GET /health. `runtime` is the text AGENT-SETUP.md tells agents to wait on: "installing: <step>",
/// "installed", "failed: <reason>".
public struct Health: Codable, Equatable {
    public var ok = true
    public var speaking: Bool
    public var phase: String
    /// The session whose reply is being read; null when none.
    public var session: String?
    public var current: Int
    public var count: Int
    public var speed: Double
    public var waiting: Int
    public var history: Int
    public var auto: [String: Bool]
    public var engine: String
    public var runtime: String
    public var version: String
    public var menuBarIcon: String

    public init(speaking: Bool, phase: String, session: String?, current: Int, count: Int, speed: Double,
                waiting: Int, history: Int, auto: [String: Bool], engine: String, runtime: String,
                version: String, menuBarIcon: String) {
        self.speaking = speaking
        self.phase = phase
        self.session = session
        self.current = current
        self.count = count
        self.speed = speed
        self.waiting = waiting
        self.history = history
        self.auto = auto
        self.engine = engine
        self.runtime = runtime
        self.version = version
        self.menuBarIcon = menuBarIcon
    }

    private enum CodingKeys: String, CodingKey {
        case ok, speaking, phase, session, current, count, speed, waiting, history, auto, engine, runtime, version, menuBarIcon
    }

    // The mod tells "no session" from "another session" by a null, so it's written out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ok, forKey: .ok)
        try c.encode(speaking, forKey: .speaking)
        try c.encode(phase, forKey: .phase)
        try c.encode(session, forKey: .session)
        try c.encode(current, forKey: .current)
        try c.encode(count, forKey: .count)
        try c.encode(speed, forKey: .speed)
        try c.encode(waiting, forKey: .waiting)
        try c.encode(history, forKey: .history)
        try c.encode(auto, forKey: .auto)
        try c.encode(engine, forKey: .engine)
        try c.encode(runtime, forKey: .runtime)
        try c.encode(version, forKey: .version)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
    }
}

// MARK: Routes

/// A request to the control server on 127.0.0.1, checked against the route table. The app only
/// does the sockets; this decides what a request means.
public enum ControlRequest: Equatable {
    case health
    case speak(SpeakRequest)
    /// nil session: stop everything. `newTurn`: a prompt hook's stop, not a Stop button's.
    case stop(session: String?, newTurn: Bool = false)
    case command(CommandRequest)
    case session(SessionRequest)
    case auto(AutoRequest)
    case voice(VoiceRequest)
    case engine(EngineAction?)

    public struct Refusal: Error, Equatable {
        public let status: Int
        public let message: String
    }

    /// Only clients on this Mac that talk JSON get through. A web page can't set
    /// `Content-Type: application/json` on a cross-site request without a preflight, which nothing
    /// here answers, and a page that rebinds its domain to 127.0.0.1 still sends its own Host.
    public static func parse(_ request: HTTPRequest, port: UInt16 = ReadbackApp.port()) -> Result<ControlRequest, Refusal> {
        let host = request.headers["host"]?.lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return .failure(Refusal(status: 403, message: "this server only answers 127.0.0.1:\(port)"))
        }
        guard let route = routes[request.path] else { return .failure(Refusal(status: 404, message: "not found")) }
        guard request.method == route.method else { return .failure(Refusal(status: 405, message: "method not allowed")) }
        let mediaType = request.headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        if route.method == "POST", mediaType != "application/json" {
            return .failure(Refusal(status: 415, message: "send Content-Type: application/json"))
        }
        do {
            return .success(try route.parse(request.body))
        } catch {
            return .failure(Refusal(status: 400, message: route.expects))
        }
    }

    private struct Route {
        let method: String
        let expects: String
        let parse: (Data) throws -> ControlRequest
    }

    private struct NoSession: Error {}

    private static func decode<T: Decodable>(_ body: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: body)
    }

    private static func decode<T: Decodable>(_ body: Data, orEmpty empty: T) throws -> T {
        body.isEmpty ? empty : try decode(body)
    }

    private static let routes: [String: Route] = [
        "/health": Route(method: "GET", expects: "", parse: { _ in .health }),
        "/speak": Route(method: "POST", expects: "expected JSON with a text field",
                        parse: { .speak(try decode($0)) }),
        "/stop": Route(method: "POST", expects: #"expected {"session":"<id>"}, or no body to stop everything"#,
                       parse: { body in
                           let stop = try decode(body, orEmpty: StopRequest(session: nil))
                           return .stop(session: stop.session, newTurn: stop.newTurn == true)
                       }),
        "/command": Route(method: "POST", expects: #"expected {"command":"speak|read","tool":"claude|codex|opencode","session":"<id>"}"#,
                          parse: { body in
                              let command: CommandRequest = try decode(body)
                              if command.command == .speak, command.session == nil { throw NoSession() }
                              return .command(command)
                          }),
        "/session": Route(method: "POST", expects: #"expected {"session":"<id>","enabled":true}"#,
                          parse: { .session(try decode($0)) }),
        "/auto": Route(method: "POST", expects: #"expected {"tool":"claude|codex|opencode","enabled":true}"#,
                       parse: { .auto(try decode($0)) }),
        "/voice": Route(method: "POST", expects: #"expected {"engine","voice","model","lang"}"#,
                        parse: { .voice(try decode($0, orEmpty: VoiceRequest())) }),
        "/engine": Route(method: "POST", expects: #"expected {"action":"install|remove"}, or no body to report"#,
                         parse: { .engine(try decode($0, orEmpty: EngineRequest(action: nil)).action) }),
    ]
}

// MARK: Answers

/// What Readback answers when someone types its commands, worded the same in every tool and
/// naming that tool's own commands.
public enum CommandAnswer {
    public static func speak(asked: Bool?, isOn: Bool, everyReply: Bool, tool: Tool) -> String {
        let here = "this \(tool.conversation)"
        if asked == nil, everyReply {
            return "Read-aloud is on in \(here), because Readback reads every \(tool.name) reply. Switch that off in Readback's Reading page; \(tool.readCommand) reads the last reply."
        }
        if asked == nil {
            return "Read-aloud is \(isOn ? "on" : "off") in \(here). \(tool.speakCommand) on or \(tool.speakCommand) off changes it, \(tool.readCommand) reads the last reply."
        }
        if !isOn, everyReply {
            return "Read-aloud is off for \(here), but Readback is set to read every \(tool.name) reply. Switch that off in Readback's Reading page."
        }
        return "Read-aloud is \(isOn ? "on" : "off") for \(here)."
    }

    public static func read(played: Bool, tool: Tool) -> String {
        played ? "Reading the last reply." : "There's no reply in this \(tool.conversation) to read yet."
    }
}

extension Tool {
    /// The command that switches read-aloud for a session, as the person types it there.
    /// Claude Code's are the mod's own `/readback:speak` and `/readback:read` (owner, 2026-11-25:
    /// the bare /speak and /read went away). Codex keeps the names its skill menu sends.
    public var speakCommand: String { self == .claude ? "/readback:speak" : "/speak" }

    /// The command that reads the last reply now.
    public var readCommand: String { self == .claude ? "/readback:read" : "/read" }
}
