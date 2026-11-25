import ReadbackCore
import SwiftUI

struct ConnectionSettings: View {
    @ObservedObject var connections: Connections
    @ObservedObject var replies: Replies

    var body: some View {
        Form {
            Section {
                ForEach(Tool.allCases) { tool in
                    ConnectionRow(tool: tool, title: tool.name, row: connections.rows[tool],
                                  lastReply: lastReply(from: tool),
                                  connect: { connections.connect(tool) },
                                  disconnect: { connections.disconnect(tool) })
                }
                if let orca = connections.orca {
                    ConnectionRow(tool: .codex, title: "Codex in Orca", row: orca, lastReply: nil, orca: true,
                                  connect: { connections.connectOrca() },
                                  disconnect: { connections.disconnectOrca() })
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

    private func lastReply(from tool: Tool) -> Date? {
        replies.all.first(where: { $0.source.flatMap(Tool.init(source:)) == tool })?.received
    }
}

private struct ConnectionRow: View {
    let tool: Tool
    let title: String
    let row: Connections.Row?
    /// When the newest reply from this tool arrived, as proof the connection works.
    let lastReply: Date?
    var orca = false
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        LabeledContent {
            button
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ToolTile(tool: tool, connected: ConnectionText.isWorking(tool, row))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(ConnectionText.detail(tool, row, lastReply: lastReply, orca: orca))
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
        if row?.busy == true {
            ProgressView().controlSize(.small)
        } else {
            actionButton
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch row?.status {
        case .connected?: Button("Disconnect", action: disconnect)
        case .stale?: Button("Reconnect", action: connect)
        case .outdated?, .updateAvailable?: Button("Update", action: connect)
        default: Button("Connect", action: connect).disabled(row?.installed != true)
        }
    }
}

/// What a tool's row says, shared by Connections and the first-run setup sheet so they agree.
enum ConnectionText {
    /// Fully working: connected, and for Codex, approved.
    static func isWorking(_ tool: Tool, _ row: Connections.Row?) -> Bool {
        row?.status == .connected && (tool != .codex || row?.approved == true)
    }

    /// Slash commands, kept on one line: a plain "/" lets the text wrap between "/" and "hooks".
    static func command(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: "/\u{2060}")
    }

    /// `orca`: the row for Codex in Orca, which has its own Codex home that the Codex app never reads.
    static func detail(_ tool: Tool, _ row: Connections.Row?, lastReply: Date?, orca: Bool = false) -> String {
        if row?.busy == true { return row?.status == .connected ? "Disconnecting…" : "Connecting…" }
        if let error = row?.error { return error }
        guard let row, row.installed else { return "Not installed on this Mac." }
        switch row.status {
        case .stale:
            return "Connected to another copy of Readback (the app moved?). Reconnect to use this one."
        case .outdated:
            return "Connected the old way, without \(command("/speak")) or \(command("/read")). Update to switch to Readback's Codex plugin. Codex then asks you to approve its hooks once more."
        case .updateAvailable:
            return "Connected. A newer version of Readback's Codex plugin is ready: Update installs it, and Codex asks you to approve its hooks once more."
        case .connected:
            switch tool {
            case .claude: return "Connected. In a session: \(command("/speak on, /speak off, /read")). Start a new session to pick up the commands."
            case .codex:
                guard row.approved else {
                    if orca {
                        return "One step left: in an Orca Codex pane, type \(command("/hooks")) and approve Readback's two hooks."
                    }
                    return "One step left: approve Readback's two hooks in Codex. In the Codex app, open Settings > Hooks (quit and reopen the app first if it's open). In the terminal, type \(command("/hooks"))."
                }
                if let lastReply {
                    return "Working. Last reply \(lastReply.formatted(.relative(presentation: .named))). In a chat: \(command("/speak on, /speak off, /read"))."
                }
                return "Connected. In a chat: \(command("/speak on, /speak off, /read")). Send a message in Codex to try it."
            case .opencode: return "Connected. Restart OpenCode to load the plugin."
            }
        case .notConnected:
            switch tool {
            case .claude: return "Edits ~/.claude/settings.json and adds the \(command("/speak")) and \(command("/read")) commands."
            case .codex: return "Installs Readback's Codex plugin, with \(command("/speak")) and \(command("/read"))."
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
