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
                        get: { prefs.readsEveryReply(tool) },
                        set: { prefs.setReadsEveryReply(tool, $0) }
                    ))
                    .accessibilityLabel("Read every \(tool.name) reply out loud")
                }
            } header: {
                Text("Read every reply out loud")
            } footer: {
                FormNote("On for a tool once you connect it, unless you'd switched it off before. With it off, /readback:speak on reads one session, /readback:read reads the last reply, and Read last reply in the menu bar still works.")
            }

            Section {
                LabeledContent("Sound before reading") {
                    Dropdown("Sound before reading", selection: $prefs.cueSound,
                             options: [("None", "")] + Self.cueSounds.map { ($0, $0) })
                    .fixedSize()
                }
                .onChange(of: prefs.cueSound) { _, name in
                    // Hear it as you pick it.
                    if !name.isEmpty { NSSound(named: NSSound.Name(name))?.play() }
                }
            } footer: {
                FormNote("Plays when a reply starts reading by itself, and the voice follows a second later. Not when you press play or ask for the last reply.")
            }

            Section {
                Toggle("Lower other sounds while reading", isOn: $prefs.lowerOtherAudio)
                    .accessibilityLabel("Lower other sounds while reading")
            } footer: {
                FormNote("Music, videos and other apps drop to about a third of their volume while a reply plays. macOS asks for System Audio Recording permission when you switch this on: it's how Readback turns other apps down. Nothing is recorded or kept. To change it later: System Settings → Privacy & Security → Screen & System Audio Recording.")
            }

            Section {
                LabeledContent("When another reply arrives mid-reading") {
                    Dropdown("When another reply arrives mid-reading", selection: $prefs.switchToNewReplies,
                             options: [("Play it next", false), ("Switch to it", true)])
                    .fixedSize()
                }
            } header: {
                Text("Several agents at once")
            } footer: {
                FormNote("Replies that wait show as +1, +2 in the player. Click the title in the player, or open History, to jump to any of them.")
            }

            Section("Player") {
                LabeledContent("Speed") {
                    Dropdown("Speed", selection: Binding(get: { reader.speed }, set: { reader.setSpeed($0) }),
                             options: Reader.speeds.sorted().map { speed in
                                 (speed == 1 ? "Normal" : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×", speed)
                             })
                    .fixedSize()
                }
                LabeledContent("When a reply ends") {
                    Dropdown("When a reply ends", selection: $prefs.hideAfter,
                             options: [("Hide after 4 seconds", 4.0), ("Hide after 10 seconds", 10.0),
                                       ("Hide after 30 seconds", 30.0), ("Keep it open", 0.0)])
                    .fixedSize()
                }
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
