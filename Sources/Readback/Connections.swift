import Foundation
import ReadbackCore

/// The Connections tab's state: which tools are installed and connected, and the buttons' actions.
@MainActor
final class Connections: ObservableObject {
    struct Row: Equatable {
        var installed: Bool
        var status: Integrations.Status
        var error: String?
        /// Codex only: whether a person approved the plugin's two hooks in Codex.
        var approved = false
        /// A Connect or Disconnect is running for this row.
        var busy = false
    }

    @Published private(set) var rows: [Tool: Row] = [:]
    /// Codex as Orca runs it (its own Codex home), when Orca is on this Mac.
    @Published private(set) var orca: Row?
    /// A failed Connect or Disconnect, by row ("orca" for Orca's), kept until the next try so the
    /// page's regular refresh doesn't wipe it.
    private var actionErrors: [String: String] = [:]
    private static let orcaKey = "orca"
    /// Rows with a Connect or Disconnect running.
    private var busy: Set<String> = []
    /// Connects and disconnects run here, one at a time and off the main thread: finding codex
    /// can mean asking the login shell, and Codex and Orca share one plugin folder.
    private let queue = DispatchQueue(label: "local.readback.connections")

    var files: IntegrationFiles { Self.makeFiles() }

    /// Safe from any thread: connects build their own on the background queue.
    nonisolated static func makeFiles() -> IntegrationFiles {
        IntegrationFiles(
            // The rows mean each tool's usual folder (~/.codex, ~/.claude). A CODEX_HOME or
            // CLAUDE_CONFIG_DIR the app was started with (from a terminal) must not swap them:
            // the CLI's `readback connect` is the way to reach another folder.
            paths: ReadbackPaths(home: ReadbackPaths.defaultHome),
            cli: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/readback").path,
            bundledPlugin: Bundle.main.resourceURL?.appendingPathComponent("ClaudeCodePlugin", isDirectory: true),
            codex: CodexCLI.lazyRunner(),
            bundledCodexAssets: Bundle.main.resourceURL?.appendingPathComponent("CodexPluginAssets", isDirectory: true)
        )
    }

    init() { refresh() }

    /// Reads every tool's state again. The page calls this every few seconds, so it only
    /// publishes what changed.
    func refresh() {
        let files = self.files
        var fresh: [Tool: Row] = [:]
        for tool in Tool.allCases {
            let installed = files.isToolInstalled(tool)
            do {
                var row = Row(installed: installed, status: try files.status(tool))
                if tool == .codex { row.approved = files.codexHooksApproved(home: files.paths.codexDir) }
                fresh[tool] = row
            } catch {
                fresh[tool] = Row(installed: installed, status: .notConnected, error: "\(error)")
            }
            if let failed = actionErrors[tool.rawValue] { fresh[tool]?.error = failed }
            fresh[tool]?.busy = busy.contains(tool.rawValue)
        }
        if fresh != rows { rows = fresh }

        let orcaHome = files.paths.orcaCodexDir
        var orcaRow: Row?
        if FileManager.default.fileExists(atPath: orcaHome.path) {
            do {
                orcaRow = Row(installed: true, status: try files.codexStatus(home: orcaHome),
                              approved: files.codexHooksApproved(home: orcaHome))
            } catch {
                orcaRow = Row(installed: true, status: .notConnected, error: "\(error)")
            }
            if let failed = actionErrors[Self.orcaKey] { orcaRow?.error = failed }
            orcaRow?.busy = busy.contains(Self.orcaKey)
        }
        if orcaRow != orca { orca = orcaRow }
    }

    func connect(_ tool: Tool) {
        run("connect \(tool.name)", failing: tool) { try $0.connect(tool) }
    }

    func disconnect(_ tool: Tool) {
        run("disconnect \(tool.name)", failing: tool) { try $0.disconnect(tool) }
    }

    func connectOrca() {
        run("connect Codex in Orca", failing: nil) { try $0.connectCodex(home: $0.paths.orcaCodexDir) }
    }

    func disconnectOrca() {
        run("disconnect Codex in Orca", failing: nil) { try $0.disconnectCodex(home: $0.paths.orcaCodexDir) }
    }

    /// Does `change` in the background, logs how it went, and shows a failure on the tool's row
    /// (Orca's when nil). The row shows it's busy meanwhile.
    private func run(_ what: String, failing tool: Tool?, _ change: @escaping @Sendable (IntegrationFiles) throws -> Void) {
        let key = tool?.rawValue ?? Self.orcaKey
        busy.insert(key)
        refresh()
        queue.async { [weak self] in
            var error: String?
            var full: String?
            do { try change(Self.makeFiles()) } catch let caught { error = "\(caught)"; full = String(reflecting: caught) }
            let failure = error
            let details = full
            Task { @MainActor in
                guard let self else { return }
                self.busy.remove(key)
                if let failure {
                    Log.error("couldn't \(what): \(details ?? failure)")
                } else {
                    Log.info("\(what): done")
                }
                self.actionErrors[key] = failure
                self.refresh()
            }
        }
    }

    /// When Claude Code is connected, refresh the copied mod so it matches this version of the app.
    func refreshPlugin() {
        guard rows[.claude]?.status == .connected else { return }
        do {
            try files.copyPlugin()
        } catch {
            Log.error("couldn't refresh the Claude Code mod: \(error)")
        }
    }
}
