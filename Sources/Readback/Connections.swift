import Foundation
import ReadbackCore

/// The Connections page's state: each tool home's status, and the buttons' actions.
@MainActor
final class Connections: ObservableObject {
    struct Row: Equatable {
        var installed: Bool
        var status: Integrations.Status
        var error: String?
        /// What's running for this row, if anything.
        var busy: Action?
    }

    enum Action: Equatable {
        case connecting, disconnecting
    }

    /// The homes to show: every tool, plus Codex in Orca when Orca is on this Mac.
    @Published private(set) var homes: [ToolHome] = []
    @Published private(set) var rows: [ToolHome: Row] = [:]
    /// A failed Connect or Disconnect, kept until the next try so the page's regular refresh
    /// doesn't wipe it.
    private var actionErrors: [ToolHome: String] = [:]
    private var busy: [ToolHome: Action] = [:]
    /// Connects and disconnects run here, one at a time and off the main thread: finding codex
    /// can mean asking the login shell, and Codex and Orca share one plugin folder.
    private let queue = DispatchQueue(label: "local.readback.connections")

    var files: IntegrationFiles { Self.makeFiles() }

    /// Safe from any thread: connects build their own on the background queue.
    nonisolated static func makeFiles() -> IntegrationFiles {
        // The rows mean each tool's usual folder (~/.codex, ~/.claude). A CODEX_HOME or
        // CLAUDE_CONFIG_DIR the app was started with (from a terminal) must not swap them:
        // the CLI's `readback connect` is the way to reach another folder.
        AppBundle(url: Bundle.main.bundleURL).integrationFiles(paths: ReadbackPaths(home: ReadbackPaths.defaultHome))
    }

    init() { refresh() }

    func row(_ home: ToolHome) -> Row? { rows[home] }

    /// Reads every home's state again. The page calls this every few seconds, so it only
    /// publishes what changed.
    func refresh() {
        let files = self.files
        let found = files.homes
        var fresh: [ToolHome: Row] = [:]
        for home in found {
            let installed = files.isInstalled(home)
            do {
                fresh[home] = Row(installed: installed, status: try files.status(home))
            } catch {
                fresh[home] = Row(installed: installed, status: .notConnected, error: "\(error)")
            }
            if let failed = actionErrors[home] { fresh[home]?.error = failed }
            fresh[home]?.busy = busy[home]
        }
        if found != homes { homes = found }
        if fresh != rows { rows = fresh }
    }

    func connect(_ home: ToolHome) {
        run("connect \(home.title)", home, .connecting) { try $0.connect(home) }
    }

    func disconnect(_ home: ToolHome) {
        run("disconnect \(home.title)", home, .disconnecting) { try $0.disconnect(home) }
    }

    /// Does `change` in the background, logs how it went, and shows a failure on the row. The row
    /// shows it's busy meanwhile.
    private func run(_ what: String, _ home: ToolHome, _ action: Action, _ change: @escaping @Sendable (IntegrationFiles) throws -> Void) {
        busy[home] = action
        refresh()
        queue.async { [weak self] in
            var error: String?
            var full: String?
            do { try change(Self.makeFiles()) } catch let caught { error = "\(caught)"; full = String(reflecting: caught) }
            let failure = error
            let details = full
            Task { @MainActor in
                guard let self else { return }
                self.busy[home] = nil
                if let failure {
                    Log.error("couldn't \(what): \(details ?? failure)")
                } else {
                    Log.info("\(what): done")
                }
                self.actionErrors[home] = failure
                self.refresh()
            }
        }
    }

    /// When Claude Code is connected, refresh the copied mod so it matches this version of the app.
    func refreshPlugin() {
        let files = self.files
        // Incomplete too: a missing or old mod file is exactly what this puts back.
        switch try? files.status(.claude) {
        case .connected?, .incomplete?: break
        default: return
        }
        do {
            try files.copyPlugin()
        } catch {
            Log.error("couldn't refresh the Claude Code mod: \(error)")
        }
    }
}
