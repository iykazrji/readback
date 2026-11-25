import Foundation
import ReadbackCore

// readback: the command the coding tools' hooks run. It lives inside the app at
// Readback.app/Contents/Helpers/readback and talks to the app on 127.0.0.1:8908.

let usage = """
usage: readback <command>

  hook <tool>               Stop hook for claude, codex or opencode. Reads the hook's JSON on stdin,
                            prints {} and hands the reply to Readback, which reads it if read-aloud is
                            on for that session or tool.
  stop                      Stops the reading (UserPromptSubmit hook). With hook JSON on stdin it
                            only stops a reading from that same session.
  prompt codex              Codex's UserPromptSubmit hook: answers /speak on|off and /read itself
                            (Codex never sends them to the model), and otherwise works like stop.
  read                      Reads now: hook-style JSON on stdin (last_assistant_message, session_id).
  say <text>                Reads some text now.
  session <id> [on|off]     Read-aloud for one session (Claude Code's /speak uses this).
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

let port = Int(ProcessInfo.processInfo.environment["READBACK_PORT"] ?? "") ?? 8908
let base = URL(string: "http://127.0.0.1:\(port)")!

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("readback: \(message)\n".utf8))
    exit(code)
}

/// Appends to ~/Library/Logs/Readback/cli.log, since a hook's stderr usually goes nowhere visible.
func log(_ message: String) {
    let paths = ReadbackPaths()
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    do {
        try FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let file = paths.logs.appendingPathComponent("cli.log")
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: file)
        }
    } catch {
        FileHandle.standardError.write(Data("readback: couldn't write the log: \(error)\n".utf8))
    }
}

// MARK: HTTP

struct Response { let status: Int; let json: [String: Any] }

func request(_ method: String, _ path: String, _ body: [String: Any]? = nil, timeout: TimeInterval = 5) -> Response? {
    var req = URLRequest(url: base.appendingPathComponent(path))
    req.httpMethod = method
    req.timeoutInterval = timeout
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    let done = DispatchSemaphore(value: 0)
    var result: Response?
    URLSession.shared.dataTask(with: req) { data, response, _ in
        if let http = response as? HTTPURLResponse {
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            result = Response(status: http.statusCode, json: json)
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + timeout + 1)
    return result
}

func isUp() -> Bool { request("GET", "health", timeout: 1)?.status == 200 }

/// This executable's real path, through any symlink (argv[0] is just "readback" when it's run
/// from PATH, so it can't be used).
let executablePath: String = {
    let path = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return path.resolvingSymlinksInPath().path
}()

/// The app this CLI sits in: …/Readback.app/Contents/Helpers/readback → …/Readback.app.
var appURL: URL? {
    let exe = URL(fileURLWithPath: executablePath)
    let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}

/// Starts Readback in the background if it isn't running, and waits for it to answer.
func ensureApp() -> Bool {
    if isUp() { return true }
    // --background: started by a hook, so no window pops up over the person's work.
    let target = (appURL.map { ["-g", "-a", $0.path] } ?? ["-g", "-b", "local.readback"]) + ["--args", "--background"]
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = target
    do { try open.run(); open.waitUntilExit() } catch {
        log("couldn't start Readback: \(error)")
        return false
    }
    for _ in 0..<32 {
        if isUp() { return true }
        Thread.sleep(forTimeInterval: 0.25)
    }
    log("Readback didn't answer on \(base) after starting it")
    return false
}

// MARK: stdin

func readStdinJSON() -> [String: Any] {
    guard isatty(0) == 0 else { return [:] }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

/// The reply text from a Stop hook's payload, falling back to the transcript file for tools
/// that don't send last_assistant_message.
func replyText(_ payload: [String: Any]) -> String? {
    if let text = payload["last_assistant_message"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return text
    }
    guard let path = payload["transcript_path"] as? String,
          let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in content.split(separator: "\n").suffix(400).reversed() {
        guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              row["type"] as? String == "assistant",
              let message = row["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]] else { continue }
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        if !text.isEmpty { return text }
    }
    return nil
}

/// Whether the app's saved settings want this reply read: the session switched on with
/// /speak on, or the tool's "read every reply" switch. Read straight from the app's settings so a
/// hook never has to start the app just to ask.
func wantsReading(tool: Tool, session: String?) -> Bool {
    guard let defaults = UserDefaults(suiteName: "local.readback") else { return false }
    if defaults.bool(forKey: "autoRead.\(tool.rawValue)") { return true }
    guard let session else { return false }
    return (defaults.stringArray(forKey: "sessionsOn") ?? []).contains(session)
}

func speak(_ body: [String: Any]) -> Bool {
    guard ensureApp() else { return false }
    guard let response = request("POST", "speak", body), response.status == 202 else {
        log("/speak failed for \(body["source"] ?? "?")")
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
    guard let app = appURL else { fail("run this from inside Readback.app (Contents/Helpers/readback)") }
    return IntegrationFiles(paths: ReadbackPaths(), cli: executablePath,
                            bundledPlugin: app.appendingPathComponent("Contents/Resources/ClaudeCodePlugin", isDirectory: true),
                            codex: CodexCLI.lazyRunner(),
                            bundledCodexAssets: app.appendingPathComponent("Contents/Resources/CodexPluginAssets", isDirectory: true))
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
    let source = tool(args.first)
    let payload = readStdinJSON()
    print("{}")   // Codex wants JSON on stdout from a Stop hook; Claude Code accepts it.
    fflush(stdout)
    if source == .codex, CodexHookPayload.isBackgroundJob(transcriptPath: payload["transcript_path"] as? String) {
        log("codex: skipped a reply from a background job (no saved chat)")
        exit(0)
    }
    guard let text = replyText(payload) else {
        log("\(source.rawValue): the hook had no reply text")
        exit(0)
    }
    var body: [String: Any] = ["text": text, "source": source.rawValue]
    let session = payload["session_id"] as? String
    if let session { body["session"] = session }
    if let cwd = payload["cwd"] as? String { body["cwd"] = cwd }
    // Running: hand it over (it's kept for "Read last reply" even when it isn't read).
    // Not running: only start Readback when this reply is meant to be read, so quitting
    // Readback isn't undone by the next reply in some other session.
    if isUp() || wantsReading(tool: source, session: session) {
        _ = speak(body)
    }

case "read":
    let payload = readStdinJSON()
    guard let text = replyText(payload) else { fail("no last_assistant_message on stdin") }
    var body: [String: Any] = ["text": text, "source": (payload["source"] as? String) ?? "claude", "autoplay": true]
    if let session = payload["session_id"] as? String { body["session"] = session }
    if let cwd = payload["cwd"] as? String { body["cwd"] = cwd }
    if !speak(body) { fail("Readback didn't take it (see ~/Library/Logs/Readback/cli.log)") }

case "say":
    let text = args.joined(separator: " ")
    guard !text.isEmpty else { fail("nothing to say", code: 2) }
    if !speak(["text": text, "source": "Readback", "autoplay": true]) { fail("Readback didn't take it") }

case "stop":
    let payload = readStdinJSON()
    guard isUp() else { exit(0) }
    var body: [String: Any] = [:]
    if let session = payload["session_id"] as? String { body["session"] = session }
    _ = request("POST", "stop", body)

case "prompt":
    let source = tool(args.first)
    let payload = readStdinJSON()
    let session = payload["session_id"] as? String
    let prompt = payload["prompt"] as? String ?? ""
    guard let asked = PromptCommand(prompt: prompt) else {
        // Something that starts like a command but didn't parse: note its start, so a new way
        // of writing the command (a Codex update) shows up in the log rather than going unseen.
        let start = prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60).lowercased()
        if start.first.map("/$[".contains) == true, start.contains("speak") || start.contains("read") {
            log("\(source.rawValue): a prompt that looks like /speak or /read wasn't one: \(start)")
        }
        // An ordinary prompt: stop this session's reading, like `stop`. Print nothing, since
        // Codex adds a UserPromptSubmit hook's plain output to the conversation.
        if isUp() { _ = request("POST", "stop", session.map { ["session": $0] } ?? [:]) }
        exit(0)
    }
    guard let session else { blockPrompt("Readback couldn't tell which chat this is, so it can't change anything here.") }
    guard ensureApp() else { blockPrompt("Readback isn't running and couldn't be started. Open Readback from your Applications folder.") }
    switch asked {
    case .speak(let enabled):
        var body: [String: Any] = ["session": session]
        if let enabled { body["enabled"] = enabled }
        guard let isOn = request("POST", "session", body)?.json["enabled"] as? Bool else {
            blockPrompt("Readback didn't answer. See ~/Library/Logs/Readback.")
        }
        let everyReply = UserDefaults(suiteName: "local.readback")?.bool(forKey: "autoRead.\(source.rawValue)") == true
        if !isOn, everyReply {
            blockPrompt("Read-aloud is off for this chat, but Readback is set to read every \(source.name) reply. Switch that off in Readback's Reading page.")
        }
        if enabled == nil {
            blockPrompt("Read-aloud is \(isOn || everyReply ? "on" : "off") in this chat. /speak on or /speak off changes it, /read reads the last reply.")
        }
        blockPrompt(isOn ? "Read-aloud is on for this chat." : "Read-aloud is off for this chat.")
    case .read:
        guard let answer = request("POST", "replay", ["session": session]), answer.status == 200 else {
            blockPrompt("Readback didn't answer. See ~/Library/Logs/Readback.")
        }
        blockPrompt(answer.json["played"] as? Bool == true ? "Reading the last reply." : "There's no reply in this chat to read yet.")
    }

case "session":
    guard let id = args.first, !id.isEmpty else { fail("usage: readback session <id> [on|off]", code: 2) }
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    var body: [String: Any] = ["session": id]
    if let value = onOff(args.dropFirst().first) { body["enabled"] = value }
    guard let response = request("POST", "session", body) else { fail("no answer from Readback") }
    print((response.json["enabled"] as? Bool) == true ? "on" : "off")

case "auto":
    let t = tool(args.first)
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    var body: [String: Any] = ["tool": t.rawValue]
    if let value = onOff(args.dropFirst().first) { body["enabled"] = value }
    guard let response = request("POST", "auto", body) else { fail("no answer from Readback") }
    print("\(t.name): \((response.json["enabled"] as? Bool) == true ? "on" : "off")")

case "voice":
    // readback voice [engine] [voice]   e.g. readback voice kokoro bm_george
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    var body: [String: Any] = [:]
    if let engine = args.first { body["engine"] = engine }
    if args.count > 1 { body["voice"] = args[1] }
    if args.count > 2 { body["model"] = args[2] }
    guard let response = request("POST", "voice", body) else { fail("no answer from Readback") }
    if response.status != 200 { fail(response.json["error"] as? String ?? "HTTP \(response.status)") }
    printJSON(response.json)

case "engine":
    // readback engine [install|remove]: the on-device voice engine, from the terminal.
    let action = args.first
    if let action, action != "install", action != "remove" { fail("usage: readback engine [install|remove]", code: 2) }
    guard ensureApp() else { fail("Readback isn't running and couldn't be started") }
    guard let response = request("POST", "engine", action.map { ["action": $0] }) else { fail("no answer from Readback") }
    print(response.json["runtime"] as? String ?? "unknown")

case "wait":
    for _ in 0..<20 {
        if (request("GET", "health", timeout: 1)?.json["speaking"] as? Bool) == true { break }
        Thread.sleep(forTimeInterval: 0.25)
    }
    while (request("GET", "health", timeout: 1)?.json["speaking"] as? Bool) == true {
        Thread.sleep(forTimeInterval: 0.5)
    }

case "status":
    guard let response = request("GET", "health", timeout: 1) else {
        print("Readback isn't running")
        exit(1)
    }
    printJSON(response.json)

case "connect", "disconnect":
    let t = tool(args.first)
    let files = integrationFiles()
    do {
        if command == "connect" { try files.connect(t) } else { try files.disconnect(t) }
        print("\(t.name): \(command == "connect" ? "connected" : "disconnected")")
        if command == "connect", t == .codex, !files.codexHooksApproved(home: files.paths.codexDir) {
            print("Codex runs the plugin's two hooks only after you approve them: Settings > Hooks in the Codex app, or /hooks in the terminal. Quit and reopen the Codex app if it's open.")
        }
    } catch {
        fail("\(error)")
    }

case "integrations":
    let files = integrationFiles()
    for t in Tool.allCases {
        let state: String
        if !files.isToolInstalled(t) { state = "not installed" } else {
            switch (try? files.status(t)) ?? .notConnected {
            case .connected:
                state = t == .codex && !files.codexHooksApproved(home: files.paths.codexDir)
                    ? "connected, waiting for you to approve its hooks in Codex" : "connected"
            case .notConnected: state = "not connected"
            case .stale(let other): state = "connected to another copy of Readback (\(other))"
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
