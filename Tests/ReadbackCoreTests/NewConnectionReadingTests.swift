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
            #expect(switches.applyNewConnection(of: .claude, isNew: true))
            #expect(switches.readsEveryReply(.claude))
        }
    }

    @Test func aConnectionThatIsntNewLeavesItAlone() {
        withSwitches { switches in
            #expect(!switches.applyNewConnection(of: .claude, isNew: false))
            #expect(!switches.hasSetEveryReply(.claude))
        }
    }

    @Test func anEarlierOffWins() {
        withSwitches { switches in
            switches.setReadsEveryReply(.claude, false)
            #expect(!switches.applyNewConnection(of: .claude, isNew: true))
            #expect(!switches.readsEveryReply(.claude))
        }
    }

    @Test func onlyTheToolThatWasSetKeepsItsChoice() {
        withSwitches { switches in
            switches.setReadsEveryReply(.codex, false)
            #expect(switches.switchesOn(forNewConnectionOf: .opencode, isNew: true))
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

/// IntegrationFiles.connect says whether a connection was new, read before it changes anything.
@Suite struct ConnectSaysIfNewTests {
    private func withHome(_ body: (IntegrationFiles) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-new-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(IntegrationFiles(paths: ReadbackPaths(home: home), cli: "/Applications/Readback.app/Contents/Helpers/readback", bundledPlugin: nil))
    }

    @Test func aFirstConnectIsNewAndASecondIsnt() throws {
        try withHome { files in
            let first = try files.connect(.claude)
            let second = try files.connect(.claude)
            #expect(first)
            #expect(!second)
        }
    }

    @Test func reconnectingAfterADisconnectIsNewAgain() throws {
        try withHome { files in
            try files.connect(.opencode)
            try files.disconnect(.opencode)
            let again = try files.connect(.opencode)
            #expect(again)
        }
    }

    @Test func aStatusThatCantBeReadIsntNew() throws {
        try withHome { files in
            // Settings that aren't JSON: status can't be read. Connect refuses to write over them,
            // and nothing may switch reading on.
            try "not json".write(to: files.paths.claudeSettings, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try files.connect(.claude) }
        }
    }
}
