import Foundation
import ReadbackCore

// readback: the command the coding tools' hooks run. It lives inside the app at
// Readback.app/Contents/Helpers/readback and talks to the app's control server (ControlRequest).

let usage = """
usage: readback <command>

  hook <tool>               Stop hook for claude, codex or opencode. Reads the hook's JSON on stdin,
                            prints {} and hands the reply to Readback, which reads it if read-aloud is
                            on for that session or tool.
  stop                      Stops the reading. As a UserPromptSubmit hook (JSON on stdin) it only
                            stops that session's reading, and nothing when the hook names no session.
  prompt codex              Codex's UserPromptSubmit hook: answers /speak on|off and /read itself
                            (Codex never sends them to the model), and otherwise works like stop.
  read                      Reads the last reply now: hook-style JSON on stdin (last_assistant_message, session_id).
  say <text>                Reads some text now.
  session <id> [on|off]     Read-aloud for one session.
  auto <tool> [on|off]      Read every reply from a tool.
  voice [engine] [voice]    Shows or sets the voice: engine is system, kokoro, melo, soprano, qwen3 or custom,
                            e.g. `readback voice kokoro bm_george`, `readback voice qwen3 aiden`.
  engine [install|remove]   Shows, installs or removes the on-device voice engine.
  wait                      Waits while Readback is reading.
  status                    What Readback is doing.
  connect <tool>            Connects claude, codex or opencode (edits their config; keeps a backup).
  disconnect <tool>
  integrations              Shows which tools are connected.
"""

let base = URL(string: "http://127.0.0.1:\(ReadbackApp.port())")!

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("readback: \(message)\n".utf8))
    exit(code)
}

/// Appends to ~/Library/Logs/Readback/cli.log, since a hook's stderr usually goes nowhere visible.
func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    do {
        try LogFile.append(line, to: ReadbackPaths().logs.appendingPathComponent("cli.log"))
    } catch {
        FileHandle.standardError.write(Data("readback: couldn't write the log: \(error)\n".utf8))
    }
}

// MARK: HTTP

struct Response {
    let status: Int
    let data: Data
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
    func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
}

/// When this run has to be done by, as uptime. Hooks set it (`within`); other commands have none.
var deadline = TimeInterval.infinity
func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
/// Gives this run `seconds` from now. Every request and wait below stays inside it.
func within(_ seconds: TimeInterval) { deadline = now() + seconds }

func send(_ method: String, _ path: String, body: Data?, timeout: TimeInterval) -> Response? {
    let timeout = min(timeout, deadline - now())
    guard timeout > 0.05 else { return nil }
    var req = URLRequest(url: base.appendingPathComponent(path))
    req.httpMethod = method
    req.timeoutInterval = timeout
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
    }
    let done = DispatchSemaphore(value: 0)
    var result: Response?
    let task = URLSession.shared.dataTask(with: req) { data, response, error in
        if let http = response as? HTTPURLResponse {
            result = Response(status: http.statusCode, data: data ?? Data())
        } else if let error, timeout > 1 {
            log("\(method) /\(path) failed: \(error.localizedDescription)")
        }
        done.signal()
    }
    task.resume()
    if done.wait(timeout: .now() + timeout) == .timedOut {
        task.cancel()
        _ = done.wait(timeout: .now() + 0.2)
        return nil
    }
    return result
}

func get(_ path: String, timeout: TimeInterval = 5) -> Response? {
    send("GET", path, body: nil, timeout: timeout)
}

func post<Body: Encodable>(_ path: String, _ body: Body, timeout: TimeInterval = 5) -> Response? {
    send("POST", path, body: try? JSONEncoder().encode(body), timeout: timeout)
}

func isUp() -> Bool { get("health", timeout: 1)?.status == 200 }

/// This executable's real path, through any symlink (argv[0] is just "readback" when it's run
/// from PATH, so it can't be used).
let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let bundle = AppBundle(helper: executable)

/// What the tools allow a hook before giving up on it (Codex.swift, Integrations.swift), less a
/// margin for the process itself to start and exit.
let replyHookBudget: TimeInterval = 8    // Stop hooks and Codex's prompt hook: 10 s
let stopHookBudget: TimeInterval = 4     // Claude Code's UserPromptSubmit hook: 5 s

/// Starts Readback in the background if it isn't running, and waits for it to answer: up to
/// 20 s, and never past this run's deadline.
func ensureApp() -> Bool {
    if isUp() { return true }
    let giveUp = min(deadline, now() + 20)
    // --background: started by a hook, so no window pops up over the person's work.
    let target = (bundle.map { ["-g", "-a", $0.url.path] } ?? ["-g", "-b", ReadbackApp.bundleID]) + ["--args", "--background"]
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = target
    do { try open.run() } catch {
        log("couldn't start Readback: \(error)")
        return false
    }
    while now() < giveUp - 0.3 {
        if !open.isRunning, isUp() { return true }
        Thread.sleep(forTimeInterval: 0.25)
    }
    log("Readback didn't answer on \(base) in time after starting it")
    return false
}

func readPayload() -> HookPayload {
    guard isatty(0) == 0 else { return HookPayload(json: [:]) }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let payload = HookPayload.parse(data) else {
        log("\(command): stdin wasn't a JSON object (\(data.count) bytes)")
        return HookPayload(json: [:])
    }
    return payload
}

func speak(_ request: SpeakRequest) -> Bool {
    guard ensureApp() else { return false }
    guard let response = post("speak", request), response.status == 202 else {
        log("/speak failed for \(request.source ?? "?")")
        return false
    }
    return true
}

func printJSON(_ object: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
}

func onOff(_ arg: String?) -> Bool? {
    switch arg?.lowercased() {
    case "on": return true
    case "off": return false
    case nil: return nil
    default: fail("expected on or off, got \(arg!)", code: 2)
    }
}

func integrationFiles() -> IntegrationFiles {
    guard let bundle else { fail("run this from inside Readback.app (\(AppBundle.cliPath))") }
    return bundle.integrationFiles(paths: ReadbackPaths())
}

/// A UserPromptSubmit answer that keeps the prompt from reaching the model and shows `reason`.
func blockPrompt(_ reason: String) -> Never {
    printJSON(["decision": "block", "reason": reason])
    exit(0)
}

func tool(_ arg: String?) -> Tool {
    guard let arg, let tool = Tool(source: arg) else { fail("expected claude, codex or opencode", code: 2) }
    return tool
}

// MARK: Commands

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "" : args.removeFirst()

switch command {
case "hook":
    within(replyHookBudget)
    let source = tool(args.first)
    let payload = readPayload()
    print("{}")   // Codex wants JSON on stdout from a Stop hook; Claude Code accepts it.
    fflush(stdout)
    if payload.isBackgroundJob(source) {
        log("\(source.rawValue): skipped a reply from a background job (no saved chat)")
        exit(0)
    }
    guard let reply = payload.speakRequest(from: source) else {
        log("\(source.rawValue): the hook had no reply text")
        exit(0)
    }
    // Running: hand it over (it's kept for "Read last reply" even when it isn't read).
    // Not running: only start Readback when this reply is meant to be read, so quitting
    // Readback isn't undone by the next reply in some other session.
    if isUp() || ReadingSwitches.forCLI()?.wantsReading(tool: source, session: reply.session) == true {
        _ = speak(reply)
    }

case "read":
    let payload = readPayload()
    guard let text = payload.replyText() else { fail("no last_assistant_message on stdin") }
    let source = payload.source.flatMap(Tool.init(source:)) ?? .claude
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    let asked = CommandRequest(command: .read, tool: source, session: payload.session, text: text, cwd: payload.cwd)
    let response = post("command", asked)
    if response?.status == 404 { fail(CommandAnswer.appIsOlder) }
    guard let answer = response?.decode(CommandReply.self) else { fail("Readback didn't take it (see ~/Library/Logs/Readback/cli.log)") }
    print(answer.text)

case "say":
    let text = args.joined(separator: " ")
    guard !text.isEmpty else { fail("nothing to say", code: 2) }
    if !speak(SpeakRequest(text: text, source: "Readback", autoplay: true)) { fail("Readback didn't take it") }

case "stop":
    let input = isatty(0) == 0 ? FileHandle.standardInput.readDataToEndOfFile() : Data()
    if !input.isEmpty { within(stopHookBudget) }
    let stop = StopRequest.fromCLI(stdin: input)
    guard isUp() else { exit(0) }
    guard let stop else {
        log("stop: nothing stopped (the hook named no session, or the prompt was one of Readback's own commands)")
        exit(0)
    }
    _ = post("stop", stop)

case "prompt":
    within(replyHookBudget)
    let source = tool(args.first)
    let payload = readPayload()
    let prompt = payload.prompt
    guard let asked = PromptCommand(prompt: prompt) else {
        // Something that starts like a command but didn't parse: note its start, so a new way
        // of writing the command (a Codex update) shows up in the log rather than going unseen.
        if let shape = PromptCommand.nearMiss(prompt) {
            log("\(source.rawValue): a prompt shaped like a command wasn't /speak or /read: \(shape)")
        }
        // An ordinary prompt: stop this session's reading, like `stop`. Print nothing, since
        // Codex adds a UserPromptSubmit hook's plain output to the conversation.
        if isUp(), let stop = payload.stopRequest { _ = post("stop", stop) }
        exit(0)
    }
    guard let session = payload.session else { blockPrompt("Readback couldn't tell which chat this is, so it can't change anything here.") }
    guard ensureApp() else { blockPrompt("Readback isn't running and couldn't be started. Open Readback from your Applications folder.") }
    var request = CommandRequest(asked, tool: source, session: session)
    // /read: the chat's last reply from its transcript, in case the Stop hook never got it to
    // Readback (it wasn't running then, and nothing asked for the reply to be read).
    if case .read = asked { request.text = payload.finishedTranscriptReply(); request.cwd = payload.cwd }
    let response = post("command", request)
    if response?.status == 404 { blockPrompt(CommandAnswer.appIsOlder) }
    guard let answer = response?.decode(CommandReply.self) else {
        blockPrompt("Readback didn't answer. See ~/Library/Logs/Readback.")
    }
    blockPrompt(answer.text)

case "session":
    guard let id = args.first, !id.isEmpty else { fail("usage: readback session <id> [on|off]", code: 2) }
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    guard let response = post("session", SessionRequest(session: id, enabled: onOff(args.dropFirst().first))) else { fail("no answer from Readback") }
    print((response.json["enabled"] as? Bool) == true ? "on" : "off")

case "auto":
    let t = tool(args.first)
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    guard let response = post("auto", AutoRequest(tool: t, enabled: onOff(args.dropFirst().first))) else { fail("no answer from Readback") }
    print("\(t.name): \((response.json["enabled"] as? Bool) == true ? "on" : "off")")

case "voice":
    // readback voice [engine] [voice]   e.g. readback voice kokoro bm_george
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    let body = VoiceRequest(engine: args.first, voice: args.count > 1 ? args[1] : nil, model: args.count > 2 ? args[2] : nil)
    guard let response = post("voice", body) else { fail("no answer from Readback") }
    if response.status != 200 { fail(response.json["error"] as? String ?? "HTTP \(response.status)") }
    printJSON(response.json)

case "engine":
    // readback engine [install|remove]: the on-device voice engine, from the terminal.
    let action = args.first.map(EngineAction.init(rawValue:))
    if action == .some(nil) { fail("usage: readback engine [install|remove]", code: 2) }
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    guard var response = post("engine", EngineRequest(action: action ?? nil)) else { fail("no answer from Readback") }
    // Removing takes a moment (the engine stops first); answer once it's done, so quitting the
    // app straight after, as AGENT-SETUP.md's uninstall does, can't cut it short.
    for _ in 0..<120 where response.json["runtime"] as? String == "removing" {
        Thread.sleep(forTimeInterval: 0.5)
        if let next = post("engine", EngineRequest(action: nil)) { response = next }
    }
    let state = response.json["runtime"] as? String ?? "unknown"
    print(state)
    // Gone, or never could be there (an Intel Mac): either way the uninstall can go on.
    if action == .some(.remove), state != "not installed", state != "unsupported" { exit(1) }

case "wait":
    for _ in 0..<20 {
        if get("health", timeout: 1)?.decode(Health.self)?.speaking == true { break }
        Thread.sleep(forTimeInterval: 0.25)
    }
    while get("health", timeout: 1)?.decode(Health.self)?.speaking == true {
        Thread.sleep(forTimeInterval: 0.5)
    }

case "status":
    guard let response = get("health", timeout: 1) else {
        print("Readback isn't running")
        exit(1)
    }
    printJSON(response.json)

case "connect", "disconnect":
    let home = ToolHome(tool(args.first))
    let files = integrationFiles()
    do {
        if command == "connect" { try files.connect(home) } else { try files.disconnect(home) }
        print("\(home.title): \(command == "connect" ? "connected" : "disconnected")")
        if command == "connect", (try? files.status(home)) == .waitingForApproval {
            print("\(home.tool.name) runs the plugin's two hooks only after you approve them: Settings > Hooks in the Codex app, or /hooks in the terminal. Quit and reopen the Codex app if it's open.")
        }
    } catch {
        fail("\(error)")
    }

case "integrations":
    let files = integrationFiles()
    for t in Tool.allCases {
        let home = ToolHome(t)
        let state: String
        if !files.isInstalled(home) { state = "not installed" } else {
            switch (try? files.status(home)) ?? .notConnected {
            case .connected: state = "connected"
            case .waitingForApproval: state = "connected, waiting for you to approve its hooks in \(t.name)"
            case .notConnected: state = "not connected"
            case .stale(let other): state = "connected to another copy of Readback (\(other))"
            case .incomplete: state = "partly connected (a hook or command is missing); run `readback connect \(t.rawValue)` to repair it"
            case .outdated: state = "connected the old way (no /speak or /read); run `readback connect codex` to update"
            case .updateAvailable: state = "connected; a newer version of its plugin is ready: run `readback connect codex` to install it"
            }
        }
        print("\(t.name): \(state)")
    }

case "", "help", "-h", "--help":
    print(usage)

default:
    fail("unknown command \(command)\n\n\(usage)", code: 2)
}
