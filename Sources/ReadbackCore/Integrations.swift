import Foundation

/// The coding tools Readback connects to.
public enum Tool: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude, codex, opencode
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    /// Matches what hooks send as their source ("claude", "Claude Code", "codex", "OpenCode").
    public init?(source: String) {
        let key = source.lowercased().filter { $0.isLetter }
        switch key {
        case "claude", "claudecode": self = .claude
        case "codex": self = .codex
        case "opencode": self = .opencode
        default: return nil
        }
    }
}

/// Pure edits to the tools' config files. The app does the file reading, backups and writing.
///
/// Claude Code (~/.claude/settings.json) and Codex (~/.codex/hooks.json, Readback's own plugin, and
/// older Readback versions' entries in hooks.json) share a hook layout:
/// root.hooks.<Event> = [ { "hooks": [ { "type": "command", "command": ..., "timeout": ... } ] } ].
/// Readback's entries are recognised by the CLI path they run (…/Readback.app/Contents/MacOS/readback),
/// so connecting again replaces them, and disconnecting removes only them.
public enum Integrations {
    public static let pluginDirsKey = "CLAUDE_CODE_PLUGIN_DIRS"

    /// Where the CLI sits inside the app (Contents/MacOS holds the app's own `Readback`, and the
    /// disk ignores case, so the CLI can't live beside it).
    public static let cliSuffix = ".app/Contents/Helpers/readback"

    public static func isOurs(_ command: String) -> Bool {
        command.contains(cliSuffix + "'") || command.contains(cliSuffix + " ") || command.hasSuffix(cliSuffix)
    }

    /// The Claude Code mod is copied out of the app to Application Support/Readback/ClaudeCodePlugin,
    /// so Claude Code writing its type files beside the mod never touches the signed app.
    public static func isOurPluginDir(_ path: String) -> Bool {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.hasSuffix("/Readback/ClaudeCodePlugin")
    }

    public static func command(cli: String, _ args: String) -> String {
        "'\(cli.replacingOccurrences(of: "'", with: "'\\''"))' \(args)"
    }

    // MARK: Hook files

    /// Adds one command hook under hooks.<event>, creating what's missing.
    public static func addHook(_ root: inout JSONValue, event: String, command: String, timeout: Int) {
        if !root.isObject { root = .object([]) }
        var hooks = root["hooks"] ?? .object([])
        if !hooks.isObject { hooks = .object([]) }
        var groups = hooks[event]?.arrayValue ?? []
        groups.append(.object([
            ("hooks", .array([.object([
                ("type", .string("command")),
                ("command", .string(command)),
                ("timeout", .number(String(timeout))),
            ])])),
        ]))
        hooks.set(event, .array(groups))
        root.set("hooks", hooks)
    }

    /// Removes every hook entry that runs a Readback CLI. A group, an event or "hooks" itself goes
    /// too when removing Readback's entries emptied it; anything that was already empty stays.
    public static func removeOurHooks(_ root: inout JSONValue) {
        guard var hooks = root["hooks"], case .object(let events) = hooks else { return }
        var removedAny = false
        for (event, value) in events {
            guard let groups = value.arrayValue else { continue }
            var kept: [JSONValue] = []
            var changed = false
            for group in groups {
                var g = group
                guard let entries = g["hooks"]?.arrayValue else { kept.append(group); continue }
                let left = entries.filter { !isOurs($0["command"]?.stringValue ?? "") }
                if left.count == entries.count { kept.append(group); continue }
                changed = true
                if left.isEmpty { continue }
                g.set("hooks", .array(left))
                kept.append(g)
            }
            guard changed else { continue }
            removedAny = true
            if kept.isEmpty { hooks.remove(event) } else { hooks.set(event, .array(kept)) }
        }
        guard removedAny else { return }
        if case .object(let remaining) = hooks, remaining.isEmpty {
            root.remove("hooks")
        } else {
            root.set("hooks", hooks)
        }
    }

    /// The Readback commands in a hook file, by event.
    public static func ourCommands(_ root: JSONValue) -> [String: [String]] {
        guard case .object(let events)? = root["hooks"] else { return [:] }
        var found: [String: [String]] = [:]
        for (event, value) in events {
            for group in value.arrayValue ?? [] {
                for entry in group["hooks"]?.arrayValue ?? [] {
                    if let c = entry["command"]?.stringValue, isOurs(c) { found[event, default: []].append(c) }
                }
            }
        }
        return found
    }

    // MARK: Claude Code

    public static func connectClaude(_ root: inout JSONValue, cli: String, pluginDir: String) {
        disconnectClaude(&root)
        addHook(&root, event: "Stop", command: command(cli: cli, "hook claude"), timeout: 10)
        addHook(&root, event: "UserPromptSubmit", command: command(cli: cli, "stop"), timeout: 5)
        var env = root["env"] ?? .object([])
        if !env.isObject { env = .object([]) }
        var dirs = (env[pluginDirsKey]?.stringValue ?? "").split(separator: ":").map(String.init)
        dirs.append(pluginDir)
        env.set(pluginDirsKey, .string(dirs.joined(separator: ":")))
        root.set("env", env)
    }

    public static func disconnectClaude(_ root: inout JSONValue) {
        removeOurHooks(&root)
        guard var env = root["env"], let value = env[pluginDirsKey]?.stringValue else { return }
        let dirs = value.split(separator: ":").map(String.init).filter { !isOurPluginDir($0) }
        if dirs.isEmpty { env.remove(pluginDirsKey) } else { env.set(pluginDirsKey, .string(dirs.joined(separator: ":"))) }
        if case .object(let left) = env, left.isEmpty { root.remove("env") } else { root.set("env", env) }
    }

    // MARK: Status

    public enum Status: Equatable {
        case notConnected
        case connected
        /// Connected to a Readback at another path (the app moved, or another copy).
        case stale(String)
        /// Codex connected the old way, with hooks in hooks.json and no /speak or /read.
        /// Reconnecting swaps them for the plugin.
        case outdated
        /// Codex has an older version of Readback's plugin installed; connecting installs this one.
        case updateAvailable
    }

    /// How a hook file stands against the CLI at `cli`.
    public static func hookStatus(_ root: JSONValue, cli: String) -> Status {
        let commands = ourCommands(root).values.flatMap { $0 }
        if commands.isEmpty { return .notConnected }
        let mine = command(cli: cli, "")
        if let other = commands.first(where: { !$0.hasPrefix(mine) }) {
            return .stale(other)
        }
        return .connected
    }

    // MARK: OpenCode

    public static let openCodeMarker = "// Readback for OpenCode, written by Readback.app."

    /// The OpenCode plugin file (~/.config/opencode/plugins/readback.js).
    public static func openCodePlugin(cli: String) -> String {
        """
        \(openCodeMarker) Disconnect it in Readback's Settings.
        // Hands each finished reply to Readback, which reads it if auto-read for OpenCode is on and keeps it
        // as the last reply either way, and stops the reading when you send a new message.
        const CLI = \(JSONValue.quote(cli))

        export const ReadbackPlugin = async ({ client, $, directory }) => {
          const log = async (level, message) => {
            try {
              await client.app.log({ body: { service: "readback", level, message } })
            } catch (err) {
              console.error(`[readback] ${message} (logging failed: ${err?.message ?? err})`)
            }
          }
          const run = async (args, input) => {
            const proc = input === undefined ? $`${CLI} ${args}` : $`${CLI} ${args} < ${new Response(input)}`
            const result = await proc.nothrow().quiet()
            if (result.exitCode !== 0) {
              await log("error", `readback ${args.join(" ")} exited ${result.exitCode}: ${result.stderr.toString().trim()}`)
            }
          }
          return {
            event: async ({ event }) => {
              try {
                if (event.type === "session.idle") {
                  const id = event.properties.sessionID
                  const session = await client.session.get({ path: { id } })
                  if (session.data?.parentID) return // a subagent's session, not the conversation
                  const res = await client.session.messages({ path: { id } })
                  const last = (res.data ?? []).findLast((m) => m.info.role === "assistant")
                  const text = (last?.parts ?? [])
                    .filter((p) => p.type === "text" && !p.synthetic && !p.ignored)
                    .map((p) => p.text)
                    .join("\\n\\n")
                    .trim()
                  if (text) await run(["hook", "opencode"], JSON.stringify({ last_assistant_message: text, session_id: id, cwd: directory }))
                } else if (event.type === "session.status" && event.properties.status?.type === "busy") {
                  await run(["stop"], JSON.stringify({ session_id: event.properties.sessionID }))
                }
              } catch (err) {
                await log("error", `couldn't hand the reply to Readback: ${err?.message ?? err}`)
              }
            },
          }
        }

        """
    }

    /// The CLI path a plugin file runs, if it's ours.
    public static func openCodeCLI(in source: String) -> String? {
        guard source.hasPrefix(openCodeMarker) else { return nil }
        guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix("const CLI = ") }) else { return nil }
        return (try? JSONValue.parse(String(line.dropFirst("const CLI = ".count))))?.stringValue
    }
}
