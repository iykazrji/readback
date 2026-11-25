import AppKit
import ReadbackCore
import ServiceManagement
import SwiftUI

struct ReadingSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var reader: Reader
    let resetPosition: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                ForEach(Tool.allCases) { tool in
                    Toggle(tool.name, isOn: Binding(
                        get: { prefs.autoRead[tool] ?? false },
                        set: { prefs.setAutoRead(tool, $0) }
                    ))
                    .accessibilityLabel("Read every \(tool.name) reply out loud")
                }
            } header: {
                Text("Read every reply out loud")
            } footer: {
                FormNote("Off by default. In Claude Code you can switch it on for one session with /speak on, and /read reads the last reply. With it off, Read last reply in the menu bar still works.")
            }

            Section {
                LabeledContent("Sound before reading") {
                    Picker("Sound before reading", selection: $prefs.cueSound) {
                        Text("None").tag("")
                        ForEach(Self.cueSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .accessibilityLabel("Sound before reading")
                .onChange(of: prefs.cueSound) { _, name in
                    // Hear it as you pick it.
                    if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }
                }
            } footer: {
                FormNote("Plays when a reply starts reading by itself, and the voice follows a second later. Not when you press play or type /read.")
            }

            Section {
                LabeledContent("When another reply arrives mid-reading") {
                    Picker("When another reply arrives mid-reading", selection: $prefs.switchToNewReplies) {
                        Text("Play it next").tag(false)
                        Text("Switch to it").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .accessibilityLabel("When another reply arrives mid-reading")
            } header: {
                Text("Several agents at once")
            } footer: {
                FormNote("Replies that wait show as +1, +2 in the player. Click the title in the player, or open History, to jump to any of them.")
            }

            Section("Player") {
                LabeledContent("Speed") {
                    Picker("Speed", selection: Binding(get: { reader.speed }, set: { reader.setSpeed($0) })) {
                        ForEach(Reader.speeds.sorted(), id: \.self) { speed in
                            Text(speed == 1 ? "Normal" : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×").tag(speed)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .accessibilityLabel("Speed")
                LabeledContent("When a reply ends") {
                    Picker("When a reply ends", selection: $prefs.hideAfter) {
                        Text("Hide after 4 seconds").tag(4.0)
                        Text("Hide after 10 seconds").tag(10.0)
                        Text("Hide after 30 seconds").tag(30.0)
                        Text("Keep it open").tag(0.0)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .accessibilityLabel("When a reply ends")
                Toggle(isOn: $prefs.escCloses) {
                    Text("Esc closes the player")
                    Text("While the player is showing, Esc goes to Readback, not the app you're in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Esc closes the player")
                LabeledContent("Position") {
                    Button("Move back to the bottom", action: resetPosition)
                }
            }

            Section("Startup") {
                Toggle("Open Readback when you log in", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .accessibilityLabel("Open Readback when you log in")
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(CardFormStyle())
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    /// macOS's own sounds that work as a short heads-up; Pop is the default, like a toaster.
    static let cueSounds = ["Pop", "Tink", "Glass", "Ping", "Bottle", "Purr"]

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            Log.error("couldn't \(on ? "turn on" : "turn off") open at login: \(error)")
            loginError = "macOS didn't allow it: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginError = "macOS needs your OK: System Settings → General → Login Items."
        }
    }
}
