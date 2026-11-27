import AppKit
import ReadbackCore
import ServiceManagement
import SwiftUI

struct ReadingSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var reader: Reader
    let resetPosition: () -> Void
    /// Reading back on, or off for one of the three lengths (AppDelegate: stops what's reading,
    /// swaps the menu bar icon).
    let turnReadingOn: () -> Void
    let turnReadingOff: (ReadingOff.Length) -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            // The overall switch, the same one as the menu bar's and the sidebar's (owner's mockup,
            // 2026-11-26), as the same action with the same three lengths (owner, 2026-11-27:
            // before that it was a switch here, off until switched back on, and only the menu bar
            // had the times).
            Section {
                LabeledContent {
                    if prefs.readingOffUntil == nil {
                        MenuButton(title: "Turn reading off",
                                   items: { ReadingOff.Length.allCases.map { $0.menuTitle(now: Date()) } },
                                   choose: { turnReadingOff(ReadingOff.Length.allCases[$0]) })
                    } else {
                        Button("Turn on", action: turnReadingOn)
                            .buttonStyle(.readback(.primary))
                            .controlSize(.small)
                    }
                } label: {
                    Text("Read replies out loud")
                    if let until = prefs.readingOffUntil {
                        Text(ReadingOff.status(until: until, now: Date()).replacingOccurrences(of: "Reading is off", with: "Off"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                FormNote("Off stops everything that reads by itself, for every tool and thread, for as long as you pick: an hour, until 8\u{00A0}AM, or until you turn it back on. Replies still go to History, and asking for one still plays it. The sidebar and the menu bar icon can turn it off too.")
            }

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
                FormNote("Connecting a tool switches this on, unless you'd set it before. /readback:speak off mutes one session, /readback:speak on reads one, and /readback:read reads the last reply. Muted sessions show on Home.")
            }
            // Kept as they are while reading is off, and dimmed: turning reading on restores them.
            .disabled(prefs.readingOffUntil != nil)
            .opacity(prefs.readingOffUntil == nil ? 1 : 0.5)

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
        .keepsReadingSwitchesFresh(prefs)
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

extension View {
    /// While this view shows, picks up a "read every reply" switch that another process changed:
    /// `readback connect` writes it straight to the saved settings (review 2026-11-26). Such a
    /// write showed up in the app's UserDefaults within a quarter second when tried on 2026-11-26.
    func keepsReadingSwitchesFresh(_ prefs: Preferences) -> some View {
        task {
            while !Task.isCancelled {
                prefs.reloadReadingSwitches()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
