import XCTest
@testable import ReadbackCore

final class JSONValueTests: XCTestCase {
    func testRoundTripKeepsKeyOrderNumbersAndEscapes() throws {
        let text = """
        {
          "zeta": 1,
          "alpha": {
            "b": [
              true,
              null,
              -1.50e3
            ],
            "a": "quote \\" slash \\\\ tab \\t newline \\n unicode é 🎧 \\u0001"
          },
          "empty": {},
          "list": []
        }

        """
        let value = try JSONValue.parse(text)
        XCTAssertEqual(value.formatted(), text)
    }

    /// Read-only check against real files: READBACK_ROUNDTRIP_FILES="a.json:b.json" swift test.
    /// Each must come back byte for byte, or Readback would reformat someone's settings.
    func testRealFilesRoundTripByteForByte() throws {
        guard let list = ProcessInfo.processInfo.environment["READBACK_ROUNDTRIP_FILES"] else {
            throw XCTSkip("set READBACK_ROUNDTRIP_FILES to check real files")
        }
        for path in list.split(separator: ":").map(String.init) {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertEqual(try JSONValue.parse(text).formatted(), text, path)
        }
    }

    func testParsesCompactJSONAndSurrogatePairs() throws {
        let value = try JSONValue.parse(#"{"a":"\ud83c\udfa7","b":[1,2]}"#)
        XCTAssertEqual(value["a"], .string("🎧"))
        XCTAssertEqual(value["b"], .array([.number("1"), .number("2")]))
    }

    func testRejectsBrokenJSON() {
        XCTAssertThrowsError(try JSONValue.parse(#"{"a": }"#))
        XCTAssertThrowsError(try JSONValue.parse(#"{"a": 1} trailing"#))
        XCTAssertThrowsError(try JSONValue.parse(#"{"a": "unterminated}"#))
    }

    func testSetKeepsPositionAndAppendsNewKeys() throws {
        var value = try JSONValue.parse(#"{"a":1,"b":2}"#)
        value.set("a", .number("9"))
        value.set("c", .number("3"))
        XCTAssertEqual(value.formatted(), "{\n  \"a\": 9,\n  \"b\": 2,\n  \"c\": 3\n}\n")
    }
}

final class IntegrationTests: XCTestCase {
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"
    let pluginDir = "/Users/me/Library/Application Support/Readback/ClaudeCodePlugin"

    let claudeSettings = """
    {
      "model": "opus",
      "env": {
        "CLAUDE_CODE_PLUGIN_DIRS": "/Users/me/my-plugin",
        "FOO": "bar"
      },
      "hooks": {
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "echo done",
                "timeout": 5
              }
            ]
          }
        ]
      },
      "theme": "dark"
    }

    """

    func testConnectClaudeAddsHooksAndPluginDirAndKeepsTheRest() throws {
        var root = try JSONValue.parse(claudeSettings)
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)

        let ours = Integrations.ourCommands(root)
        XCTAssertEqual(ours["Stop"], ["'\(cli)' hook claude"])
        XCTAssertEqual(ours["UserPromptSubmit"], ["'\(cli)' stop"])
        XCTAssertEqual(root["hooks"]?["Stop"]?.arrayValue?.count, 2, "the user's own Stop hook stays")
        XCTAssertEqual(root["env"]?["CLAUDE_CODE_PLUGIN_DIRS"], .string("/Users/me/my-plugin:\(pluginDir)"))
        XCTAssertEqual(root["model"], .string("opus"))
        XCTAssertEqual(Integrations.hookStatus(root, cli: cli), .connected)
    }

    func testConnectingTwiceDoesNotDuplicate() throws {
        var root = try JSONValue.parse(claudeSettings)
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)
        XCTAssertEqual(Integrations.ourCommands(root)["Stop"]?.count, 1)
        XCTAssertEqual(root["env"]?["CLAUDE_CODE_PLUGIN_DIRS"], .string("/Users/me/my-plugin:\(pluginDir)"))
    }

    func testDisconnectClaudeRestoresTheFileExactly() throws {
        var root = try JSONValue.parse(claudeSettings)
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)
        Integrations.disconnectClaude(&root)
        XCTAssertEqual(root.formatted(), claudeSettings)
    }

    func testDisconnectRemovesWhatItCreated() throws {
        var root = try JSONValue.parse("{\n  \"model\": \"opus\"\n}\n")
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)
        Integrations.disconnectClaude(&root)
        XCTAssertEqual(root.formatted(), "{\n  \"model\": \"opus\"\n}\n")
    }

    func testAppMovedShowsAsStaleAndReconnectReplacesIt() throws {
        var root = try JSONValue.parse("{}")
        Integrations.connectClaude(&root, cli: "/Users/me/Downloads/Readback.app/Contents/Helpers/readback", pluginDir: pluginDir)
        guard case .stale = Integrations.hookStatus(root, cli: cli) else { return XCTFail("expected stale") }
        Integrations.connectClaude(&root, cli: cli, pluginDir: pluginDir)
        XCTAssertEqual(Integrations.hookStatus(root, cli: cli), .connected)
        XCTAssertEqual(Integrations.ourCommands(root).values.flatMap { $0 }.count, 2)
    }

    func testCodexKeepsItsOtherLayoutAndHooks() throws {
        let codex = """
        {
          "SessionStart": [],
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "impeccable hook"
                  }
                ]
              }
            ]
          }
        }

        """
        // What older Readback versions wrote into hooks.json; connecting now removes it.
        var root = try JSONValue.parse(codex)
        Integrations.addHook(&root, event: "Stop", command: Integrations.command(cli: cli, "hook codex"), timeout: 10)
        Integrations.addHook(&root, event: "UserPromptSubmit", command: Integrations.command(cli: cli, "stop"), timeout: 5)
        XCTAssertEqual(Integrations.ourCommands(root)["Stop"], ["'\(cli)' hook codex"])
        XCTAssertEqual(root["hooks"]?["Stop"]?.arrayValue?.count, 2)
        Integrations.removeOurHooks(&root)
        XCTAssertEqual(root.formatted(), codex)
    }

    func testOtherHooksMentioningReadbackAreLeftAlone() {
        XCTAssertFalse(Integrations.isOurs("bash ~/.claude/hooks/speak-reply.sh"))
        XCTAssertFalse(Integrations.isOurs("echo readback"))
        XCTAssertTrue(Integrations.isOurs("'/Applications/Readback.app/Contents/Helpers/readback' stop"))
    }

    func testQuotesPathsWithSpacesAndQuotes() {
        XCTAssertEqual(Integrations.command(cli: "/Users/me/My Apps/Readback.app/Contents/Helpers/readback", "stop"),
                       "'/Users/me/My Apps/Readback.app/Contents/Helpers/readback' stop")
        XCTAssertEqual(Integrations.command(cli: "/x/it's/Readback.app/Contents/Helpers/readback", "stop"),
                       "'/x/it'\\''s/Readback.app/Contents/Helpers/readback' stop")
    }

    func testOpenCodePluginNamesItsCLI() {
        let source = Integrations.openCodePlugin(cli: cli)
        XCTAssertEqual(Integrations.openCodeCLI(in: source), cli)
        XCTAssertNil(Integrations.openCodeCLI(in: "export const Other = 1"))
        XCTAssertTrue(source.contains(#".join("\n\n")"#), "the JS keeps its escaped newlines")
    }

    func testToolFromSource() {
        XCTAssertEqual(Tool(source: "Claude Code"), .claude)
        XCTAssertEqual(Tool(source: "OpenCode"), .opencode)
        XCTAssertNil(Tool(source: "Readback"))
    }
}

final class VoiceCatalogTests: XCTestCase {
    func testKokoroVoicesCarryLanguageAndGender() {
        XCTAssertEqual(VoiceCatalog.kokoroVoice("bm_george"), VoiceOption(id: "bm_george", name: "George (male)", group: "English (UK)", lang: "b"))
        XCTAssertNil(VoiceCatalog.kokoroVoice("jf_alpha"), "Japanese makes empty audio, so it's not offered")
        XCTAssertEqual(VoiceCatalog.lang(for: "ef_dora", engine: .kokoro), "e")
        XCTAssertEqual(VoiceCatalog.lang(for: "ryan", engine: .qwen3), "auto")
        // 28 English (11 + 9 US, 4 + 4 UK), 3 Spanish, 1 French, 4 Hindi, 2 Italian, 3 Portuguese.
        XCTAssertEqual(VoiceCatalog.kokoroVoices.count, 41)
    }
}
