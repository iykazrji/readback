import ReadbackCore
import SwiftUI

/// First launch: connect the coding tools Readback found and get the natural voice, with one
/// click. Then a list of steps shows what Readback is doing, what's done, the one thing only the
/// person can do (approve the hooks in Codex), a meter for the voice download, and what to try
/// next. The person agrees before any tool's settings change or anything big downloads, and can
/// close the sheet at any point: everything carries on, and Connections and Voices show it too.
struct SetupSheet: View {
    @ObservedObject var connections: Connections
    @ObservedObject var replies: Replies
    @ObservedObject var runtime: Runtime
    @ObservedObject var downloads: ModelDownloads
    @ObservedObject var prefs: Preferences
    let openConnections: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<ToolHome> = []
    /// Install the engine and Kokoro, the default voice. Ticked unless it's already there.
    @State private var getVoice = true
    @State private var started = false

    private var found: [ToolHome] {
        connections.homes.filter { connections.row($0)?.installed == true }
    }

    private func row(_ home: ToolHome) -> Connections.Row? { connections.row(home) }

    /// The natural voice can be offered: Apple silicon, and not installed or installing already.
    private var voiceOffered: Bool {
        switch runtime.state {
        case .notInstalled, .failed: return true
        default: return false
        }
    }

    /// What the voice download comes to: the engine as measured, plus Kokoro.
    private static let voiceTotal = Runtime.expectedFetchBytes + VoiceCatalog.kokoroBytes

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if found.isEmpty {
                nothingFound
            } else if started {
                progress
            } else {
                choices
            }
        }
        .padding(24)
        .frame(width: 520)
        .buttonStyle(.readback(.secondary))
        // Esc closes it on every screen, not only where there's a Cancel-style button.
        .onExitCommand { dismiss() }
        .onAppear {
            connections.refresh()
            runtime.refresh()
            // Everything found starts ticked, except what's already working.
            chosen = Set(found.filter { !ConnectionText.isWorking(row($0)) })
            getVoice = voiceOffered
        }
        // Codex's approval happens in Codex, so keep looking while the sheet is open.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                connections.refresh()
            }
        }
    }

    // MARK: Before: what to set up

    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle("Set up Readback")
            Text("Readback reads your coding tool's replies out loud, but it didn't find Claude Code, Codex or OpenCode on this Mac. Once you install one, connect it in Connections.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.readback(.primary)).keyboardShortcut(.defaultAction).buttonStyle(.readback(.primary))
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SheetTitle("Set up Readback")
                Text("Readback reads your coding tool's replies out loud. Pick what to set up:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(found) { home in
                    let working = ConnectionText.isWorking(row(home))
                    Toggle(isOn: binding(for: home)) {
                        ChoiceLabel(tile: ToolTile(tool: home.tool, connected: working), title: home.title,
                                    detail: working ? "Already connected"
                                        : row(home)?.status == .outdated ? "Set up by an older Readback. This updates it and adds \(home.tool.speakCommand) and \(home.tool.readCommand)."
                                        : row(home)?.status == .updateAvailable ? "A newer version of Readback's plugin is ready. This installs it."
                                        : nil)
                    }
                    .toggleStyle(.readbackCheckbox)
                    .disabled(working)
                }
                if voiceOffered {
                    Toggle(isOn: $getVoice) {
                        ChoiceLabel(tile: VoiceTile(ready: false), title: "Natural voice",
                                    detail: "Kokoro, downloaded to this Mac (\(Self.voiceTotal.formatted(.byteCount(style: .file)))). Until it's ready, replies use the macOS voice.")
                    }
                    .toggleStyle(.readbackCheckbox)
                }
            }
            FormNote("Connecting changes each tool's settings so its replies reach Readback. The old file stays beside it as <name>.before-readback, and Disconnect in Connections undoes it.")
            HStack {
                Spacer()
                Button("Not now") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set up") { start() }
                    .buttonStyle(.readback(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty && !(voiceOffered && getVoice))
            }
        }
    }

    // MARK: After: the steps

    private enum StepState: Equatable { case waiting, working, done, yourTurn, failed }

    private struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let state: StepState
        var meter: (fraction: Double, amount: String)?
    }

    private var steps: [Step] {
        var list: [Step] = []
        for home in found where chosen.contains(home) {
            let r = row(home)
            let inPlace = r?.status == .connected || r?.status == .waitingForApproval
            let state: StepState = r?.busy != nil ? .working : r?.error != nil ? .failed : inPlace ? .done : .waiting
            if home.tool == .codex {
                let orca = home == .orcaCodex
                list.append(Step(id: home.id + ".plugin", title: orca ? "Install the plugin in Orca's Codex" : "Install the Codex plugin",
                                 detail: state == .failed ? (r?.error ?? "") : state == .done ? "Installed, with /speak and /read." : "Adds Readback's plugin to Codex.",
                                 state: state))
                let approve: StepState = state != .done ? .waiting : r?.status == .connected ? .done : .yourTurn
                list.append(Step(id: home.id + ".approve", title: orca ? "Approve Readback in Orca" : "Approve Readback in Codex",
                                 detail: approveDetail(home, state: approve), state: approve))
            } else {
                let done = home.tool == .claude ? "Connected. Start a new Claude Code session to get /readback:speak and /readback:read."
                    : "Connected. Restart OpenCode to load it."
                list.append(Step(id: home.id, title: "Connect \(home.title)",
                                 detail: state == .failed ? (r?.error ?? "") : state == .done ? done : "Connecting…", state: state))
            }
        }
        if getVoice { list.append(voiceStep) }
        return list
    }

    private func approveDetail(_ home: ToolHome, state: StepState) -> String {
        switch state {
        case .done: return "Approved. \(home == .orcaCodex ? "Orca's" : "Codex") replies reach Readback now."
        case .yourTurn: return "Codex skips new hooks until you OK them. \(ConnectionText.howToApprove(home)) This updates by itself."
        default: return "After the plugin is in."
        }
    }

    private var voiceStep: Step {
        switch runtime.state {
        case .installed:
            return Step(id: "voice", title: "Get the natural voice", detail: "Ready. Replies are read with Kokoro.", state: .done)
        case .failed(let message):
            return Step(id: "voice", title: "Get the natural voice", detail: "Didn't finish: \(message). Try again from Voices.", state: .failed)
        case .installing:
            let kokoro = downloads.status(for: VoiceCatalog.kokoroModel)
            let phase: String
            switch runtime.step {
            case .python?: phase = "Getting Python"
            case .engine?: phase = "Downloading the voice engine"
            case .voice?: phase = kokoro == nil ? "Loading Kokoro" : "Downloading Kokoro"
            case nil: phase = "Starting"
            }
            let engine = min(runtime.fetchedBytes, Runtime.expectedFetchBytes)
            // Kokoro already on disk (a reinstall) counts as fetched once the engine is in.
            let model = kokoro?.received ?? (runtime.step == .voice ? VoiceCatalog.kokoroBytes : 0)
            let got = engine + model
            let fraction = min(Double(got) / Double(Self.voiceTotal), 0.99)
            let amount = DownloadAmount.text(received: got, total: Self.voiceTotal)
            return Step(id: "voice", title: "Get the natural voice", detail: "\(phase)…", state: .working,
                        meter: (fraction, amount))
        case .notInstalled, .unsupported:
            return Step(id: "voice", title: "Get the natural voice", detail: "Waiting to start.", state: .waiting)
        }
    }

    private var title: String {
        let states = steps.map(\.state)
        if states.contains(.failed) { return "Something needs a look" }
        if states.contains(.working) || states.contains(.waiting) { return "Setting up" }
        if states.contains(.yourTurn) { return "One thing left for you" }
        return "All set"
    }

    private var subtitle: String {
        let states = steps.map(\.state)
        if states.contains(.failed) { return "A step below didn't finish. The rest carried on." }
        if steps.contains(where: { $0.id == "voice" && $0.state == .working }) {
            return "You can close this window. The download carries on, and Voices shows how far it's got."
        }
        if states.contains(.working) || states.contains(.waiting) { return "This takes a few seconds." }
        if states.contains(.yourTurn) { return "Readback notices by itself once you've done it." }
        return "Readback is ready. Here's how to try it."
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SheetTitle(title)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Divider().padding(.leading, 42) }
                    StepRow(step: step)
                }
            }
            .surface(radius: Radius.sidebarCard)

            if !nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next").font(.headline)
                    ForEach(nextSteps, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Button("Open Connections") {
                    openConnections()
                    dismiss()
                }
                Spacer()
                Button(title == "All set" ? "Done" : "Close") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.readback(.primary))
            }
        }
    }

    /// What to try once things work, only for what was set up.
    private var nextSteps: [String] {
        let picked = found.filter(chosen.contains)
        var lines: [String] = []
        if picked.contains(where: { $0.tool == .claude }) {
            lines.append("In a new Claude Code session, type /readback:speak on, then ask anything. Readback reads the reply.")
        }
        let codex = picked.filter { $0.tool == .codex }
        if !codex.isEmpty {
            let approved = codex.allSatisfy { row($0)?.status == .connected }
            lines.append("In a Codex chat, type /speak on\(approved ? "" : " once you've approved Readback there"). /read reads the last reply again.")
        }
        if !picked.isEmpty {
            lines.append("To hear every reply without asking, switch it on for a tool in Reading.")
        }
        return lines
    }

    private func binding(for home: ToolHome) -> Binding<Bool> {
        // Already working shows ticked (and greyed out): it's connected, nothing to do.
        Binding(get: { chosen.contains(home) || ConnectionText.isWorking(row(home)) },
                set: { on in if on { chosen.insert(home) } else { chosen.remove(home) } })
    }

    private func start() {
        for home in found where chosen.contains(home) {
            connections.connect(home)
        }
        if voiceOffered {
            if getVoice {
                prefs.engine = .kokoro
                runtime.install(for: prefs)
            } else if prefs.engine.needsRuntime {
                // No download wanted: say what they'll actually hear.
                prefs.engine = .system
            }
        } else {
            getVoice = false
        }
        started = true
    }

    // MARK: Pieces

    private struct SheetTitle: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            Text(text)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private struct ChoiceLabel<Tile: View>: View {
        let tile: Tile
        let title: String
        let detail: String?
        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    // A lone name sits level with the tile's centre: its line is as tall as the tile.
                    // With a detail line under it, the name starts at the tile's top instead, so the
                    // pair reads as one block beside the tile (owner, 2026-11-25).
                    Text(title).frame(height: detail == nil ? 28 : nil)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private struct StepRow: View {
        let step: Step
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                StepIcon(state: step.state)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(step.title).fontWeight(step.state == .yourTurn ? .semibold : .regular)
                        if step.state == .yourTurn {
                            Text("Your turn")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(ControlMetrics.fill(scheme), in: Capsule())
                                .overlay(Hairline(Capsule(), ControlMetrics.edge(scheme)))
                        }
                    }
                    Text(step.detail)
                        .font(.callout)
                        .foregroundStyle(step.state == .failed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let meter = step.meter {
                        VStack(alignment: .leading, spacing: 4) {
                            Meter(fraction: meter.fraction)
                            Text(meter.amount)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(step.title), \(Self.spoken(step.state))")
            .accessibilityValue(step.meter.map { "\($0.amount). \(step.detail)" } ?? step.detail)
        }

        static func spoken(_ state: StepState) -> String {
            switch state {
            case .waiting: return "waiting"
            case .working: return "in progress"
            case .done: return "done"
            case .yourTurn: return "your turn"
            case .failed: return "didn't finish"
            }
        }
    }

    private struct StepIcon: View {
        let state: StepState

        var body: some View {
            Group {
                switch state {
                case .waiting: Image(systemName: "circle").foregroundStyle(.tertiary)
                case .working: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .yourTurn: Image(systemName: "arrow.right.circle.fill").foregroundStyle(.primary)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .font(.system(size: 16))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
        }
    }
}

/// The voice's tile, drawn like the tools' tiles: tinted once the voice is ready.
private struct VoiceTile: View {
    let ready: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ready ? ControlMetrics.primaryText(scheme) : .white)
            .frame(width: 28, height: 28)
            .background(ready ? ControlMetrics.primaryFill(scheme) : Color.gray.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .accessibilityHidden(true)
    }
}
