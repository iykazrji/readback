import Foundation

/// Where everything lives, from one home folder (a test can point it somewhere else).
public struct ReadbackPaths {
    public let home: URL
    /// The tool-specific variables (CODEX_HOME, CLAUDE_CONFIG_DIR) that apply. Only the real
    /// home's: a home passed in (a test's fake home) must never reach the user's actual config
    /// files, unless the test hands in its own.
    private let environment: [String: String]

    public init(home: URL? = nil) {
        if let home {
            self.home = home
            environment = [:]
        } else {
            self.home = ReadbackPaths.defaultHome
            let real = ProcessInfo.processInfo.environment
            environment = real["READBACK_HOME"] == nil ? real : [:]
        }
    }

    /// A home with these variables set, for tests.
    public init(home: URL, environment: [String: String]) {
        self.home = home
        self.environment = environment
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
    public var claudePlugin: URL { support.appendingPathComponent(AppBundle.claudeCodePluginFolder, isDirectory: true) }
    public var logs: URL { home.appendingPathComponent("Library/Logs/Readback", isDirectory: true) }

    /// Claude Code's config folder: CLAUDE_CONFIG_DIR when it's set (a second login, such as a
    /// work account, keeps its own folder that way), else ~/.claude. Like CODEX_HOME, only for
    /// the real home. The app is started by macOS without it, so it always shows ~/.claude;
    /// `CLAUDE_CONFIG_DIR=<folder> readback connect claude` connects another one.
    public var claudeDir: URL {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            let expanded = custom.hasPrefix("~") ? home.path + custom.dropFirst() : custom
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }
    public var claudeSettings: URL { claudeDir.appendingPathComponent("settings.json") }
    public var codexDir: URL {
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return usualCodexDir
    }
    /// ~/.codex, whatever CODEX_HOME says: the Codex app's home.
    public var usualCodexDir: URL { home.appendingPathComponent(".codex", isDirectory: true) }
    public var codexHooks: URL { codexDir.appendingPathComponent("hooks.json") }
    /// Orca (a terminal app) runs Codex with its own CODEX_HOME, so it needs connecting separately.
    public var orcaCodexDir: URL { home.appendingPathComponent("Library/Application Support/orca/codex-runtime-home/home", isDirectory: true) }
    /// The Codex plugin marketplace Readback writes; Codex installs the plugin from it into its cache.
    public var codexPluginSource: URL { support.appendingPathComponent("CodexPlugin", isDirectory: true) }
    public var openCodeDir: URL { home.appendingPathComponent(".config/opencode", isDirectory: true) }
    public var openCodePlugin: URL { openCodeDir.appendingPathComponent("plugins/readback.js") }
}

/// One place Readback connects to: a tool's config folder. Codex can have two on one Mac.
public enum ToolHome: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, opencode
    /// Codex as Orca runs it, with Orca's own CODEX_HOME.
    case orcaCodex = "orca"

    public var id: String { rawValue }

    public var tool: Tool {
        switch self {
        case .claude: return .claude
        case .codex, .orcaCodex: return .codex
        case .opencode: return .opencode
        }
    }

    public var title: String { self == .orcaCodex ? "Codex in Orca" : tool.name }

    /// A tool's usual folder, as `readback connect <tool>` means it.
    public init(_ tool: Tool) {
        switch tool {
        case .claude: self = .claude
        case .codex: self = .codex
        case .opencode: self = .opencode
        }
    }
}

/// Connects and disconnects the tools by editing their files on disk. Before a file of the
/// person's is changed, their version is kept beside it as `<name>.before-readback`.
public struct IntegrationFiles {
    public let paths: ReadbackPaths
    /// The CLI the hooks run (…/Readback.app/Contents/Helpers/readback).
    public let cli: String
    /// The Claude Code mod folder shipped inside the app, copied out on connect.
    public let bundledPlugin: URL?
    /// Runs `codex <args>` against a Codex home: Codex installs plugins itself. nil when no
    /// codex command was found (tests pass a fake).
    public let codex: CodexRun?
    /// The Codex plugin's artwork shipped inside the app, copied into the plugin on connect. nil
    /// leaves the plugin without pictures (tests).
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
        /// A file where Readback writes its own is someone else's; Readback leaves it alone.
        case notOurs(String)

        public var description: String {
            switch self {
            case .toolNotInstalled(let tool, let path): return "\(tool.name) doesn't seem to be installed (no \(path))"
            case .unreadable(let path, let why): return "Couldn't read \(path): \(why)"
            case .noCodexCommand: return "Couldn't find Codex to install the plugin with. Install the Codex app or the codex command, then try again."
            case .notOurs(let path): return "\(path) is already there and Readback didn't write it, so it was left alone. Move or rename it, then connect again."
            }
        }
    }

    public func folder(_ home: ToolHome) -> URL {
        switch home {
        case .claude: return paths.claudeDir
        case .codex: return paths.codexDir
        case .orcaCodex: return paths.orcaCodexDir
        case .opencode: return paths.openCodeDir
        }
    }

    public func isInstalled(_ home: ToolHome) -> Bool {
        FileManager.default.fileExists(atPath: folder(home).path)
    }

    /// What to show: every tool's usual folder, and Orca's Codex when Orca is on this Mac.
    public var homes: [ToolHome] {
        [.claude, .codex, .opencode] + (isInstalled(.orcaCodex) ? [.orcaCodex] : [])
    }

    public func status(_ home: ToolHome) throws -> Integrations.Status {
        switch home {
        case .claude: return try claudeStatus()
        case .codex, .orcaCodex: return try codexStatus(home: folder(home))
        case .opencode: return openCodeStatus()
        }
    }

    public func connect(_ home: ToolHome) throws {
        guard isInstalled(home) else { throw Failure.toolNotInstalled(home.tool, folder(home).path) }
        switch home {
        case .claude:
            try copyPlugin()
            var root = try readJSON(paths.claudeSettings)
            Integrations.connectClaude(&root, cli: cli, pluginDir: paths.claudePlugin.path)
            try writeJSON(root, to: paths.claudeSettings)
        case .codex, .orcaCodex:
            try connectCodex(home: folder(home))
        case .opencode:
            let file = paths.openCodePlugin
            if FileManager.default.fileExists(atPath: file.path),
               (try? String(contentsOf: file, encoding: .utf8)).flatMap(Integrations.openCodeCLI(in:)) == nil {
                throw Failure.notOurs(file.path)
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Integrations.openCodePlugin(cli: cli).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    public func disconnect(_ home: ToolHome) throws {
        switch home {
        case .claude:
            guard FileManager.default.fileExists(atPath: paths.claudeSettings.path) else { return }
            var root = try readJSON(paths.claudeSettings)
            Integrations.disconnectClaude(&root)
            try writeJSON(root, to: paths.claudeSettings)
        case .codex, .orcaCodex:
            try disconnectCodex(home: folder(home))
        case .opencode:
            if let source = try? String(contentsOf: paths.openCodePlugin, encoding: .utf8),
               Integrations.openCodeCLI(in: source) != nil {
                try FileManager.default.removeItem(at: paths.openCodePlugin)
            }
        }
    }

    // MARK: Claude Code

    /// Connected means both hooks run this CLI, and the mod is listed and in place (it carries
    /// /speak and /read). A copy of the app without a bundled mod (a dev build) skips the mod.
    private func claudeStatus() throws -> Integrations.Status {
        let root = try readJSON(paths.claudeSettings)
        let hooks = Integrations.hookStatus(root, cli: cli, expecting: Integrations.claudeHooks)
        // The mod listed with the hooks gone is still Readback's, and Disconnect has to show.
        if hooks == .notConnected { return Integrations.listsOurPluginDir(root) ? .incomplete : .notConnected }
        guard hooks == .connected, let bundledPlugin else { return hooks }
        return Integrations.listsOurPluginDir(root) && modFilesPresent(bundledPlugin) ? .connected : .incomplete
    }

    /// Every file the app's mod has is in the copy (an older copy's contents are fine: launch
    /// refreshes it).
    private func modFilesPresent(_ bundled: URL) -> Bool {
        relativeFiles(in: bundled).allSatisfy { FileManager.default.fileExists(atPath: paths.claudePlugin.path + $0) }
    }

    private func relativeFiles(in folder: URL) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let base = folder.standardizedFileURL.path
        var found: [String] = []
        for case let file as URL in walker where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            found.append(String(file.standardizedFileURL.path.dropFirst(base.count)))
        }
        return found
    }

    /// Launch: brings the copied mod up to this version of the app. The copy is shared by every
    /// Claude Code login connected to Readback, a CLAUDE_CONFIG_DIR one included, and the app
    /// only sees ~/.claude, so a copy that's there is refreshed whatever ~/.claude says (deep
    /// review 2026-11-26, P2-2). With no copy, one is put back only when ~/.claude lists it.
    public func refreshPlugin() throws {
        if !FileManager.default.fileExists(atPath: paths.claudePlugin.path) {
            switch try? status(.claude) {
            case .connected?, .incomplete?: break
            default: return
            }
        }
        try copyPlugin()
    }

    /// Copies the mod out of the app, only when the app's copy differs: every open Claude Code
    /// session reloads the mod (and says so) whenever its files change.
    public func copyPlugin() throws {
        guard let bundledPlugin else { return }
        let fm = FileManager.default
        if pluginIsCurrent(bundledPlugin) { return }
        try fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let staging = paths.support.appendingPathComponent(AppBundle.claudeCodePluginFolder + ".new", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: bundledPlugin, to: staging)
        if fm.fileExists(atPath: paths.claudePlugin.path) { try fm.removeItem(at: paths.claudePlugin) }
        try fm.moveItem(at: staging, to: paths.claudePlugin)
    }

    /// Files Claude Code adds beside the copy (its type files) don't count.
    private func pluginIsCurrent(_ bundled: URL) -> Bool {
        let fm = FileManager.default
        let files = relativeFiles(in: bundled)
        guard !files.isEmpty else { return false }
        return files.allSatisfy { relative in
            guard let a = fm.contents(atPath: bundled.standardizedFileURL.path + relative),
                  let b = fm.contents(atPath: paths.claudePlugin.path + relative) else { return false }
            return a == b
        }
    }

    // MARK: Codex

    /// Writes Readback's plugin marketplace, has Codex install the plugin into `home`, and removes
    /// the hooks older Readback versions put in hooks.json so no reply is read twice. A broken
    /// hooks.json is refused before anything changes. Running it again is harmless: Codex
    /// reinstalls the same copy.
    private func connectCodex(home: URL) throws {
        // Checked first, so a broken file stops Connect before Codex changes anything; read
        // again after the install, so an edit made meanwhile isn't written over.
        _ = try readJSON(home.appendingPathComponent("hooks.json"))
        guard let codex else { throw Failure.noCodexCommand }
        try writeCodexPlugin()
        try codex(["plugin", "marketplace", "add", paths.codexPluginSource.path], home)
        try codex(["plugin", "add", CodexPlugin.selector], home)
        try removeOldCodexHooks(home: home)
    }

    private func disconnectCodex(home: URL) throws {
        if CodexPlugin.isEnabled(configToml: codexConfig(home: home)) {
            guard let codex else { throw Failure.noCodexCommand }
            try codex(["plugin", "remove", CodexPlugin.selector], home)
            try codex(["plugin", "marketplace", "remove", CodexPlugin.marketplace], home)
            // Orca's Codex home links its plugins folder to ~/.codex/plugins, so removing the
            // plugin from one home deletes the copy the other runs. Put it back for any home
            // that still has it switched on.
            // The usual ~/.codex too: with CODEX_HOME pointing at Orca, `folder(.codex)` is Orca's.
            let homes = [paths.usualCodexDir, folder(.codex), folder(.orcaCodex)].map(\.standardizedFileURL)
            for other in Set(homes) where other != home.standardizedFileURL {
                if CodexPlugin.isEnabled(configToml: codexConfig(home: other)), installedCodexHooks(home: other) == nil {
                    try codex(["plugin", "add", CodexPlugin.selector], other)
                }
            }
        }
        try removeOldCodexHooks(home: home)
    }

    /// Connected means Codex has the plugin enabled, its installed copy runs this CLI, and a
    /// person approved both hooks (until then Codex skips them).
    private func codexStatus(home: URL) throws -> Integrations.Status {
        if !Integrations.ourCommands(try readJSON(home.appendingPathComponent("hooks.json"))).isEmpty { return .outdated }
        let config = codexConfig(home: home)
        guard CodexPlugin.isEnabled(configToml: config) else { return .notConnected }
        // Switched on in config.toml with no installed copy: Readback's, but not working.
        guard let installed = installedCodexHooks(home: home) else { return .incomplete }
        let status = Integrations.hookStatus(try readJSON(installed), cli: cli, expecting: CodexPlugin.hooks)
        // Switched on, so it's Readback's even with none of its hooks in the copy.
        if status == .notConnected { return .incomplete }
        guard status == .connected else { return status }
        let version = installed.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        if version != CodexPlugin.version { return .updateAvailable }
        return CodexPlugin.approvedEvents(configToml: config).isSuperset(of: CodexPlugin.hookEvents) ? .connected : .waitingForApproval
    }

    private func codexConfig(home: URL) -> String {
        (try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8)) ?? ""
    }

    /// The hooks.json of the copy Codex installed, in <home>/plugins/cache/readback/readback/<version>/:
    /// this version's, else the newest there.
    private func installedCodexHooks(home: URL) -> URL? {
        let cache = home.appendingPathComponent("plugins/cache/\(CodexPlugin.marketplace)/\(CodexPlugin.name)", isDirectory: true)
        let versioned = cache.appendingPathComponent("\(CodexPlugin.version)/hooks/hooks.json")
        if FileManager.default.fileExists(atPath: versioned.path) { return versioned }
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        return versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
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
            let data = try Data(contentsOf: bundledCodexAssets.appendingPathComponent(name))
            let target = assets.appendingPathComponent(name)
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

    // MARK: OpenCode

    private func openCodeStatus() -> Integrations.Status {
        guard let source = try? String(contentsOf: paths.openCodePlugin, encoding: .utf8),
              let other = Integrations.openCodeCLI(in: source) else { return .notConnected }
        return other == cli ? .connected : .stale(other)
    }

    // MARK: Files

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

    /// The backup is the person's own version of the file: it's written when there's none yet, or
    /// when the file holds nothing of Readback's. So connecting twice doesn't replace it with a
    /// file Readback already changed.
    /// Nothing to change, nothing written: a file stays in the person's own layout until Readback
    /// actually edits it.
    private func writeJSON(_ value: JSONValue, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), (try? readJSON(url)) == value { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("before-readback")
        if fm.fileExists(atPath: url.path) {
            let theirs = (try? readJSON(url)).map { !Integrations.holdsAnythingOurs($0) } ?? false
            if theirs || !fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: url, to: backup)
            }
        }
        try value.formatted().write(to: url, atomically: true, encoding: .utf8)
    }
}
