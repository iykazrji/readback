import Foundation

/// Readback's Codex plugin: two hooks (a finished reply goes to Readback; a new prompt stops the
/// reading, or is a /speak or /read command Readback answers itself) and two skills, `speak` and
/// `read`, which exist so the commands show in Codex's slash menu.
///
/// Codex only runs a plugin's hooks once a person approves them (Settings > Hooks in the Codex app,
/// /hooks in the terminal). Approval is kept against the hook definition and the plugin's scripts,
/// so these files only change when the CLI path does: an update to Readback never asks again.
public enum CodexPlugin {
    public static let name = "readback"
    public static let marketplace = "readback"
    public static var selector: String { "\(name)@\(marketplace)" }
    /// Bumped only when a file below changes, since Codex installs one cached copy per version.
    /// A copy installed from an older version shows as an update in Connections.
    public static let version = "1.1.0"
    /// The artwork the plugin shows in Codex: its list (512 px) and the composer (32 px). The app
    /// ships them in Resources/CodexPluginAssets and connecting copies them in.
    public static let assetNames = ["logo.png", "composer-icon.png"]

    /// The marketplace folder Readback writes, relative to its root, with the CLI path baked into
    /// the hooks. Codex installs the plugin from here into its own cache.
    public static func files(cli: String) -> [(path: String, contents: String)] {
        let stop = JSONValue.quote(hooks["Stop"]!.line(cli: cli))
        let prompt = JSONValue.quote(hooks["UserPromptSubmit"]!.line(cli: cli))
        return [
            (".agents/plugins/marketplace.json", """
            {
              "name": "\(marketplace)",
              "interface": { "displayName": "Readback" },
              "plugins": [
                {
                  "name": "\(name)",
                  "source": { "source": "local", "path": "./plugins/\(name)" },
                  "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
                  "category": "Productivity"
                }
              ]
            }

            """),
            ("plugins/\(name)/.codex-plugin/plugin.json", """
            {
              "name": "\(name)",
              "version": "\(version)",
              "description": "Reads Codex replies aloud with the Readback app. /speak on or /speak off in a chat, /read for the last reply.",
              "hooks": "./hooks/hooks.json",
              "skills": "./skills/",
              "interface": {
                "displayName": "Readback",
                "shortDescription": "Hear Codex replies read aloud on your Mac",
                "longDescription": "Readback reads each finished reply out loud with a voice that runs on your Mac. Type /speak on in a chat to hear its replies, /speak off to stop, and /read to hear the last reply again.",
                "developerName": "Readback",
                "category": "Productivity",
                "logo": "./assets/logo.png",
                "composerIcon": "./assets/composer-icon.png",
                "brandColor": "#B39A78"
              }
            }

            """),
            ("plugins/\(name)/hooks/hooks.json", """
            {
              "hooks": {
                "Stop": [
                  { "hooks": [ { "type": "command", "command": \(stop), "timeout": 10 } ] }
                ],
                "UserPromptSubmit": [
                  { "hooks": [ { "type": "command", "command": \(prompt), "timeout": 10 } ] }
                ]
              }
            }

            """),
            ("plugins/\(name)/skills/speak/SKILL.md", skill(
                name: "speak",
                description: "Read replies aloud in this chat with Readback: /speak on or /speak off.",
                usage: "/speak on or /speak off")),
            ("plugins/\(name)/skills/speak/agents/openai.yaml", skillUI(
                title: "Speak", summary: "Read replies aloud in this chat: on or off")),
            ("plugins/\(name)/skills/read/SKILL.md", skill(
                name: "read",
                description: "Read the last reply in this chat aloud now with Readback.",
                usage: "/read")),
            ("plugins/\(name)/skills/read/agents/openai.yaml", skillUI(
                title: "Read", summary: "Read the last reply aloud now")),
        ]
    }

    /// The skill only gives the command a place in the menu: Readback's prompt hook answers it
    /// before the model sees it. The text covers the one case where it doesn't (hooks not approved).
    private static func skill(name: String, description: String, usage: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        Readback answers this command itself before it reaches you, so you normally never see it.

        If you are reading this, Readback did not catch the command. Do not run any commands. Reply with exactly this: "Readback didn't catch that. Type \(usage) on its own line, and check that Readback's two hooks are approved in Codex: Settings > Hooks in the Codex app, or /hooks in the terminal."

        """
    }

    private static func skillUI(title: String, summary: String) -> String {
        """
        interface:
          display_name: "\(title)"
          short_description: "\(summary)"
          icon_small: "../../assets/composer-icon.png"
          icon_large: "../../assets/logo.png"
        policy:
          allow_implicit_invocation: false

        """
    }

    // MARK: What Codex's config.toml says

    /// The hook events whose Readback hook a person approved, read from config.toml's
    /// `[hooks.state."readback@readback:hooks/hooks.json:<event>:<group>:<hook>"]` tables.
    /// A table with `enabled = false` (switched off in /hooks) doesn't count. Read-only: Readback
    /// never writes these.
    public static func approvedEvents(configToml: String) -> Set<String> {
        let prefix = "[hooks.state.\"\(selector):hooks/hooks.json:"
        var approved: Set<String> = []
        var current: String?
        var trusted = false, disabled = false
        func finish() {
            if let current, trusted, !disabled { approved.insert(current) }
        }
        for raw in configToml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                finish()
                current = nil; trusted = false; disabled = false
                if line.hasPrefix(prefix) {
                    current = line.dropFirst(prefix.count).split(separator: ":").first.map(String.init)
                }
            } else if current != nil {
                let compact = line.replacingOccurrences(of: " ", with: "")
                if compact.hasPrefix("trusted_hash=\"") { trusted = true }
                if compact == "enabled=false" { disabled = true }
            }
        }
        finish()
        return approved
    }

    /// The two hooks in the plugin's hooks.json, by event.
    public static let hooks: [String: HookCommand] = ["Stop": .replyFinished(.codex), "UserPromptSubmit": .codexPrompt]

    /// The two events Readback's hooks run on, as config.toml names them.
    public static let hookEvents: Set<String> = ["stop", "user_prompt_submit"]

    /// Whether config.toml has the plugin installed and not switched off.
    public static func isEnabled(configToml: String) -> Bool {
        let header = "[plugins.\"\(selector)\"]"
        var inTable = false, found = false, disabled = false
        for raw in configToml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inTable = line == header
                if inTable { found = true }
            } else if inTable, line.replacingOccurrences(of: " ", with: "") == "enabled=false" {
                disabled = true
            }
        }
        return found && !disabled
    }
}

/// What a Codex prompt asks Readback to do, when it's one of Readback's commands.
public enum PromptCommand: Equatable {
    /// `/speak on`, `/speak off`, or `/speak` alone (nil: say whether it's on).
    case speak(Bool?)
    /// `/read`: read this chat's last reply now.
    case read

    /// The command in a prompt, or nil for an ordinary prompt. Accepts the forms Codex can send
    /// for a typed or picked skill: `/speak on`, `$speak on`, `$readback:speak on`, and a skill
    /// mention written as a markdown link, `[$speak](/path/SKILL.md) on`. Anything else after
    /// the command word makes it an ordinary prompt ("/read the docs" goes to the model).
    public init?(prompt: String) {
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // [$speak](…) → $speak
        if text.hasPrefix("["), let close = text.range(of: "]("), let end = text[close.upperBound...].firstIndex(of: ")") {
            text = String(text[text.index(after: text.startIndex)..<close.lowerBound]) + text[text.index(after: end)...]
        }
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard var word = words.first, word.first == "/" || word.first == "$" else { return nil }
        word.removeFirst()
        let plugin = CodexPlugin.name + ":"
        if word.hasPrefix(plugin) { word.removeFirst(plugin.count) }
        let rest = Array(words.dropFirst())
        switch (word, rest) {
        case ("speak", []): self = .speak(nil)
        case ("speak", ["on"]): self = .speak(true)
        case ("speak", ["off"]): self = .speak(false)
        case ("read", []): self = .read
        default: return nil
        }
    }
}

extension PromptCommand {
    /// For a prompt that starts like /speak or /read but isn't one (a new way Codex writes the
    /// command, say), its shape for the log. nil for a command or an ordinary prompt. Nothing the
    /// person typed is kept.
    public static func nearMiss(_ prompt: String) -> String? {
        guard PromptCommand(prompt: prompt) == nil else { return nil }
        let words = prompt.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard let word = words.first, let first = word.first, "/$[".contains(first) else { return nil }
        let lower = word.lowercased()
        let mentions = lower.contains("speak") ? "speak" : lower.contains("read") ? "read" : nil
        guard let mentions else { return nil }
        // Only the shape: which sign it starts with, which command it mentions, and how long it is.
        let rest = words.count - 1
        return "a \(first) word with \(mentions) in it (\(word.count) characters), then \(rest) \(rest == 1 ? "word" : "words")"
    }
}

/// Bytes from a pipe, appended on its reading queue and read on another.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ chunk: Data) { lock.lock(); bytes.append(chunk); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
}

/// Runs `codex <args>` with CODEX_HOME set to a Codex home; throws when it fails.
public typealias CodexRun = (_ args: [String], _ codexHome: URL) throws -> Void

/// The codex command Readback installs its plugin with. The Codex app (ChatGPT.app) carries its
/// own copy, so people who only use the app don't need the terminal version.
public struct CodexCLI {
    public let path: String

    public init(path: String) { self.path = path }

    /// A codex command that failed. `description` is one line a person can read in the app;
    /// `debugDescription` has the whole output, for the log.
    public struct Failed: Error, CustomStringConvertible, CustomDebugStringConvertible {
        public let args: [String]
        public let status: Int32
        public let output: String

        public var description: String {
            let step = args.prefix(2) == ["plugin", "marketplace"] ? "add Readback's plugin list" : "install the plugin"
            return "Codex couldn't \(step): \(Self.reason(in: output)). The full message is in Readback's log (About > Logs)."
        }

        public var debugDescription: String {
            "codex \(args.joined(separator: " ")) failed (exit \(status)):\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        /// The first "Error: …" line codex printed, or its first line, shortened: codex errors
        /// carry multi-line traces that mean nothing in a settings window.
        static func reason(in output: String) -> String {
            let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var line = lines.first(where: { $0.hasPrefix("Error:") }).map { String($0.dropFirst("Error:".count)) } ?? lines.first ?? "no message"
            line = line.trimmingCharacters(in: .whitespaces)
            if line.count > 120 { line = String(line.prefix(119)) + "…" }
            return line.isEmpty ? "no message" : line
        }
    }

    /// The first codex found: the Codex app's own copy, then the usual install places. Apps
    /// started by macOS don't get the shell's PATH, so this looks in each place by hand.
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> CodexCLI? {
        let bundled = "ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        var candidates = [
            "/Applications/\(bundled)",
            home.appendingPathComponent("Applications/\(bundled)").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".bun/bin/codex").path,
            home.appendingPathComponent(".volta/bin/codex").path,
        ]
        // npm installs under nvm: the newest Node version that has codex.
        let nvm = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? []
        candidates += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { nvm.appendingPathComponent("\($0)/bin/codex").path }
        return candidates.first(where: isExecutable).map(CodexCLI.init(path:))
    }

    /// The oldest Codex with `codex plugin marketplace` and plugin hooks switched on (#21396,
    /// #22549, both in rust-v0.131.0, 2026-05-18).
    public static let minimumVersion = "0.131.0"

    public struct TooOld: Error, CustomStringConvertible {
        public let version: String
        public let path: String
        public var description: String {
            "Your Codex is version \(version) (\(path)), and Readback's plugin needs \(CodexCLI.minimumVersion) or newer. Update Codex, then click Connect again. With npm: npm install -g @openai/codex@latest. With Homebrew: brew upgrade codex."
        }
    }

    /// Whether `version` ("0.171.0", "0.171.0-alpha.13.2", "codex-cli 0.120.1") is at least the minimum.
    public static func isNewEnough(_ version: String) -> Bool {
        func numbers(_ v: String) -> [Int] {
            let word = v.split(separator: " ").last.map(String.init) ?? v
            return word.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let have = numbers(version), need = numbers(minimumVersion)
        guard !have.isEmpty else { return false }
        for i in 0..<max(have.count, need.count) {
            let a = i < have.count ? have[i] : 0, b = i < need.count ? need[i] : 0
            if a != b { return a > b }
        }
        return true
    }

    /// `codex --version`'s answer, e.g. "codex-cli 0.171.0".
    public func version() throws -> String {
        try output(["--version"], codexHome: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Looks through the person's login shell's PATH for codex, for installs the usual places
    /// miss (pnpm, fnm, mise, a custom npm prefix). Asks for PATH rather than `command -v codex`,
    /// which names a shell function or alias called codex instead of the file. Slow, so only when
    /// the usual places have nothing.
    public static func fromLoginShell(timeout: TimeInterval = 5,
                                      isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> CodexCLI? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        // -l reads the login files; -i also reads .zshrc/.bashrc, where nvm and friends are often set up.
        for flags in [["-l", "-c"], ["-l", "-i", "-c"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = flags + [#"printf '\nREADBACK_PATH=%s\n' "$PATH""#]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { continue }
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); continue }
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if let found = inPath(text, isExecutable: isExecutable) { return found }
        }
        return nil
    }

    /// The first codex in the PATH line a shell printed (anything else a shell's startup files
    /// print around it is ignored).
    static func inPath(_ shellOutput: String, isExecutable: (String) -> Bool) -> CodexCLI? {
        guard let line = shellOutput.split(separator: "\n").last(where: { $0.hasPrefix("READBACK_PATH=") }) else { return nil }
        return line.dropFirst("READBACK_PATH=".count).split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
            .first(where: isExecutable)
            .map(CodexCLI.init(path:))
    }

    /// The runner the app and CLI hand to IntegrationFiles: finds codex the first time it's
    /// needed (not on every status check), and refuses one too old for plugins.
    public static func lazyRunner() -> CodexRun {
        var ready: CodexCLI?
        return { args, codexHome in
            if ready == nil {
                guard let cli = find() ?? fromLoginShell() else { throw IntegrationFiles.Failure.noCodexCommand }
                let version = try cli.version()
                guard isNewEnough(version) else { throw TooOld(version: version, path: cli.path) }
                ready = cli
            }
            try ready!.run(args, codexHome: codexHome)
        }
    }

    /// Long enough for a plugin install on a slow disk; a codex that takes longer is stuck.
    public static let timeout: TimeInterval = 120

    public func run(_ args: [String], codexHome: URL, timeout: TimeInterval = CodexCLI.timeout) throws {
        _ = try output(args, codexHome: codexHome, timeout: timeout)
    }

    private func output(_ args: [String], codexHome: URL?, timeout: TimeInterval = 15) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        if let codexHome { env["CODEX_HOME"] = codexHome.path }
        // An npm-installed codex is a Node script: its folder holds the node it needs.
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().path
        env["PATH"] = ([folder] + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init))
            .joined(separator: ":")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let collected = Collected()
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let readerDone = DispatchSemaphore(value: 0)
        try process.run()
        // One reader owns the pipe from start to end, so nothing read is ever lost between two.
        // It stops at EOF, or once the process has ended and the pipe is empty: a child the
        // process left behind may hold the pipe open, and waiting for that would block Connect.
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 { collected.append(Data(buffer[0..<count])); continue }
                if count == 0 { break }
                guard errno == EAGAIN || errno == EINTR else { break }
                // Empty for now. Once the process has ended, one more look takes anything it wrote
                // last; after that the pipe is done.
                if !process.isRunning {
                    let more = read(fd, &buffer, buffer.count)
                    if more > 0 { collected.append(Data(buffer[0..<more])); continue }
                    break
                }
                usleep(5_000)
            }
            readerDone.signal()
        }
        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        _ = readerDone.wait(timeout: .now() + 2)
        let data = collected.data
        if timedOut {
            throw Failed(args: args, status: -1, output: "Error: codex didn't finish within \(Int(timeout)) seconds\n" + String(decoding: data, as: UTF8.self))
        }
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failed(args: args, status: process.terminationStatus, output: output)
        }
        return output
    }
}
