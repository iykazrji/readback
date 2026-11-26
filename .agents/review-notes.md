# Review notes

Read by Deep Review before each review. An entry whose cited code changed needs a fresh check. The first reviewed snapshot is `b4d6449e1d5a9bb49e8437da50cdff8a3594772c`.

## How to verify here

- `swift test` ran 62 passing XCTest cases, one optional skip and 38 passing Swift Testing cases. The test target depends only on ReadbackCore. `Package.swift:16`.
- `READBACK_ROUNDTRIP_FILES=<fixture> swift test --filter RoundTrip` exercises exact byte equality. A valid compact settings fixture failed because the editor pretty-prints it. `Tests/ReadbackCoreTests/JSONAndIntegrationTests.swift:28`.
- `claude plugin test integrations/claude-code/readback` passed six runtime tests on 2.1.332. The native `claude plugin validate` command reported eight fixture type warnings. `integrations/claude-code/readback/tests/commands.test.ts:8`.
- Run the release build in a Git archive or scratch copy. Verify the bundle with `codesign --verify --deep --strict` and inspect the app and both helpers with `lipo -archs`. `scripts/build-app.sh:15`.

## Payload builders

- Swift Stop hook sends required reply text and tool source with optional session and cwd. An absent autoplay field means Readback combines session and tool preferences. `Sources/readback-cli/main.swift:206`.
- Claude `/read` sends full assistant text, tool, session, cwd, and autoplay true. `integrations/claude-code/readback/hooks/register.tsx:102`.
- OpenCode V1 idle builds assistant text from non-synthetic, non-ignored text parts, with session ID and plugin cwd. Busy sends only the session ID. `Sources/ReadbackCore/Integrations.swift:196`.
- The voice server request includes cleaned reply text as input, a model identifier, and optional voice, language, and generation options. `Sources/Readback/SpeechMakers.swift:209`.

## Known traps

- Bind/readiness checks at both local ports are not peer authentication. Check the caller credential before mutating state and verify the expected peer before sending a reply. `Sources/Readback/ControlServer.swift:100`, `Sources/Readback/SpeechMakers.swift:174`.
- Connect and Disconnect must prove file and hook ownership. Verify repeat runs and original config backup retention with a scratch home. `Sources/ReadbackCore/IntegrationFiles.swift:124`, `Sources/ReadbackCore/IntegrationFiles.swift:302`.
- Current Codex hook trust is tied to the exact hook definition, so an old hash cannot certify a changed hook. `Sources/ReadbackCore/Codex.swift:125`.
- Test queue advancement after unreadable and failed replies, and a new reply arriving between finish and FIFO advance. `Sources/Readback/AppDelegate.swift:60`, `Sources/Readback/AppDelegate.swift:242`.
- Exercise paused seek when a target chunk is still generating and verify both the eventual media offset and pause state. `Sources/Readback/Reader.swift:192`.
- Disk save errors must reach the hook and history UI. Keep unreadable history recoverable before replacing it. `Sources/Readback/Replies.swift:49`, `Sources/ReadbackCore/ReplyHistory.swift:108`.
- Model downloads are keyed by model but operation and progress ownership are stored as single values. Exercise two models, cancel, and startup update. `Sources/Readback/SpeechMakers.swift:302`, `Sources/Readback/Runtime.swift:68`.
- Readback's published v0.4.0 archive has only arm64 slices despite the Intel fallback promise. `scripts/build-app.sh:18`.

## Repo tools

- Use `ReadbackPaths(home:)` and the injected `CodexRun` for temporary-home integration tests. The injected runner does not verify production Codex compatibility. `Sources/ReadbackCore/IntegrationFiles.swift:10`, `Sources/ReadbackCore/IntegrationFiles.swift:81`.
- `Reader(makeSpeaker:)` accepts a controlled `SpeechMaker` for timing probes against production state and real AVPlayer with synthetic audio. `Sources/Readback/Reader.swift:51`.
- `ReplyHistory.save` uses atomic file replacement. Durability still depends on propagating failures and preserving the previous file on decode failure. `Sources/ReadbackCore/ReplyHistory.swift:115`.

## Ruled out

- Queue preservation above the cap is intentional while all entries are waiting. The defect is retaining excess after they become kept or played. `Sources/ReadbackCore/ReplyHistory.swift:61`.
- The bundled executable comes from the Swift CLI target. Legacy shell fallback issues in `bin/readback` do not affect the archive helper. `scripts/build-app.sh:19`.
- The Swift Reader run identifier and cancellation guards prevent a superseded generation from installing old audio into the new reader state. Outstanding system synthesis can still continue temporarily. `Sources/Readback/Reader.swift:87`.
