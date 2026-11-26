import Foundation
import Testing
@testable import ReadbackCore

/// A new connection reads every reply out loud, unless the person already set that switch.
@Suite struct NewConnectionReadingTests {
    private func withSwitches(_ body: (ReadingSwitches) -> Void) {
        let suite = "readback-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(ReadingSwitches(defaults: defaults))
    }

    @Test func aNewConnectionSwitchesItOn() {
        withSwitches { switches in
            #expect(switches.switchesOnWhenConnecting(.claude, from: .notConnected))
        }
    }

    @Test func anEarlierOffWins() {
        withSwitches { switches in
            switches.setReadsEveryReply(.claude, false)
            #expect(!switches.switchesOnWhenConnecting(.claude, from: .notConnected))
        }
    }

    @Test func onlyTheToolThatWasSetKeepsItsChoice() {
        withSwitches { switches in
            switches.setReadsEveryReply(.codex, false)
            #expect(switches.switchesOnWhenConnecting(.opencode, from: .notConnected))
        }
    }

    @Test(arguments: [Integrations.Status.connected, .stale("/Applications/Old.app"), .incomplete,
                      .waitingForApproval, .outdated, .updateAvailable])
    func reconnectingSomethingAlreadyThereIsntNew(_ before: Integrations.Status) {
        withSwitches { switches in
            #expect(!switches.switchesOnWhenConnecting(.codex, from: before))
        }
    }

    @Test func itSaysWhetherTheSwitchWasEverSet() {
        withSwitches { switches in
            #expect(!switches.hasSetEveryReply(.claude))
            switches.setReadsEveryReply(.claude, true)
            #expect(switches.hasSetEveryReply(.claude))
        }
    }
}
