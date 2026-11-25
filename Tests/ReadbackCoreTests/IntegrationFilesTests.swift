import XCTest
@testable import ReadbackCore

/// Connect and disconnect against a fake home folder, checking the files byte for byte.
final class IntegrationFilesTests: XCTestCase {
    var home: URL!
    var files: IntegrationFiles!
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-test-\(UUID().uuidString)", isDirectory: true)
        let plugin = home.appendingPathComponent("bundle/ClaudeCodePlugin/.claude-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try #"{"name":"readback"}"#.write(to: plugin.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli,
                                 bundledPlugin: home.appendingPathComponent("bundle/ClaudeCodePlugin", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Every file these tests can touch must be inside the fake home, whatever the shell sets
    /// (CODEX_HOME once sent a test to the real Codex config).
    func testEveryPathStaysInsideTheFakeHome() {
        let p = files.paths
        for url in [p.claudeSettings, p.codexHooks, p.openCodePlugin, p.support, p.claudePlugin, p.runtime, p.logs] {
            XCTAssertTrue(url.path.hasPrefix(home.path), "\(url.path) escapes the test home")
        }
    }

    private func write(_ text: String, _ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)
    }

    func testClaudeRoundTripLeavesTheFileAsItWasAndKeepsABackup() throws {
        let original = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "say done"
                  }
                ]
              }
            ]
          }
        }

        """
        try write(original, ".claude/settings.json")
        XCTAssertEqual(try files.status(.claude), .notConnected)

        try files.connect(.claude)
        XCTAssertEqual(try files.status(.claude), .connected)
        XCTAssertEqual(try read(".claude/settings.json.before-readback"), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/Readback/ClaudeCodePlugin/.claude-plugin/plugin.json").path))
        XCTAssertTrue(try read(".claude/settings.json").contains("Library/Application Support/Readback/ClaudeCodePlugin"))

        try files.disconnect(.claude)
        XCTAssertEqual(try files.status(.claude), .notConnected)
        XCTAssertEqual(try read(".claude/settings.json"), original)
    }

    /// The one thing a round trip doesn't keep: an event list that was already empty can't be told
    /// apart from one Readback emptied, so it's tidied away. An empty hook list does nothing.
    func testAnAlreadyEmptyEventListIsTidiedAway() throws {
        try write("{\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n", ".claude/settings.json")
        try files.connect(.claude)
        try files.disconnect(.claude)
        XCTAssertEqual(try read(".claude/settings.json"), "{}\n")
    }

    func testClaudeWithNoSettingsFileYet() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try files.connect(.claude)
        XCTAssertEqual(try files.status(.claude), .connected)
        try files.disconnect(.claude)
        XCTAssertEqual(try read(".claude/settings.json"), "{}\n")
    }

    func testToolNotInstalledIsRefused() {
        XCTAssertThrowsError(try files.connect(.codex)) { error in
            XCTAssertTrue("\(error)".contains("Codex doesn't seem to be installed"))
        }
    }

    func testBrokenJSONIsRefusedAndLeftAlone() throws {
        try write("{ not json", ".codex/hooks.json")
        XCTAssertThrowsError(try files.connect(.codex))
        XCTAssertEqual(try read(".codex/hooks.json"), "{ not json")
    }

    func testOpenCodeWritesAndRemovesOnlyItsOwnFile() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)
        try files.connect(.opencode)
        XCTAssertEqual(try files.status(.opencode), .connected)
        try files.disconnect(.opencode)
        XCTAssertEqual(try files.status(.opencode), .notConnected)

        try write("export const Mine = 1\n", ".config/opencode/plugins/readback.js")
        try files.disconnect(.opencode)
        XCTAssertEqual(try read(".config/opencode/plugins/readback.js"), "export const Mine = 1\n", "someone else's file stays")
    }

    /// Every open Claude Code session reloads the mod when its files change, so an unchanged mod
    /// must not be copied again at each launch.
    func testTheModIsOnlyCopiedWhenTheAppsCopyChanged() throws {
        let installed = files.paths.claudePlugin.appendingPathComponent(".claude-plugin/plugin.json")
        try files.copyPlugin()
        try write("// Claude Code's own types\n", "Library/Application Support/Readback/ClaudeCodePlugin/types/extra.d.ts")
        let first = try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.05)
        try files.copyPlugin()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date, first)

        try write(#"{"name":"readback","version":"2"}"#, "bundle/ClaudeCodePlugin/.claude-plugin/plugin.json")
        try files.copyPlugin()
        XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), #"{"name":"readback","version":"2"}"#)
    }
}
