import ReadbackCore
import SwiftUI

struct ConnectionSettings: View {
    @ObservedObject var connections: Connections
    @ObservedObject var replies: Replies

    var body: some View {
        Form {
            Section {
                ForEach(connections.homes) { home in
                    ConnectionRow(home: home, row: connections.row(home),
                                  lastReply: lastReply(to: home),
                                  connect: { connections.connect(home) },
                                  disconnect: { connections.disconnect(home) })
                }
            } header: {
                Text("Coding tools")
            } footer: {
                FormNote("Connecting hands each finished reply to Readback and stops the reading when you send a new message. Claude Code and Codex also get /speak and /read. Before Readback changes one of a tool's files, it keeps the old version beside it as <name>.before-readback.")
            }
        }
        .formStyle(CardFormStyle())
        // Approving the Codex hooks happens in Codex, so look again while the page is open.
        .task {
            while !Task.isCancelled {
                connections.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Replies carry their tool but not which home they came through, so a reply only counts as
    /// proof for a tool with one home on this Mac.
    private func lastReply(to home: ToolHome) -> Date? {
        guard connections.homes.filter({ $0.tool == home.tool }).count == 1 else { return nil }
        return replies.all.first(where: { $0.request.tool == home.tool })?.received
    }
}

private struct ConnectionRow: View {
    let home: ToolHome
    let row: Connections.Row?
    /// When the newest reply from this tool arrived, as proof the connection works.
    let lastReply: Date?
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        LabeledContent {
            button
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ToolTile(tool: home.tool, connected: ConnectionText.isWorking(row))
                VStack(alignment: .leading, spacing: 2) {
                    Text(home.title)
                    Text(ConnectionText.detail(home, row, lastReply: lastReply))
                        .font(.caption)
                        .foregroundStyle(row?.error == nil ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var button: some View {
        if row?.busy != nil {
            ProgressView().controlSize(.small)
        } else {
            actionButton
        }
    }

    /// Whatever state it's in, a row with anything of Readback's in it can be disconnected.
    @ViewBuilder private var actionButton: some View {
        switch row?.status {
        case .connected?, .waitingForApproval?: Button("Disconnect", action: disconnect)
        case .stale?, .incomplete?: repairButtons("Reconnect")
        case .outdated?, .updateAvailable?: repairButtons("Update")
        default: Button("Connect", action: connect).disabled(row?.installed != true)
        }
    }

    private func repairButtons(_ title: String) -> some View {
        HStack(spacing: 8) {
            Button("Disconnect", action: disconnect)
            Button(title, action: connect)
        }
    }
}

/// What a tool home's row says, shared by Connections and the first-run setup sheet so they agree.
enum ConnectionText {
    static func isWorking(_ row: Connections.Row?) -> Bool {
        row?.status == .connected
    }

    /// Where the person approves Readback's hooks. Orca's Codex has its own home, which the Codex
    /// app never reads.
    static func howToApprove(_ home: ToolHome) -> String {
        home == .orcaCodex
            ? "In an Orca Codex pane, type /hooks and approve both Readback hooks."
            : "In the Codex app, quit and reopen it, then open Settings > Hooks and approve both Readback hooks. In a terminal, type /hooks."
    }

    static func detail(_ home: ToolHome, _ row: Connections.Row?, lastReply: Date?) -> String {
        if let busy = row?.busy { return busy == .disconnecting ? "Disconnecting…" : "Connecting…" }
        if let error = row?.error { return error }
        guard let row, row.installed else { return "Not installed on this Mac." }
        switch row.status {
        case .stale:
            return "Connected to another copy of Readback (the app moved?). Reconnect to use this one."
        case .incomplete:
            return home.tool == .codex
                ? "Readback's Codex plugin is switched on but isn't installed, or its hooks are missing. Reconnect to put it back."
                : "Part of Readback's setup is missing here (a hook or the /speak commands). Reconnect to put it back."
        case .outdated:
            return "Connected the old way, without /speak or /read. Update to switch to Readback's Codex plugin. Codex then asks you to approve its hooks once more."
        case .updateAvailable:
            return "Connected. A newer version of Readback's Codex plugin is ready: Update installs it, and Codex asks you to approve its hooks once more."
        case .waitingForApproval:
            return "One step left. \(howToApprove(home))"
        case .connected:
            switch home.tool {
            case .claude: return "Connected. In a session: /speak on, /speak off, /read. Start a new session to pick up the commands."
            case .codex:
                if let lastReply {
                    return "Working. Last reply \(lastReply.formatted(.relative(presentation: .named))). In a chat: /speak on, /speak off, /read."
                }
                return "Connected. In a chat: /speak on, /speak off, /read. Send a message in Codex to try it."
            case .opencode: return "Connected. Restart OpenCode to load the plugin."
            }
        case .notConnected:
            switch home.tool {
            case .claude: return "Edits ~/.claude/settings.json and adds the /speak and /read commands."
            case .codex: return "Installs Readback's Codex plugin, with /speak and /read."
            case .opencode: return "Adds ~/.config/opencode/plugins/readback.js."
            }
        }
    }
}

/// A small tile that tells the tools apart at a glance, System Settings style: tinted when the
/// tool is connected, grey when it isn't. Generic symbols, not the tools' own logos.
struct ToolTile: View {
    let tool: Tool
    let connected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(connected ? Color.accentColor : Color.gray.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch tool {
        case .claude: return "terminal"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "curlybraces"
        }
    }
}
