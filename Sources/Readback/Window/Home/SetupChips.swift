import ReadbackCore
import SwiftUI

/// Home's "Read every reply" row: one switch per tool, always there (owner, 2026-11-25). The
/// same setting as Reading's switches.
struct EveryReplyRow: View {
    @ObservedObject var prefs: Preferences

    /// One line when it fits; in a narrow window the title goes above and the switches get a line
    /// of their own. Labels never wrap (owner, 2026-11-25: "OpenCo/de" at 760 pt was unacceptable).
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                title
                Spacer(minLength: 12)
                switches
            }
            .padding(.horizontal, Spacing.l)
            .frame(height: ControlMetrics.height + 20)
            VStack(alignment: .leading, spacing: 10) {
                title
                switches
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .surface()
    }

    private var title: some View {
        Text("Read every reply").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
    }

    private var switches: some View {
        HStack(spacing: 22) {
            ForEach(Tool.allCases, id: \.self) { tool in
                HStack(spacing: 10) {
                    Text(tool.name).font(.system(size: 13)).lineLimit(1).fixedSize()
                    ReadbackSwitch(isOn: Binding(get: { prefs.readsEveryReply(tool) },
                                                 set: { prefs.setReadsEveryReply(tool, $0) }))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Read every \(tool.name) reply out loud")
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(prefs.readsEveryReply(tool) ? "on" : "off")
                .accessibilityAction { prefs.setReadsEveryReply(tool, !prefs.readsEveryReply(tool)) }
            }
        }
        .fixedSize()
    }
}

/// Home's Setup: the voice in use and each tool's state at a glance. A tool that needs the person
/// is a chip that is itself the button (no plate inside a plate, owner, 2026-11-25), and it opens
/// Connections, where that tool's fix lives.
struct SetupChips: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var runtime: Runtime
    @ObservedObject var downloads: ModelDownloads
    @ObservedObject var connections: Connections
    let openConnections: () -> Void
    let openVoices: () -> Void

    var body: some View {
        ChipFlow(spacing: 8) {
            voiceChip
            ForEach(connections.homes.filter { connections.rows[$0]?.installed == true }, id: \.self) { home in
                toolChip(home, connections.rows[home]!)
            }
        }
    }

    /// While replies fall back to the macOS voice, the chip asks for the engine the way a tool chip
    /// asks for what it needs (EngineInstall.nudge; owner, 2026-11-26). All of them open Voices.
    @ViewBuilder private var voiceChip: some View {
        switch runtime.nudge(for: prefs) {
        case .getIt?:
            SetupChip(action: openVoices, help: "Opens Voices", callToAction: "Get the natural voice", leadsWithMark: false) {
                Text("Voice").foregroundStyle(.secondary)
                Text("macOS voice for now")
            }
        case .downloading?:
            let percent = runtime.progress(with: downloads).map { DownloadAmount.percent($0.fraction) } ?? "0%"
            // The voice being fetched: the one picked, or Kokoro when the install started from the macOS voice.
            let name = prefs.engine.needsRuntime ? VoiceSummary.of(prefs, runtime).engine : EngineKind.kokoro.title.components(separatedBy: " (").first ?? "Kokoro"
            SetupChip(action: openVoices, help: "Opens Voices", leadsWithMark: false) {
                Text("Voice").foregroundStyle(.secondary)
                Text("\(name) · downloading \(percent)").monospacedDigit()
            }
        case .didntFinish?:
            SetupChip(action: openVoices, help: "Opens Voices", callToAction: "Try again", leadsWithMark: false) {
                Text("Voice").foregroundStyle(.secondary)
                Text("download didn't finish")
            }
        case nil:
            let voice = VoiceSummary.of(prefs, runtime)
            SetupChip(action: openVoices, help: "Opens Voices", leadsWithMark: false) {
                Text("Voice").foregroundStyle(.secondary)
                Text(voice.name.isEmpty ? voice.engine : "\(voice.engine) · \(voice.name)")
            }
        }
    }

    @ViewBuilder private func toolChip(_ home: ToolHome, _ row: Connections.Row) -> some View {
        if let need = Self.need(row) {
            SetupChip(action: openConnections, help: "Opens Connections", callToAction: need.action) {
                ToolMark(tool: home.tool, size: 20)
                Text(home.title)
                Text(need.state).foregroundStyle(.secondary)
            }
        } else {
            SetupChip(action: openConnections, help: "Opens Connections") {
                ToolMark(tool: home.tool, size: 20)
                Text(home.title)
                Text(Self.settled(row)).foregroundStyle(.secondary)
            }
        }
    }

    /// A tool that needs nothing from the person: connected, or what it's in the middle of, in the
    /// Connections page's words. "Connected" only once it is (deep review 2026-11-26, P2-10).
    static func settled(_ row: Connections.Row) -> String {
        switch row.busy {
        case .connecting?: return "connecting…"
        case .disconnecting?: return "disconnecting…"
        case nil: return "connected"
        }
    }

    /// What a tool needs from the person, in a few words, and the chip's action; nil when it's fine.
    static func need(_ row: Connections.Row) -> (state: String, action: String)? {
        if row.busy != nil { return nil }
        if row.error != nil { return ("didn't connect", "Fix") }
        switch row.status {
        case .connected: return nil
        case .waitingForApproval: return ("needs you to approve its hooks", "Show me")
        case .stale, .incomplete: return ("needs reconnecting", "Fix")
        case .outdated, .updateAvailable: return ("has an update", "Update")
        case .notConnected: return ("isn't connected", "Connect")
        }
    }
}

/// A 34 pt chip with the controls' tint and edge. With a call to action it shows a hairline
/// divider and the action in bold with an arrow that nudges on hover.
private struct SetupChip<Content: View>: View {
    let action: () -> Void
    let help: String
    var callToAction: String?
    /// 7 pt before a leading 20 pt mark (level with the 7 pt above and below it), 12 before text.
    var leadsWithMark = true
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.radius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                content()
                if let callToAction {
                    Rectangle().fill(ControlMetrics.hoverEdge(scheme)).frame(width: 0.5, height: 16).padding(.horizontal, 2)
                    HStack(spacing: 4) {
                        Text(callToAction).fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .offset(x: hovering && !reduceMotion ? 2 : 0)
                    }
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.leading, leadsWithMark ? 7 : 12)
            .padding(.trailing, 12)
            .frame(height: ControlMetrics.height)
            .background(hovering ? ControlMetrics.hoverFill(scheme) : ControlMetrics.fill(scheme), in: shape)
            .overlay { Hairline(shape, hovering ? ControlMetrics.hoverEdge(scheme) : ControlMetrics.edge(scheme)) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .keyboardFocusRing(focused, shape)
        .onHover { hovering = $0 }
        .animation(Motion.spring(reduceMotion), value: hovering)
        .help(help)
    }
}

/// Lays its children out left to right, wrapping onto the next line when they run out of room.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
