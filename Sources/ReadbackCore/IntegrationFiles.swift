import Foundation

/// Where everything lives, from one home folder (a test can point it somewhere else).
public struct ReadbackPaths {
    public let home: URL
    /// Whether tool-specific variables like CODEX_HOME apply. Only for the real home: a home
    /// passed in (a test's fake home) must never reach the user's actual config files.
    private let honorsEnvironment: Bool

    public init(home: URL? = nil) {
        if let home {
            self.home = home
            honorsEnvironment = false
        } else {
            self.home = ReadbackPaths.defaultHome
            honorsEnvironment = ProcessInfo.processInfo.environment["READBACK_HOME"] == nil
        }
    }

    /// READBACK_HOME overrides the home folder (for tests); otherwise the user's.
    public static var defaultHome: URL {
        if let custom = ProcessInfo.processInfo.environment["READBACK_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public var support: URL { home.appendingPathComponent("Library/Application Support/Readback", isDirectory: true) }
    public var runtime: URL { support.appendingPathComponent("runtime", isDirectory: true) }
    public var python: URL { runtime.appendingPathComponent(".venv/bin/python") }
    public var voiceServer: URL { runtime.appendingPathComponent(".venv/bin/mlx_audio.server") }
    public var runtimeReceipt: URL { runtime.appendingPathComponent("installed.json") }
    /// Word lists MeloTTS's pronunciation step (g2p_en, through nltk) fetches on first use. Kept
    /// in the engine's folder, so removing the engine removes them, not in ~/nltk_data.
    public var nltkData: URL { runtime.appendingPathComponent("nltk_data", isDirectory: true) }
    public var claudePlugin: URL { support.appendingPathComponent("ClaudeCodePlugin", isDirectory: true) }
    public var logs: URL { home.appendingPathComponent("Library/Logs/Readback", isDirectory: true) }

    /// Claude Code's config folder: CLAUDE_CONFIG_DIR when it's set (a second login, such as a
    /// work account, keeps its own folder that way), else ~/.claude. Like CODEX_HOME, only for
    /// the real home. The app is started by macOS without it, so it always shows ~/.claude;
    /// `CLAUDE_CONFIG_DIR=<folder> readback connect claude` connects another one.
    public var claudeDir: URL {
        if honorsEnvironment, let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            let expanded = custom.hasPrefix("~") ? home.path + custom.dropFirst() : custom
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }
    public var claudeSettings: URL { claudeDir.appendingPathComponent("settings.json") }
    public var codexDir: URL {
        if honorsEnvironment, let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }
    public var codexHooks: URL { codexDir.appendingPathComponent("hooks.json") }
    /// Orca (a terminal app) runs Codex with its own CODEX_HOME, so it needs connecting separately.
    public var orcaCodexDir: URL { home.appendingPathComponent("Library/Application Support/orca/codex-runtime-home/home", isDirectory: true) }
    /// The Codex plugin marketplace Readback writes; Codex installs the plugin from it into its cache.
    public var codexPluginSource: URL { support.appendingPathComponent("CodexPlugin", isDirectory: true) }
    public var openCodeDir: URL { home.appendingPathComponent(".config/opencode", isDirectory: true) }
    public var openCodePlugin: URL { openCodeDir.appendingPathComponent("plugins/readback.js") }
}

/// Connects and disconnects the tools by editing their files on disk. Before a file is changed,
/// its current version is kept beside it as `<name>.before-readback`.
public struct IntegrationFiles {
    public let paths: ReadbackPaths
    /// The CLI the hooks run (…/Readback.app/Contents/Helpers/readback).
    public let cli: String
    /// The Claude Code mod folder shipped inside the app, copied out on connect.
    public let bundledPlugin: URL?
    /// Runs `codex <args>` against a Codex home. Codex installs plugins itself; nil when no
    /// codex command was found (tests pass a fake).
    public let codex: CodexRun?
    /// The Codex plugin's artwork shipped inside the app (Resources/CodexPluginAssets), copied
    /// into the plugin on connect. Nil leaves the plugin without pictures (tests).
    public let bundledCodexAssets: URL?

    public init(paths: ReadbackPaths, cli: String, bundledPlugin: URL?, codex: CodexRun? = nil, bundledCodexAssets: URL? = nil) {
        self.paths = paths
        self.cli = cli
        self.bundledPlugin = bundledPlugin
        self.codex = codex
        self.bundledCodexAssets = bundledCodexAssets
    }

    public enum Failure: Error, CustomStringConvertible {
        case toolNotInstalled(Tool, String)
        case unreadable(String, String)
        case noCodexCommand

        public var description: String {
            switch self {
            case .toolNotInstalled(let tool, let path): return "\(tool.name) doesn't seem to be installed (no \(path))"
            case .unreadable(let path, let why): return "Couldn't read \(path): \(why)"
            case .noCodexCommand: return "Couldn't find Codex to install the plugin with. Install the Codex app or the codex command, then try again."
            }
        }
    }

    public func isToolInstalled(_ tool: Tool) -> Bool {
        let dir: URL
        switch tool {
        case .claude: dir = paths.claudeDir
        case .codex: dir = paths.codexDir
        case .opencode: dir = paths.openCodeDir
        }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    public func status(_ tool: Tool) throws -> Integrations.Status {
        switch tool {
        case .claude: return Integrations.hookStatus(try readJSON(paths.claudeSettings), cli: cli)
        case .codex: return try codexStatus(home: paths.codexDir)
        case .opencode:
            guard let source = try? String(contentsOf: paths.openCodePlugin, encoding: .utf8),
                  let other = Integrations.openCodeCLI(in: source) else { return .notConnected }
            return other == cli ? .connected : .stale(other)
        }
    }

    public func connect(_ tool: Tool) throws {
        guard isToolInstalled(tool) else { throw Failure.toolNotInstalled(tool, toolDir(tool).path) }
        switch tool {
        case .claude:
            try copyPlugin()
            var root = try readJSON(paths.claudeSettings)
            Integrations.connectClaude(&root, cli: cli, pluginDir: paths.claudePlugin.path)
            try writeJSON(root, to: paths.claudeSettings)
        case .codex:
            try connectCodex(home: paths.codexDir)
        case .opencode:
            try FileManager.default.createDirectory(at: paths.openCodePlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Integrations.openCodePlugin(cli: cli).write(to: paths.openCodePlugin, atomically: true, encoding: .utf8)
        }
    }

    public func disconnect(_ tool: Tool) throws {
        switch tool {
        case .claude:
            guard FileManager.default.fileExists(atPath: paths.claudeSettings.path) else { return }
            var root = try readJSON(paths.claudeSettings)
            Integrations.disconnectClaude(&root)
            try writeJSON(root, to: paths.claudeSettings)
        case .codex:
            try disconnectCodex(home: paths.codexDir)
        case .opencode:
            // Only delete the file if it's the one Readback wrote.
            if let source = try? String(contentsOf: paths.openCodePlugin, encoding: .utf8),
               Integrations.openCodeCLI(in: source) != nil {
                try FileManager.default.removeItem(at: paths.openCodePlugin)
            }
        }
    }

    /// Copies the mod out of the app, only when the app's copy differs: every open Claude Code
    /// session reloads the mod (and says so) whenever its files change.
    public func copyPlugin() throws {
        guard let bundledPlugin else { return }
        let fm = FileManager.default
        if pluginIsCurrent(bundledPlugin) { return }
        try fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let staging = paths.support.appendingPathComponent("ClaudeCodePlugin.new", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: bundledPlugin, to: staging)
        if fm.fileExists(atPath: paths.claudePlugin.path) { try fm.removeItem(at: paths.claudePlugin) }
        try fm.moveItem(at: staging, to: paths.claudePlugin)
    }

    /// Whether every file in the app's mod is already in place, byte for byte. Files Claude Code
    /// adds beside the copy (its type files) don't count.
    private func pluginIsCurrent(_ bundled: URL) -> Bool {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: bundled, includingPropertiesForKeys: [.isRegularFileKey]) else { return false }
        let base = bundled.standardizedFileURL.path
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count))
            let installed = URL(fileURLWithPath: paths.claudePlugin.path + relative)
            guard let a = fm.contents(atPath: file.path), let b = fm.contents(atPath: installed.path), a == b else { return false }
        }
        return true
    }

    // MARK: Codex

    /// Writes Readback's plugin marketplace, has Codex install the plugin into `home` (~/.codex,
    /// or Orca's Codex home), and removes the hooks older Readback versions put in hooks.json so
    /// no reply is read twice. Running it again is harmless: Codex reinstalls the same copy.
    public func connectCodex(home: URL) throws {
        guard FileManager.default.fileExists(atPath: home.path) else { throw Failure.toolNotInstalled(.codex, home.path) }
        guard let codex else { throw Failure.noCodexCommand }
        try writeCodexPlugin()
        try codex(["plugin", "marketplace", "add", paths.codexPluginSource.path], home)
        try codex(["plugin", "add", CodexPlugin.selector], home)
        try removeOldCodexHooks(home: home)
    }

    public func disconnectCodex(home: URL) throws {
        if CodexPlugin.isEnabled(configToml: codexConfig(home: home)) {
            guard let codex else { throw Failure.noCodexCommand }
            try codex(["plugin", "remove", CodexPlugin.selector], home)
            try codex(["plugin", "marketplace", "remove", CodexPlugin.marketplace], home)
            // Orca's Codex home links its plugins folder to ~/.codex/plugins, so removing the
            // plugin from one home deletes the copy the other runs. Put it back for any home
            // that still has it switched on.
            for other in [paths.codexDir, paths.orcaCodexDir] where other.standardizedFileURL != home.standardizedFileURL {
                if CodexPlugin.isEnabled(configToml: codexConfig(home: other)), installedCodexHooks(home: other) == nil {
                    try codex(["plugin", "add", CodexPlugin.selector], other)
                }
            }
        }
        try removeOldCodexHooks(home: home)
    }

    /// Connected means Codex has the plugin enabled and its installed copy runs this CLI. A copy
    /// from an older version of the plugin is an update waiting.
    public func codexStatus(home: URL) throws -> Integrations.Status {
        let hooks = home.appendingPathComponent("hooks.json")
        if !Integrations.ourCommands(try readJSON(hooks)).isEmpty { return .outdated }
        guard CodexPlugin.isEnabled(configToml: codexConfig(home: home)),
              let installed = installedCodexHooks(home: home) else { return .notConnected }
        let status = Integrations.hookStatus(try readJSON(installed), cli: cli)
        let version = installed.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        if status == .connected, version != CodexPlugin.version { return .updateAvailable }
        return status
    }

    /// Whether a person approved both of the plugin's hooks in Codex. Until then Codex skips them.
    public func codexHooksApproved(home: URL) -> Bool {
        CodexPlugin.approvedEvents(configToml: codexConfig(home: home)).isSuperset(of: CodexPlugin.hookEvents)
    }

    private func codexConfig(home: URL) -> String {
        (try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8)) ?? ""
    }

    /// The hooks.json of the copy Codex installed, in <home>/plugins/cache/readback/readback/<version>/.
    private func installedCodexHooks(home: URL) -> URL? {
        let cache = home.appendingPathComponent("plugins/cache/\(CodexPlugin.marketplace)/\(CodexPlugin.name)", isDirectory: true)
        let versioned = cache.appendingPathComponent("\(CodexPlugin.version)/hooks/hooks.json")
        if FileManager.default.fileExists(atPath: versioned.path) { return versioned }
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        return versions.sorted().last
            .map { cache.appendingPathComponent("\($0)/hooks/hooks.json") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Writes only files whose contents changed, so an unchanged plugin stays byte for byte the same.
    private func writeCodexPlugin() throws {
        let fm = FileManager.default
        for file in CodexPlugin.files(cli: cli) {
            let url = paths.codexPluginSource.appendingPathComponent(file.path)
            if (try? String(contentsOf: url, encoding: .utf8)) == file.contents { continue }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        guard let bundledCodexAssets else { return }
        let assets = paths.codexPluginSource.appendingPathComponent("plugins/\(CodexPlugin.name)/assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        for name in CodexPlugin.assetNames {
            let source = bundledCodexAssets.appendingPathComponent(name)
            let target = assets.appendingPathComponent(name)
            let data = try Data(contentsOf: source)
            if fm.contents(atPath: target.path) == data { continue }
            try data.write(to: target, options: .atomic)
        }
    }

    private func removeOldCodexHooks(home: URL) throws {
        let hooks = home.appendingPathComponent("hooks.json")
        guard FileManager.default.fileExists(atPath: hooks.path) else { return }
        var root = try readJSON(hooks)
        guard !Integrations.ourCommands(root).isEmpty else { return }
        Integrations.removeOurHooks(&root)
        try writeJSON(root, to: hooks)
    }

    private func toolDir(_ tool: Tool) -> URL {
        switch tool {
        case .claude: return paths.claudeDir
        case .codex: return paths.codexDir
        case .opencode: return paths.openCodeDir
        }
    }

    /// A missing or empty file reads as {}.
    private func readJSON(_ url: URL) throws -> JSONValue {
        guard FileManager.default.fileExists(atPath: url.path) else { return .object([]) }
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) } catch {
            throw Failure.unreadable(url.path, error.localizedDescription)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .object([]) }
        do { return try JSONValue.parse(text) } catch {
            throw Failure.unreadable(url.path, "it isn't valid JSON (\(error))")
        }
    }

    private func writeJSON(_ value: JSONValue, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("before-readback")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try value.formatted().write(to: url, atomically: true, encoding: .utf8)
    }
}
