import XCTest
@testable import ReadbackCore

final class CodexPromptTests: XCTestCase {
    func testSpeakAndReadInEveryFormCodexSends() {
        XCTAssertEqual(PromptCommand(prompt: "/speak on"), .speak(true))
        XCTAssertEqual(PromptCommand(prompt: "  /speak   OFF \n"), .speak(false))
        XCTAssertEqual(PromptCommand(prompt: "/speak"), .speak(nil))
        XCTAssertEqual(PromptCommand(prompt: "$speak on"), .speak(true))
        XCTAssertEqual(PromptCommand(prompt: "$readback:speak off"), .speak(false))
        XCTAssertEqual(PromptCommand(prompt: "[$speak](/Users/me/.codex/plugins/cache/readback/readback/1.0.0/skills/speak/SKILL.md) on"), .speak(true))
        XCTAssertEqual(PromptCommand(prompt: "/read"), .read)
        XCTAssertEqual(PromptCommand(prompt: "$read"), .read)
    }

    func testOrdinaryPromptsGoToTheModel() {
        XCTAssertNil(PromptCommand(prompt: "speak on"))           // no / or $: could be a sentence
        XCTAssertNil(PromptCommand(prompt: "/read the docs and fix it"))
        XCTAssertNil(PromptCommand(prompt: "/speak about the design"))
        XCTAssertNil(PromptCommand(prompt: "/speaker on"))
        XCTAssertNil(PromptCommand(prompt: "please /speak on"))
        XCTAssertNil(PromptCommand(prompt: "[a link](https://example.com) on"))
        XCTAssertNil(PromptCommand(prompt: ""))
    }

    func testBackgroundJobsHaveNoSavedChat() {
        XCTAssertTrue(CodexHookPayload.isBackgroundJob(transcriptPath: nil))
        XCTAssertTrue(CodexHookPayload.isBackgroundJob(transcriptPath: ""))
        XCTAssertTrue(CodexHookPayload.isBackgroundJob(transcriptPath: "/gone.jsonl", fileExists: { _ in false }))
        XCTAssertFalse(CodexHookPayload.isBackgroundJob(transcriptPath: "/chat.jsonl", fileExists: { _ in true }))
    }
}

final class CodexConfigTests: XCTestCase {
    let approvedBoth = """
    [hooks.state."/Users/me/.codex/hooks.json:stop:0:0"]
    trusted_hash = "sha256:aaa"

    [hooks.state."readback@readback:hooks/hooks.json:user_prompt_submit:0:0"]
    trusted_hash = "sha256:bbb"
    trusted_content_hash = "sha256:ccc"

    [hooks.state."readback@readback:hooks/hooks.json:stop:0:0"]
    trusted_hash = "sha256:ddd"
    trusted_content_hash = "sha256:ccc"

    [plugins."readback@readback"]
    enabled = true
    """

    func testReadsWhichReadbackHooksArApproved() {
        XCTAssertEqual(CodexPlugin.approvedEvents(configToml: approvedBoth), ["stop", "user_prompt_submit"])
        XCTAssertEqual(CodexPlugin.approvedEvents(configToml: ""), [])
        // Someone else's plugin with the same hook layout doesn't count.
        XCTAssertEqual(CodexPlugin.approvedEvents(configToml: """
        [hooks.state."readback-proto@readback-proto:hooks/hooks.json:stop:0:0"]
        trusted_hash = "sha256:x"
        """), [])
    }

    func testASwitchedOffOrUnhashedHookIsNotApproved() {
        let config = """
        [hooks.state."readback@readback:hooks/hooks.json:stop:0:0"]
        enabled = false
        trusted_hash = "sha256:ddd"
        [hooks.state."readback@readback:hooks/hooks.json:user_prompt_submit:0:0"]
        enabled = true
        """
        XCTAssertEqual(CodexPlugin.approvedEvents(configToml: config), [])
    }

    func testPluginEnabledState() {
        XCTAssertTrue(CodexPlugin.isEnabled(configToml: approvedBoth))
        XCTAssertFalse(CodexPlugin.isEnabled(configToml: "[plugins.\"readback@readback\"]\nenabled = false\n"))
        XCTAssertFalse(CodexPlugin.isEnabled(configToml: "[plugins.\"github@openai-curated\"]\nenabled = true\n"))
    }

    func testPluginFilesAreValidAndRunThisCLI() throws {
        let cli = "/Users/me/My Apps/Readback.app/Contents/Helpers/readback"
        let files = Dictionary(uniqueKeysWithValues: CodexPlugin.files(cli: cli).map { ($0.path, $0.contents) })
        for (path, text) in files where path.hasSuffix(".json") {
            XCTAssertNoThrow(try JSONValue.parse(text), path)
        }
        let hooks = try JSONValue.parse(try XCTUnwrap(files["plugins/readback/hooks/hooks.json"]))
        XCTAssertEqual(Integrations.ourCommands(hooks)["Stop"], ["'\(cli)' hook codex"])
        XCTAssertEqual(Integrations.ourCommands(hooks)["UserPromptSubmit"], ["'\(cli)' prompt codex"])
        XCTAssertEqual(Integrations.hookStatus(hooks, cli: cli), .connected)
        // The skills are menu entries only: Codex must never pick them by itself.
        for skill in ["speak", "read"] {
            XCTAssertTrue(try XCTUnwrap(files["plugins/readback/skills/\(skill)/agents/openai.yaml"]).contains("allow_implicit_invocation: false"))
            XCTAssertTrue(try XCTUnwrap(files["plugins/readback/skills/\(skill)/SKILL.md"]).hasPrefix("---\nname: \(skill)\n"))
        }
        // Same CLI, same bytes: Codex's approval is kept against these files.
        XCTAssertEqual(CodexPlugin.files(cli: cli).map(\.contents), CodexPlugin.files(cli: cli).map(\.contents))
    }

    func testCodexVersionsOldAndNew() {
        XCTAssertEqual(CodexCLI.minimumVersion, "0.131.0")
        for ok in ["codex-cli 0.131.0", "0.171.0", "codex-cli 0.171.0-alpha.13.2", "0.131.1", "1.0.0", "0.131"] {
            XCTAssertTrue(CodexCLI.isNewEnough(ok), ok)
        }
        for old in ["codex-cli 0.130.9", "0.99.0", "0.13.0", "codex-cli 0.130.0-alpha.1", "", "codex-cli"] {
            XCTAssertFalse(CodexCLI.isNewEnough(old), old)
        }
        XCTAssertTrue("\(CodexCLI.TooOld(version: "0.120.0", path: "/opt/homebrew/bin/codex"))".contains("0.131.0 or newer"))
    }

    func testFindsCodexInTheShellsPathNotItsAlias() {
        let output = "Welcome back!\ncodex\n\nREADBACK_PATH=/usr/bin:/Users/me/Library/pnpm:/opt/homebrew/bin\n"
        XCTAssertEqual(CodexCLI.inPath(output, isExecutable: { $0.hasPrefix("/Users/me/Library/pnpm/") || $0.hasPrefix("/opt/") })?.path,
                       "/Users/me/Library/pnpm/codex")
        XCTAssertNil(CodexCLI.inPath(output, isExecutable: { _ in false }))
        XCTAssertNil(CodexCLI.inPath("codex\n", isExecutable: { _ in true }))
    }

    func testFindsTheCodexAppCopyFirst() {
        let home = URL(fileURLWithPath: "/Users/me")
        let app = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        XCTAssertEqual(CodexCLI.find(home: home, isExecutable: { $0 == app || $0 == "/opt/homebrew/bin/codex" })?.path, app)
        XCTAssertEqual(CodexCLI.find(home: home, isExecutable: { $0 == "/opt/homebrew/bin/codex" })?.path, "/opt/homebrew/bin/codex")
        XCTAssertNil(CodexCLI.find(home: home, isExecutable: { _ in false }))
    }
}

/// Connect, check and disconnect Codex against a fake home, with a fake `codex` that does what
/// the real one does to config.toml and the plugin cache.
final class CodexIntegrationTests: XCTestCase {
    var home: URL!
    var calls: [(args: [String], codexHome: String)] = []
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        calls = []
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func files(codex: CodexRun? = nil) -> IntegrationFiles {
        IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: codex ?? fakeCodex)
    }

    /// Mimics `codex plugin …`: add copies the plugin into the cache and enables it in config.toml.
    private func fakeCodex(_ args: [String], _ codexHome: URL) throws {
        calls.append((args, codexHome.path))
        let fm = FileManager.default
        let config = codexHome.appendingPathComponent("config.toml")
        var text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        let cache = codexHome.appendingPathComponent("plugins/cache/readback/readback/\(CodexPlugin.version)")
        switch Array(args.prefix(2)) {
        case ["plugin", "add"]:
            let source = ReadbackPaths(home: home).codexPluginSource.appendingPathComponent("plugins/readback")
            try? fm.removeItem(at: cache)
            try fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: cache)
            if !text.contains("[plugins.\"readback@readback\"]") { text += "\n[plugins.\"readback@readback\"]\nenabled = true\n" }
        case ["plugin", "remove"]:
            try fm.removeItem(at: cache)
            text = text.replacingOccurrences(of: "\n[plugins.\"readback@readback\"]\nenabled = true\n", with: "")
        default: break
        }
        try text.write(to: config, atomically: true, encoding: .utf8)
    }

    private func approve(_ codexHome: URL) throws {
        let config = codexHome.appendingPathComponent("config.toml")
        let text = try String(contentsOf: config, encoding: .utf8) + """

        [hooks.state."readback@readback:hooks/hooks.json:stop:0:0"]
        trusted_hash = "sha256:1"
        [hooks.state."readback@readback:hooks/hooks.json:user_prompt_submit:0:0"]
        trusted_hash = "sha256:2"

        """
        try text.write(to: config, atomically: true, encoding: .utf8)
    }

    func testConnectInstallsThePluginThroughCodexAndWaitsForApproval() throws {
        let files = files()
        let codexHome = files.paths.codexDir
        XCTAssertEqual(try files.status(.codex), .notConnected)

        try files.connect(.codex)
        XCTAssertEqual(calls.map(\.args), [
            ["plugin", "marketplace", "add", files.paths.codexPluginSource.path],
            ["plugin", "add", "readback@readback"],
        ])
        XCTAssertTrue(calls.allSatisfy { $0.codexHome == codexHome.path })
        XCTAssertEqual(try files.status(.codex), .connected)
        XCTAssertFalse(files.codexHooksApproved(home: codexHome))

        try approve(codexHome)
        XCTAssertTrue(files.codexHooksApproved(home: codexHome))

        try files.disconnect(.codex)
        XCTAssertEqual(calls.suffix(2).map(\.args), [["plugin", "remove", "readback@readback"], ["plugin", "marketplace", "remove", "readback"]])
        XCTAssertEqual(try files.status(.codex), .notConnected)
    }

    func testConnectingAgainLeavesThePluginFilesUntouched() throws {
        let files = files()
        try files.connect(.codex)
        let hooks = files.paths.codexPluginSource.appendingPathComponent("plugins/readback/hooks/hooks.json")
        let before = try FileManager.default.attributesOfItem(atPath: hooks.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 0.05)
        try files.connect(.codex)
        let after = try FileManager.default.attributesOfItem(atPath: hooks.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after)
        XCTAssertEqual(try files.status(.codex), .connected)
    }

    func testOldHooksShowAsOutdatedAndConnectSwapsThemForThePlugin() throws {
        let files = files()
        let hooksFile = files.paths.codexHooks
        let original = """
        {
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
        var root = try JSONValue.parse(original)
        Integrations.addHook(&root, event: "Stop", command: Integrations.command(cli: cli, "hook codex"), timeout: 10)
        Integrations.addHook(&root, event: "UserPromptSubmit", command: Integrations.command(cli: cli, "stop"), timeout: 5)
        try root.formatted().write(to: hooksFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try files.status(.codex), .outdated)

        try files.connect(.codex)
        XCTAssertEqual(try String(contentsOf: hooksFile, encoding: .utf8), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hooksFile.appendingPathExtension("before-readback").path))
        XCTAssertEqual(try files.status(.codex), .connected)
    }

    func testAPluginRunningAnotherCopyOfReadbackIsStale() throws {
        try files().connect(.codex)
        let moved = IntegrationFiles(paths: ReadbackPaths(home: home), cli: "/Users/me/Downloads/Readback.app/Contents/Helpers/readback",
                                     bundledPlugin: nil, codex: fakeCodex)
        guard case .stale = try moved.codexStatus(home: moved.paths.codexDir) else { return XCTFail("expected stale") }
    }

    func testOrcaIsConnectedSeparatelyAndStaysInsideTheFakeHome() throws {
        let files = files()
        let orca = files.paths.orcaCodexDir
        XCTAssertTrue(orca.path.hasPrefix(home.path))
        XCTAssertTrue(files.paths.codexPluginSource.path.hasPrefix(home.path))
        XCTAssertThrowsError(try files.connectCodex(home: orca))   // Orca isn't installed yet
        try FileManager.default.createDirectory(at: orca, withIntermediateDirectories: true)

        try files.connectCodex(home: orca)
        XCTAssertTrue(calls.allSatisfy { $0.codexHome == orca.path })
        XCTAssertEqual(try files.codexStatus(home: orca), .connected)
        XCTAssertEqual(try files.status(.codex), .notConnected)    // ~/.codex is untouched
    }

    /// Orca's Codex home links plugins/ to ~/.codex/plugins, so both homes run one installed copy.
    func testDisconnectingOneHomeKeepsThePluginTheOtherSharesWorking() throws {
        let files = files()
        let fm = FileManager.default
        let orca = files.paths.orcaCodexDir
        try fm.createDirectory(at: orca, withIntermediateDirectories: true)
        try fm.createDirectory(at: files.paths.codexDir.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: orca.appendingPathComponent("plugins"), withDestinationURL: files.paths.codexDir.appendingPathComponent("plugins"))

        try files.connect(.codex)
        try files.connectCodex(home: orca)
        XCTAssertEqual(try files.codexStatus(home: orca), .connected)

        try files.disconnectCodex(home: orca)
        XCTAssertEqual(try files.codexStatus(home: orca), .notConnected)
        XCTAssertEqual(try files.status(.codex), .connected)
        XCTAssertEqual(calls.last?.args, ["plugin", "add", "readback@readback"])
        XCTAssertEqual(calls.last?.codexHome, files.paths.codexDir.path)
    }

    func testNoCodexCommandIsAClearError() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: nil)
        XCTAssertThrowsError(try files.connect(.codex)) { error in
            XCTAssertTrue("\(error)".contains("Couldn't find Codex"))
        }
    }
}

final class CodexFailureTextTests: XCTestCase {
    func testAFailureShowsOneReadableLineAndKeepsTheWholeOutputForTheLog() {
        let output = """
        Error: failed to load bootstrap configuration

        Caused by:
            0: /Users/me/.codex/config.toml:1:5: key with no value, expected `=`
               1: TOML parse error at line 1, column 5
        """
        let failed = CodexCLI.Failed(args: ["plugin", "marketplace", "add", "/x"], status: 1, output: output)
        XCTAssertEqual("\(failed)", "Codex couldn't add Readback's plugin list: failed to load bootstrap configuration. The full message is in Readback's log (About > Logs).")
        XCTAssertTrue(String(reflecting: failed).contains("TOML parse error at line 1, column 5"))
        XCTAssertEqual(CodexCLI.Failed.reason(in: ""), "no message")
        XCTAssertEqual(CodexCLI.Failed.reason(in: String(repeating: "x", count: 200)).count, 120)
    }
}

final class CodexPluginArtworkTests: XCTestCase {
    var home: URL!
    let cli = "/Applications/Readback.app/Contents/Helpers/readback"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("readback-art-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testConnectCopiesTheArtworkTheManifestNames() throws {
        let assets = home.appendingPathComponent("bundle/CodexPluginAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for name in CodexPlugin.assetNames { try Data(name.utf8).write(to: assets.appendingPathComponent(name)) }
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil,
                                     codex: { _, _ in }, bundledCodexAssets: assets)
        try files.connect(.codex)
        let plugin = files.paths.codexPluginSource.appendingPathComponent("plugins/readback")
        for name in CodexPlugin.assetNames {
            XCTAssertEqual(FileManager.default.contents(atPath: plugin.appendingPathComponent("assets/\(name)").path), Data(name.utf8))
        }
        let manifest = try JSONValue.parse(String(contentsOf: plugin.appendingPathComponent(".codex-plugin/plugin.json"), encoding: .utf8))
        XCTAssertEqual(manifest["interface"]?["logo"]?.stringValue, "./assets/logo.png")
        XCTAssertEqual(manifest["interface"]?["composerIcon"]?.stringValue, "./assets/composer-icon.png")
        let skillUI = try String(contentsOf: plugin.appendingPathComponent("skills/speak/agents/openai.yaml"), encoding: .utf8)
        XCTAssertTrue(skillUI.contains(#"icon_small: "../../assets/composer-icon.png""#))
    }

    func testAnOlderInstalledPluginIsAnUpdateWaiting() throws {
        let files = IntegrationFiles(paths: ReadbackPaths(home: home), cli: cli, bundledPlugin: nil, codex: { _, _ in })
        let codex = files.paths.codexDir
        try "[plugins.\"readback@readback\"]\nenabled = true\n".write(to: codex.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let hooks = CodexPlugin.files(cli: cli).first { $0.path.hasSuffix("hooks/hooks.json") }!.contents
        func install(_ version: String) throws {
            let url = codex.appendingPathComponent("plugins/cache/readback/readback/\(version)/hooks/hooks.json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try hooks.write(to: url, atomically: true, encoding: .utf8)
        }
        try install("1.0.0")
        XCTAssertEqual(try files.codexStatus(home: codex), .updateAvailable)
        try install(CodexPlugin.version)
        XCTAssertEqual(try files.codexStatus(home: codex), .connected)
    }
}
