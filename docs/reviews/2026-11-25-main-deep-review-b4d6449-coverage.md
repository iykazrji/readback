# Readback 0.4.0 review coverage and candidate dispositions

[Review and verification results](2026-11-25-main-deep-review-b4d6449.md). Head `b4d6449e1d5a9bb49e8437da50cdff8a3594772c`, empty-tree baseline `4b825dc642cb6eb9a060e54bf8d69288fbee4904`. Full-file review covered 62 text files. Five PNG assets were inspected as binary assets. Readers followed the runtime and file-system callers across their assigned areas. Separate readers covered app, ingress, and runtime, followed by independent gap sweeps. The first passes' messages and app ledger survived the session interruption. The original ingress and runtime ledgers were still in progress, so the fresh passes reconstructed those coverage areas. The map groups closely related declarations that share a caller and contract. Recorded evidence is at file and unit-group granularity.

## Sentry Find Bugs checklist

| Item | Status and boundary evidence |
|---|---|
| Injection | No SQL layer, dynamic shell evaluation, server-side templates, or reflected response headers in the tracked app. The shell hook quotes the CLI path, generated JS uses JSON quoting and Bun interpolation, and Foundation Process receives argument arrays. The parser validation gap is D01. |
| XSS | No browser UI or raw HTML renderer. History converts Markdown to a native AttributedString with a plain-text fallback. Scheme behavior on a clicked native link remains P09. |
| Authentication | Both app TCP interfaces lack application authentication. The CLI and app also fail to verify the expected peers. S01–S02. |
| Authorization and IDOR | Loopback is the only inbound boundary, and session identifiers are selectors used for playback and preferences. S01, B08. Tool paths come from the current user environment or local installation, not network path input. |
| CSRF | The control app does not validate HTTP Origin or JSON media type. MLX's CORS default is wildcard. Browser-to-loopback reachability was not exercised. S01, P01. |
| Race conditions | The playback queue, integration settings merge/write, timeout response, neural process ownership, and installer transitions each have a timing or ownership problem. B03, B06–B07, B10–B11, D04. |
| Session | There is no cookie, browser login, or authenticated server session. The app stores session IDs for speech eligibility and associates replies with optional session owners. Missing/scoped stop and history replay are covered by B08–B09. Session log metadata is S03. |
| Cryptography | No app credentials, crypto implementation, signing protocol, or embedded secret was found in the tracked source sample. App and Swift CLI are signed ad hoc. Codex's trust hash is read as status but not tied to the current hook in Readback. B05, S06. |
| Information disclosure | Private text can cross an unauthenticated peer boundary or be written to diagnostics. File modes and effective local access were checked separately. S02–S03, S05, P08. |
| Denial of service | TCP connection and work limits, repeated history rewrites, queued-history growth, hook deadlines and long-running subprocesses remain relevant. S04, B10, B13, B15, P06–P07. |
| Business logic | Queue, persistence, playback controls, runtime lifecycle, trimming, release architecture, compatibility, and status issues recorded in the main review and below. |

Use the lists below for access-surface scope. HTTP routes parse body fields, use no cookies or database, return fixed headers, and read or update MainActor Reader/Preferences/ReplyHistory/Runtime through AppDelegate. Hook clients consume user prompts or assistant replies and local source/session/cwd metadata, read local preferences/files, and use exact local paths for HTTP or subprocesses. Integration settings and backups use local files and Codex's own CLI. The runtime executes bundled uv, uses Python, Hugging Face and MLX model files, and uses cleartext local HTTP. UI code renders native views and edits those same local objects. Build and design tools run locally with operator-controlled flags and paths. Tests use synthetic, temporary-home and fake host fixtures.

## Lens key and applicability

C1 contract and callers, C2 empty/extreme, C3 copies, C4 state across runs, C5 order/concurrency, C6 failures, C7 skips, C8 identity, C9 lifecycle, C10 persistence/migrations, C11 security, C12 tests, C13 spec, C14 repo rules, C15 wording. C14 is inapplicable across groups because the snapshot includes no project review rule files. Database-specific checks are inapplicable throughout. In the unit maps, unlisted lenses had no additional candidate when applicable. Persistent state, UI lifecycle, account isolation, and code execution are inapplicable to a unit that has no matching surface. Each row includes the callers that establish the relevant scope.

## Additional confirmed observations

| ID | Severity | Trigger and impact | Evidence and fix |
|---|---|---|---|
| D01 | Medium | A config contains a leading-zero numeric literal or duplicate names. Readback's parser can accept and re-emit the invalid numeric syntax or operate on the first duplicate while another host resolves a different one. | `JSONValue.swift:29–42,118–134,205–211,247`. Enforce the JSON grammar and reject ambiguous settings before edits. |
| D02 | Medium | A neural synthesis error leaves the engine running. Failure cancels the app's idle clock, which is scheduled only for idle or finished. A log-handle failure just after starting a model download can separately leave the active progress stuck. | `AppDelegate.swift:66–71,177–192`, `SpeechMakers.swift:317–349`. Use terminal lifecycle cleanup for all phases and clear an operation's own status in every exit path. |
| D03 | Medium | Repeated Stop of a backlog persists an entire history snapshot for each entry before closing the reader. More waiting entries cause repeated serialization of every item. | `AppDelegate.swift:235–239,275–283`, `Replies.swift:26–29,49–55`. Stop the audio first, then batch the state update and save. Actual UI latency depends on data and hardware. |
| D04 | Medium | The CLI's semaphore wait times out around completion. The URLSession callback can still write the shared result while the caller reads it and returns. | `Sources/readback-cli/main.swift:62–80`. Use a task with structured cancellation and one synchronized result, including on timeout. |
| D05 | Medium | CLI app startup resolves a tool of unsupported version while a newer CLI is also installed, or OpenCode uses a supported non-default global config root. Discovery selects the first Codex executable before checking the version. OpenCode status uses one hardcoded directory. | `Codex.swift:242–259,332–339`, `IntegrationFiles.swift:62–63,103–120`. Discover supported installations and distinguish detected, installed, and ready. |
| D06 | Medium | History Clear advertises removal of every saved reply, but explicitly preserves waiting replies. A short reply can also have relevant content elided from its preview with no Expand button, since eligibility checks raw length. | `HistoryPages.swift:189–193,216–225,313–320,413–419`, `ReplyHistory.swift:44–48,84–92`, `Replies.swift:14–18`. Clarify queue retention and enable viewing whenever the display omits original content. |
| D07 | Low | `/speak off` in Claude announces off while the global auto-read preference can still read that session. The CLI's status-only `auto` and `session` commands likewise treat error bodies as off. | `register.tsx:89–99`, `AppDelegate.swift:251–255`, `Sources/readback-cli/main.swift:276–305`. Surface effective state and standardize the HTTP status/schema check. |
| D08 | Low | The legacy shell helper places full reply text in jq process arguments and omits session attribution. It has no tracked caller and the archive ships the Swift CLI. | `bin/readback:39–69`, `scripts/build-app.sh:18–26`. Retire the script or bring it up to the same protocol and keep reply text off argv. |
| D09 | Low | Idle health reports the previous chunk count and position after close. The menu can disable Stop in the brief idle interval before another queued item starts. The Escape badge remains visible when Escape capture is disabled. | `Reader.swift:119–135`, `AppDelegate.swift:373–387,493–496`, `PlayerView.swift:314–325`. Reset exposed status, derive command availability from queued work, and reflect active bindings in labels. |
| D10 | Low | While changing replies, canceled system-voice synthesis can keep running until its callback or timeout. When stopping during an audible cue, the cue is not explicitly stopped. A failed or cancelled operation leaves resources temporarily active. | `Reader.swift:119–155`, `SpeechMakers.swift:84–95,120–131`. Bind OS synthesis and cue lifetimes to the Reader run. |
| D11 | Low | For an unusually long reply, the right edge of the scrubber can select a chunk earlier than the final one because it applies a fixed whole-reply fraction cap before scaling. | `Reader.swift:192–197`, `SpeechText.swift:34–50`. Clamp based on the final chunk index and offset. |
| D12 | Low | A startup receipt with invalid contents is treated as installed by the existence check and suppresses update when decoding fails. | `Runtime.swift:53–61,106–111`. Validate the receipt as part of installation state and route malformed receipts to repair. |
| D13 | Low | A disabled Codex plugin can leave its registration and marketplace after the CLI announces a successful disconnect. | `IntegrationFiles.swift:201–215`, `Sources/readback-cli/main.swift:342–349`. Determine whether registration exists independently of enablement. |
| D14 | Low | A customized Hugging Face path that uses a variable reference or another user's tilde expansion can resolve differently in Swift and in the actual Hub package. | `ModelCache.swift:16–27`. Align app cache discovery with the downloader's path resolution. |
| D15 | Low | Installer subprocess messages split at the read-buffer boundary can reach the UI as fragments. Its error reason may use the previous step's last line. | `Runtime.swift:245–270`. Buffer complete lines, drain at exit, and associate diagnostics with the installer operation. |

## Plausible and needs verification

| ID | Candidate | What would settle it |
|---|---|---|
| P01 | A browser origin can reach either local HTTP listener under some policy combinations. | Check the supported browsers' live local network permission and loopback behavior in an isolated defensive test plan. Local-client authorization in S01 is already established. |
| P02 | Non-audio bytes accepted from the model service or an AVPlayerItem read failure leave the queue stalled in playing state. | Use a controlled AVPlayer failure fixture and verify the phase and queue. The source currently observes normal end only. `SpeechMakers.swift:220–227`, `Reader.swift:217–245`. |
| P03 | An interrupted drag leaves stale scrub preview, or panel rehome misses a transition under Combine's pre-change publication. | Exercise native Trackpad interruption, Space change, and active panel navigation with controlled phase, and observe final scrub position and window. `PlayerView.swift:200–225`, `PlayerPanel.swift:55–79,114–148`. |
| P04 | Oversized or unavailable displays can strand the panel or cause its screen fallback to trap. | Exercise window positioning on a supported monitor-disconnect and mixed-resolution setup. The tested pure geometry helper and panel drag clamp are different. `PlayerPanel.swift:239–255,299–319`, `PlayerGeometry.swift:44–50`. |
| P05 | Two instances using the same per-user temp path can erase each other's audio, and a CLI-triggered first launch can unexpectedly show setup. | Confirm launch-service behavior and temp path identity on duplicate launch, and inspect first-run state in a disposable user session. `AppDelegate.swift:37–56,82–89,129–156`. |
| P06 | Reader's progress events can cause repeated expensive preview cleanup during playback. | Measure SwiftUI view updates and main thread cost using a representative large history. `Reader.swift:55–57,256–263`, `PlayerView.swift:482–541`, `ReplyHistory.swift:44–48`. |
| P07 | The idle callback can stop a voice session around resumed playback, or an engine that did not stop before quit can survive launch teardown. | Instrument actual actor and child-process state with a synthetic request arriving on the idle deadline, then use a slow-exiting isolated child. `AppDelegate.swift:92–98,177–192`, `SpeechMakers.swift:232–257`. |
| P08 | Actual Codex error output may disclose config diagnostics or a source line to Readback's log. | Run an intentionally invalid, synthetic disposable Codex config and inspect the emitted stderr. The forwarding path is confirmed. `Codex.swift:225–226,349–370`, `Connections.swift:107–119`. |
| P09 | A native clickable Markdown link may support schemes outside the intended history UI behavior. | Establish default `openURL` scheme handling and any extra exposure on supported macOS with a harmless link. No web execution was found. `HistoryPages.swift:333–339,413–419`. |
| P10 | A final tool-only OpenCode assistant item can hide prior reply text, and idle retries can replay the same reply. | Inspect version-specific idle event and current-turn message ordering using a tool-only final assistant fixture. The adapter asks for the session's messages and picks the newest assistant item before filtering for text. `Integrations.swift:196–212`. |
| P11 | A live Claude mod's periodic health observations can outlive the host session or race Stop. | Use the real mod lifecycle to check timer disposal and delayed observations after Stop. The unit suite uses noninteractive sessions and mocked fetch. `register.tsx:55–85,112–118`. |
| P12 | Qwen's token cap can truncate supported languages or unusual text. | Measure generated speech for representative multilingual sentences with the pinned engine. The core probe confirmed a 45-character Chinese sentence gets an 80-token cap, and audio delivery was outside the probe. `VoiceCatalog.swift:146–180`. |
| P13 | History undo can lose its retained snapshot after navigation, and can reorder waiting replies after the wall clock moves backward. | Verify view state recreation in the UI and simulating a reversed date order for queued replies. `HistoryPages.swift:147–148,217–232`, `ReplyHistory.swift:97–104`. |
| P14 | Runtime CORS covers broader MLX operations while actual installed dependency issues depend on the resolved package set. | Resolve a disposable environment, inspect pin and provenance, and run advisory checks. Readback's loopback side effects remain confirmed. `Runtime.swift:19–24,149–152`. |
| P15 | Older OS versions may deliver AVSpeechSynthesizer buffers on a different queue than the one asserted by `MainActor.assumeIsolated`. | Verify native AVFoundation callback queue behavior on macOS 15 and 26. A clean ordinary speech write succeeded on the review Mac. `SpeechMakers.swift:84–95`. |
| P16 | The backend accepts an existing local model folder, while the Voices page interprets it only as a Hugging Face cache key. | Determine whether local paths are a supported product input and check actual macOS behavior with a supported local model fixture. `ModelCache.swift:31–32,119–122`, `VoicesPage.swift:151–157`. |

## Dispositions and merged candidates

Candidate IDs below refer to the independent passes. B and S refer to the main report. D and P refer to this appendix. Qualifiers limit the finding to the established code path.

| Pass | Candidate disposition |
|---|---|
| Initial app | A01 → B03. A02 → B03. A03 → B06. A04 → B08. A05 → B12. A06 → B04. A07 → D09. A08 → B18. A09 → B19. A10 → B17. A11 → B17. A12 → B23. A13 → B06. A14 → B04. A15 → P03. A16 → B24. A17 → D02. A18 → D06. A19 → P13. A20 → P04. A21 → B15. A22 → P02. A23 → B19. A24 → P05. A25 → D03. A26 → P05. A27 → P09. A28 → S03. A29 → B18. A30 → rejected below. A31 → D09. A32 → rejected below. A33 → B23. A34 → P07. A35 → B17. A36 → P03. A37 → D10. A38 → D10. A39 → P13. A40 → B18. A41 → P06. A42 → verified test-scope limitation. |
| Initial ingress | IN-01 → S01. IN-02 → B01. IN-03 → S03. IN-04 → B08. IN-05 → S02. IN-06 → B12. IN-07 → B08. IN-08 → B05. IN-09 → B09. IN-10 → B09. IN-11 → B13. IN-12 → B07. IN-13 → B23. IN-14 → B14. IN-15 → B07. IN-16 → D05. IN-17 → D07. IN-18 → B13. IN-19 → S04. IN-20 → D04. IN-21 → B11. IN-22 → B18. IN-23 → D05. IN-24 → D07. IN-25 → D08. |
| Initial runtime and independent ingress seam sweep | R01 → S01. R02 and IN-R1 → S02. R03 → B08. R04 → B12. R05 → B24. R06 → S01. R07 and IN-R4 → B11. R08, IN-R2 and IN-R3 → B10. R09 → B11. IN-R5 → D02. IN-R6 → B16. |
| Fresh ingress | GI-01 → B21. GI-02 → B07. GI-03 → P08. GI-04 → D01. GI-05 → D13. GI-06 → P11. GI-07 → P10. GI-08 → D08. |
| Fresh app and runtime | G-A1 → B24. G-A2 → D11. G-A3 → D09. G-A4 → B23. G-A5 → D06. GR-01 → B11. GR-02 → D12. GR-03 → B22. GR-04 → P12. GR-05 → B24. GR-06 → D02. GR-07 → B11. GR-08 → S06. GR-09 → B10. GR-10 → P07. GR-11 → B11. GR-12 → rejected below. GR-13 → D10 / P15. GR-14 → rejected below. GR-15 → S03. GR-16 → D14. GR-17 → D15. GR-18 → P16. GR-19 through GR-23 → rejected below. GR-24 → verified test-scope limitation. |

### Rejected or bounded

- A30. Reusing the same explicit reading for the same text/session is the documented replay behavior in `AppDelegate.swift:257–265`. Tool producers supply session IDs in normal flows. The no-session legacy case remains in D08.
- A32. Setup can retry connecting a pending Codex registration, but the current source uses a serial action queue and explicit approved versus pending branches. No separate functional failure beyond known status/mutation findings was established. `SetupSheet.swift:148–160,297–300`, `Connections.swift:98–120`.
- GR-12. The model progress producer supplies integer counters and a finish signal tied to the completed model. Parsing remains tolerant. The current producer does not supply negative progress or falsely finished alternatives. `ModelCache.swift:95–103,126–159`.
- GR-14. `maxChars` limits coalescing adjacent sentences; a complete sentence can be longer by contract. `SpeechText.swift:32–48`.
- GR-19 and GR-20. Fixed valid ports, an immutable optional checked before the force unwrap, and a zero-based Data buffer produced by the listener rule out the specific suspects. `ControlServer.swift:53–85`, `HTTPRequest.swift:89–90`, `SpeechMakers.swift:157–166`.
- GR-21. The model is passed as a separate argument to a fixed Python program. No dynamic shell execution is on that path. `SpeechMakers.swift:325–331`, `ModelCache.swift:113–125`.
- GR-22 and GR-23. Clearing the continuation before resumption prevents double completion, and the current HTTP listener handles one request per connection and closes it. Ambiguous framing remains a validation issue covered by S04. `SpeechMakers.swift:120–131`, `ControlServer.swift:157–161`.
- A42 and GR-24. There is no claim that the core test suite instantiates the app. Package configuration verifies this coverage limitation, which explains why the experiments ran through Reader/AVPlayer and scratch file boundaries. `Package.swift:16–19`.
- The waiting-review cap intentionally preserves queued entries that are still awaiting playback. B15 counts excess entries after leaving the queue. `ReplyHistory.swift:61–79`.
- Tests and sources use skip/continue for unrelated hooks, missing items, and cancellation. The SDK's `XCTSkip` is fixture-dependent and was exercised separately. `JSONAndIntegrationTests.swift:28–30`, `Integrations.swift:78–104`, `Reader.swift:95–106`.
- Phase guards and a run UUID prevent an old generation from installing audio into a new reading. D10 concerns external synthesis and cue cleanup. `Reader.swift:87–108,120–135`.
- Finding local loopback control does not establish LAN binding or browser access. The initialized listeners receive explicit loopback addresses. `ControlServer.swift:53–56`, `SpeechMakers.swift:395–398`.
- The rebuild gap does not affect release icon packaging. The release script builds iconsets from tracked assets and passed in the clean snapshot. `scripts/build-app.sh:37–50`.

## File inventory and unit maps

The tracked inventory below is the full empty-tree diff. The subsequent maps link functional units to call sites. Every PNG was inspected by its format and dimensions. Code, manifests, shell scripts, and documentation were reviewed through EOF.

<details><summary>All 67 tracked files</summary>

- [.gitignore](../../.gitignore)
- [AGENT-SETUP.md](../../AGENT-SETUP.md)
- [Package.swift](../../Package.swift)
- [README.md](../../README.md)
- [Resources/AppIcon-1024.png](../../Resources/AppIcon-1024.png)
- [Resources/MenuBarIcon.png](../../Resources/MenuBarIcon.png)
- [Resources/MenuBarIcon@2x.png](../../Resources/MenuBarIcon@2x.png)
- [Resources/ThirdPartyNotices.txt](../../Resources/ThirdPartyNotices.txt)
- [Sources/Readback/AppDelegate.swift](../../Sources/Readback/AppDelegate.swift)
- [Sources/Readback/Connections.swift](../../Sources/Readback/Connections.swift)
- [Sources/Readback/ControlServer.swift](../../Sources/Readback/ControlServer.swift)
- [Sources/Readback/Log.swift](../../Sources/Readback/Log.swift)
- [Sources/Readback/ModelDownloads.swift](../../Sources/Readback/ModelDownloads.swift)
- [Sources/Readback/PlayerPanel.swift](../../Sources/Readback/PlayerPanel.swift)
- [Sources/Readback/PlayerView.swift](../../Sources/Readback/PlayerView.swift)
- [Sources/Readback/Preferences.swift](../../Sources/Readback/Preferences.swift)
- [Sources/Readback/Reader.swift](../../Sources/Readback/Reader.swift)
- [Sources/Readback/Replies.swift](../../Sources/Readback/Replies.swift)
- [Sources/Readback/Runtime.swift](../../Sources/Readback/Runtime.swift)
- [Sources/Readback/SpeechMakers.swift](../../Sources/Readback/SpeechMakers.swift)
- [Sources/Readback/Window/AboutSettings.swift](../../Sources/Readback/Window/AboutSettings.swift)
- [Sources/Readback/Window/ConnectionSettings.swift](../../Sources/Readback/Window/ConnectionSettings.swift)
- [Sources/Readback/Window/HistoryPages.swift](../../Sources/Readback/Window/HistoryPages.swift)
- [Sources/Readback/Window/MainWindow.swift](../../Sources/Readback/Window/MainWindow.swift)
- [Sources/Readback/Window/ReadingSettings.swift](../../Sources/Readback/Window/ReadingSettings.swift)
- [Sources/Readback/Window/SetupSheet.swift](../../Sources/Readback/Window/SetupSheet.swift)
- [Sources/Readback/Window/Surfaces.swift](../../Sources/Readback/Window/Surfaces.swift)
- [Sources/Readback/Window/VoicesPage.swift](../../Sources/Readback/Window/VoicesPage.swift)
- [Sources/Readback/main.swift](../../Sources/Readback/main.swift)
- [Sources/ReadbackCore/Codex.swift](../../Sources/ReadbackCore/Codex.swift)
- [Sources/ReadbackCore/HTTPRequest.swift](../../Sources/ReadbackCore/HTTPRequest.swift)
- [Sources/ReadbackCore/IntegrationFiles.swift](../../Sources/ReadbackCore/IntegrationFiles.swift)
- [Sources/ReadbackCore/Integrations.swift](../../Sources/ReadbackCore/Integrations.swift)
- [Sources/ReadbackCore/JSONValue.swift](../../Sources/ReadbackCore/JSONValue.swift)
- [Sources/ReadbackCore/ModelCache.swift](../../Sources/ReadbackCore/ModelCache.swift)
- [Sources/ReadbackCore/PlayerGeometry.swift](../../Sources/ReadbackCore/PlayerGeometry.swift)
- [Sources/ReadbackCore/ReplyHistory.swift](../../Sources/ReadbackCore/ReplyHistory.swift)
- [Sources/ReadbackCore/SpeechText.swift](../../Sources/ReadbackCore/SpeechText.swift)
- [Sources/ReadbackCore/VoiceCatalog.swift](../../Sources/ReadbackCore/VoiceCatalog.swift)
- [Sources/readback-cli/main.swift](../../Sources/readback-cli/main.swift)
- [Tests/ReadbackCoreTests/ClaudeConfigDirTests.swift](../../Tests/ReadbackCoreTests/ClaudeConfigDirTests.swift)
- [Tests/ReadbackCoreTests/ClearUndoTests.swift](../../Tests/ReadbackCoreTests/ClearUndoTests.swift)
- [Tests/ReadbackCoreTests/CodexTests.swift](../../Tests/ReadbackCoreTests/CodexTests.swift)
- [Tests/ReadbackCoreTests/DeliveryTests.swift](../../Tests/ReadbackCoreTests/DeliveryTests.swift)
- [Tests/ReadbackCoreTests/EngineCatalogTests.swift](../../Tests/ReadbackCoreTests/EngineCatalogTests.swift)
- [Tests/ReadbackCoreTests/IntegrationFilesTests.swift](../../Tests/ReadbackCoreTests/IntegrationFilesTests.swift)
- [Tests/ReadbackCoreTests/JSONAndIntegrationTests.swift](../../Tests/ReadbackCoreTests/JSONAndIntegrationTests.swift)
- [Tests/ReadbackCoreTests/ModelCacheTests.swift](../../Tests/ReadbackCoreTests/ModelCacheTests.swift)
- [Tests/ReadbackCoreTests/PlayerGeometryTests.swift](../../Tests/ReadbackCoreTests/PlayerGeometryTests.swift)
- [Tests/ReadbackCoreTests/ReadbackCoreTests.swift](../../Tests/ReadbackCoreTests/ReadbackCoreTests.swift)
- [Tests/ReadbackCoreTests/ReplyHistoryTests.swift](../../Tests/ReadbackCoreTests/ReplyHistoryTests.swift)
- [bin/readback](../../bin/readback)
- [design/icon/NOTES.md](../../design/icon/NOTES.md)
- [design/icon/cadence-brass-contact.png](../../design/icon/cadence-brass-contact.png)
- [design/icon/readme-icon.png](../../design/icon/readme-icon.png)
- [design/icon/source/finish.py](../../design/icon/source/finish.py)
- [design/icon/source/publish.py](../../design/icon/source/publish.py)
- [design/icon/source/render.py](../../design/icon/source/render.py)
- [docs/DEVELOPMENT.md](../../docs/DEVELOPMENT.md)
- [docs/README-for-friends.md](../../docs/README-for-friends.md)
- [integrations/claude-code/readback/.claude-plugin/plugin.json](../../integrations/claude-code/readback/.claude-plugin/plugin.json)
- [integrations/claude-code/readback/hooks/hooks.json](../../integrations/claude-code/readback/hooks/hooks.json)
- [integrations/claude-code/readback/hooks/register.tsx](../../integrations/claude-code/readback/hooks/register.tsx)
- [integrations/claude-code/readback/tests/commands.test.ts](../../integrations/claude-code/readback/tests/commands.test.ts)
- [integrations/claude-code/readback/tsconfig.json](../../integrations/claude-code/readback/tsconfig.json)
- [integrations/claude-code/readback/types/index.d.ts](../../integrations/claude-code/readback/types/index.d.ts)
- [scripts/build-app.sh](../../scripts/build-app.sh)

</details>

### Build, design assets, docs and specifications

| Unit | Inputs, state and side effects | Callers and lens findings |
|---|---|---|
| `Package.swift:1–21`, `.gitignore:1–8` | macOS deployment, Swift mode, target dependencies, file exclusions | Swift build/test, Git and clean archive. C1/C3/C9/C10/C12/C13/C15 → B02, B20, A42. |
| `scripts/build-app.sh:10–87` | Build inputs, native executables, bundle, copied uv/plugin/icons, signing, archive | Release developer and distribution docs. C1/C2/C3/C4/C6/C10/C11/C12/C13/C15 → B02, B20, S06. |
| `design/icon/source/render.py:10–424` | CLI selects stage/design and builds procedural geometry, camera, materials, scene, images | `publish.py`, design notes. C1/C2/C3/C6/C7/C12/C13/C15 → B20. |
| `design/icon/source/finish.py:11–51`, `design/icon/source/publish.py:17–102` | Plate-to-icon conversions, subprocesses using operand arrays, prior plate and output, proof sheets | Design notes, local reproduction. C1/C3/C4/C6/C7/C12/C13/C15 → B20. |
| `Resources/*.png`, `design/icon/*.png` | 1024 px app icon, 18 and 36 px menu icons, 256 px README icon, 1216 × 1210 proof | Build assets and README. Format and dimensions checked. Installer asset publishing passed. |
| `README.md`, `AGENT-SETUP.md`, `docs/DEVELOPMENT.md`, `docs/README-for-friends.md`, `design/icon/NOTES.md`, `Resources/ThirdPartyNotices.txt` | Public platform support, workflows, approval, installer/removal, retention, art and dependency provenance | First launch, installers, contributor instructions. C1/C3/C4/C6/C9/C10/C11/C12/C13/C15 → B01–B02, B05, B08–B09, B11, B15, B17, B20–B22, S06. |

**Coverage map**

Each row records the contract, reads/writes and exercised callers. Lenses 1–15 were applied to each group. 1 contract, 2 inputs, 3 copies, 4 persistence, 5 concurrency, 6 failure, 7 skips, 8 identity, 9 lifecycle, 10 migrations, 11 security, 12 tests, 13 spec, 14 repo rules, 15 wording. Lenses shown identify candidates, including the original ingress ledger; remaining applicable lenses yielded no additional candidate. N/A 14 across all rows because the repository snapshot has no review/project rule files. SQL/query scoping, SQL migrations, browser HTML/DOM, cookies, credentials and cryptographic primitives are inapplicable where the unit has no corresponding boundary. Handbook and generated-skill instructions were read as content.

| Unit and locations | Contract, state and effects | Callers and coverage |
|---|---|---|
| Codex plugin marketplace, manifest, hooks, skills, UI YAML and art names (`Codex.swift:10–117`) | Maps CLI path into generated records, quotes the shell argument, writes files indirectly. Menu skills remain explicit. | IntegrationFiles.writeCodexPlugin, CodexConfigTests, CodexPluginArtworkTests. 1/3/4/10/12/13/15 tied to approval/stale version. 9 has no UI lifecycle in file generation. |
| Codex approval, event constants, enable-status scanners (`Codex.swift:119–169`) | Read selected TOML tables, no changes to trust. | IntegrationFiles.codexHooksApproved/codexStatus/disconnectCodex, UI Connections, CLI integrations/connect, tests. 1/2/3/6/7/8/10/12/15 for staleness, parser, disabled registrations. |
| PromptCommand branches and CodexHookPayload (`Codex.swift:171–201,374–382`) | Exact bare or skill-mention commands, file-existence classification. No mutable persistent state. | CLI prompt/Stop and CodexPromptTests. 1/2/6/7/8/12/13 around unsupported mentions and legitimate unsaved sessions. 4/9/10 N/A for pure matching. |
| CodexCLI discovery, status messages, subprocesses (`Codex.swift:203–372`) | Chooses executable, checks version, uses login shell fallback and pipe, remembers executable per runner, error displays and diagnostics. | Connections.makeFiles, CLI integrationFiles, Codex tests. 1–7/11/12/13/15 for timeouts, inherited config, wrong CLI selection and possible log privacy leakage. |
| ReadbackPaths fields and init (`IntegrationFiles.swift:3–64`) | Maps normal/override home to support, preferences, transcript tool paths, plugin/cache. | Runtime, SpeechMakers, Replies, Connections/AppDelegate, CLI, discovery/setup, tests. 1/2/3/4/8/10/12/13/15 for XDG and fake-home isolation. |
| IntegrationFiles injection, status, connect/disconnect, Claude mod staging (`IntegrationFiles.swift:68–185`) | Directory/install detection, edits option files and materializes mod, prepares UI state and failures. | CLI integration subcommands, Connections and setup. 1–8/10–13/15 for partial connections, competing writers, OpenCode ownership, backup lifecycle, missing V2 gate. |
| IntegrationFiles Codex connect/disconnect, installed-cache selection, art and old-hook migration (`IntegrationFiles.swift:187–281`) | Tracks global/home-specific plugin, edits files or invokes exact CLI; repairs shared Orca/default cache. | CLI integration subcommands, Connections/Orca, fake Codex tests. 1–8/10–13/15 for partial migrations, disabled state, approval/version. |
| IntegrationFiles readJSON/writeJSON (`IntegrationFiles.swift:289–311`) | Converts missing/empty to object, emits parse failure or pretty-prints atomic config and backup. | status/connect/disconnect/removeOldCodexHooks. 1–7/10–13/15 for benign round trip, backup churn, unsupported syntax and concurrency. |
| Tool and Integrations command ownership, hook access/edit, Claude env edits/status (`Integrations.swift:3–166`) | Tool identity aliases, generates shell-safe commands, adds/removes hook records and plugin-dir entries. | generated Codex hooks, CLI tool decoding, HTTP routes/app/reply history, IntegrationFiles, tests. 1–8/10–13/15 for ownership and hook completeness. |
| Integrations generated OpenCode adapter and marker parser (`Integrations.swift:168–229`) | Escapes CLI path using JSON printer, event metadata and transcript to hook stdin; connection status recognizes marker/path. | IntegrationFiles connect/disconnect/status and tests. 1–9/11–13/15 for host API, transcript order, source/identity/races. |
| JSONValue cases/accessors, equality, parser helpers and printer (`JSONValue.swift:6–274`) | Maintains order, parses scalar/object/array/string/escape/number, performs edit/read and pretty printing. | IntegrationFiles file parsing/writes; CodexPlugin and OpenCode path serialization; JSON/Integration tests. 1/2/3/6/7/10/11/12/15 for duplicate keys/number grammar, malformed backup and byte contract. 4/5/8/9 N/A for pure values. |
| HTTPRequest framing, JSON response, SpeakRequest construction and display metadata (`HTTPRequest.swift:5–95`) | Bounds Content-Length, parses headers/body, renders JSON, carries tool and session metadata. | ControlServer receive/route, CLI/Claude/OpenCode input, Reply and Reader, Core HTTP tests. 1–3/5–8/11–13/15 for parse limits, session ownership, absent headers and status. 4/9/10 N/A for pure messages. |
| CLI common options, logs, HTTP, launch, stdin, prefs and helper conversion (`main.swift:7–204`) | Reads env and stdin, waits on client and app launch, decodes transcript/preferences, outputs status. | CLI dispatch and published bundled helper. 1–9/11–13/15 for privacy, timeout/completion synchronization, size, local peer and fallback paths. |
| CLI hook, read, say, stop, prompt (`main.swift:205–289`) | Constructs text/cwd/tool/session payload, delivers or suppresses replies, returns Codex decision. | CodexPlugin, Claude generated settings and OpenCode adapter, ControlServer/AppDelegate, direct terminal users. 1–9/11–13/15 for swallowed failures, global stop, missing/latest transcript, prompt logging and idle app conditions. |
| CLI session, auto, voice, engine, wait, status, connect/disconnect/integrations/help (`main.swift:291–378`) | Asks/sets app prefs and runtime; reports connection and package status. | Shell/documented entry points, Setup, ControlServer. 1–9/11–13/15 for false success, invalid state, status/port and lifecycle. |
| Legacy shell CLI options, helpers and dispatch (`bin/readback:14–88`) | Uses network and jq, old input shapes and output, asynchronous stop/notification. | No tracked packaging/caller. 1–9/11–13/15 for session omissions, log path, command args and status. |
| Claude manifest, hook map, ambient types, tsconfig and register module (`integrations/claude-code/readback/*`) | Links host mod API and persistent atom to session startup, timer, immediate slash commands, stop band and loopback endpoints. | Installer, IntegrationFiles.copyPlugin, live Claude engine/commands tests. 1–9/11–13/15 for shape/peer health, stop ordering, timer disposal and validation warnings. |
| Connections makeFiles, refresh, Connect/Disconnect dispatch and launch refresh (`Connections.swift:6–132`) | Projects state, errors and serialized config writes; log sink. | AppDelegate launch, SetupSheet, ConnectionSettings, Sidebar. 1–9/11–13/15 for execution serialization/limits, CLI competing writers and trust/old version. |
| `ClaudeConfigDirTests.swift`, `IntegrationFilesTests.swift`, `CodexTests.swift`, `JSONAndIntegrationTests.swift`, Claude `commands.test.ts` | Assertions on pure commands/parsers and fake test home/host. Real runner, actual installer process, trust check and native app excluded from fixtures. | Swift Package test entry / Claude plugin test. 2/4/5/6/8/10/12/15 for compact and malformed config, disabled approval, asset/cached fake, synthetic settings and missing integration coverage. |

### App, playback and settings units

Reviewed b4d6449e1d5a9bb49e8437da50cdff8a3594772c against the empty tree. Read each app, UI, history and geometry file and three test files through EOF. The 15 Deep Review lenses were checked where applicable. Lens 14 did not apply because the tracked snapshot contains no repository-specific review rules. Lens 10 applies to data-format and persisted-state transitions, and lens 9 applies to task/view/process lifecycle. Calculations and presentation code with no persisted state, ownership, or external effects do not have state-across-runs, migration, or security behavior. Initial app ledger IDs appear with the units they concern.

| Unit and file | Contract, state, effects, and production callers | Findings and test gaps |
|---|---|---|
| Readback/main.swift:1–9 | Construct the NSApplication and delegate with accessory policy. AppKit owns run loop. | Delegate local lifetime spans run. |
| AppDelegate.swift:33–104 | Launch/reopen/quit, establish panel, menu, server, timers and runtime; AppKit calls. | A01–02, A17, A26, A34. Native reopen and quit timing pending. |
| AppDelegate.swift:106–157 | Release quarantine and remove previous temporary audio at launch. Bundle path and temporary URL authority. | A24. Launch cleanup namespace shared if two instances can coexist. |
| AppDelegate.swift:159–220 | Select effective voice, reset panel, flip policy, arm idle timer, warm/download/sample. Used by Reader, Views, launch and MainWindow. | A17, A34, G-A1; concurrent model loading belongs to runtime review. |
| AppDelegate.swift:222–284 | Add, autoplay, replay, queue and stop; control API, panel, history and speech callbacks. Reads preferences, writes history and reader state. | A01–02, A04, A08, A25, A30–31, A40. App-level queue tests absent. |
| AppDelegate.swift:286–408 | Convert controls to session methods, preferences, runtime and status. ControlServer dispatch; hook binaries build request fields. | A04–07, A30, ingress findings. Native menu visibility needs AppKit check. |
| AppDelegate.swift:415–511 | Native menus and target helpers, opening the main window, status icon, command gating. AppKit action target. | A31; other menu actions route to tracked methods. |
| Connections.swift:1–80 | Poll installed/action/approval state from default paths for SetupSheet, MainWindow, Connections. | A12, A33, G-A4 and ingress status findings. MainActor refresh does synchronous file reads. |
| Connections.swift:82–133 | Launch serialized edits and publish action errors; directly refresh Claude mod from application launch. | Serialization applies inside one app; ingress covers another process and subprocess failures. |
| Preferences.swift:1–64 | Published UserDefaults defaults and reading/voice knobs; control API/views write, Reader/AppDelegate/settings consume. | A05, A09, A23, A35, G-A3. |
| Preferences.swift:66–112 | Session switch list with last-500 cap and VoiceSetup projection for AppDelegate/Runtime. | A04, A16, A28, G-A1; callers and fallback state checked. |
| Replies.swift:1–35,49–57 | Load and publish history, relaunch downgrades waiting, persist every app/UI mutation. | A06, A14, A21, A39, G-A5. |
| Replies.swift:37–47 | Persist reply/word counts from AppDelegate's play and show from Home. | A08. |
| Reader.swift:1–109 | Publish AVPlayer state/speed, clean and split message, choose synthesizer, stream files, reject stale run output. AppDelegate starts. | A01, A22, A37, A40–42. |
| Reader.swift:111–155 | Rate, teardown, temporary files, delayed cue. Panel/AppDelegate call. | A07, A37–38. Delayed playback checks UUID. |
| Reader.swift:157–265 | Playback and seek with generation waiting, end and time observers. PlayerView's buttons/scrubber call. | A03, A13, A22, A41, G-A2. |
| PlayerPanel.swift:1–114 | Bind reader and reply list changes, host/size/present player. AppDelegate and PlayerView. | A09, A20, A23, A36. showList has no caller, so its misleading menu comment is minor. |
| PlayerPanel.swift:117–192 | Make visible or rehome after Space/screen/policy changes. AppKit notifications and MainWindow calls. | A09, A20, A36, G-A3; actual Spaces behavior unverified. |
| PlayerPanel.swift:194–258 | Reset/hide, elapsed hide and hover guard, manual drag. Reading screen and PlayerView call. | A20, A23; panel drag cancellation resets via PlayerView GestureState. |
| PlayerPanel.swift:260–335 | Convert/default/migrate position, select monitor by foreground window or pointer. App/window/defaults paths. | A20; tests prove pure helper rather than native resize/drag call. |
| PlayerPanel.swift:337–419 | Borderless NSPanel with first-click support, resizing, register/unregister Carbon Escape. | A09, A20, G-A3. Callback ownership applies for process lifetime; no second registration in tree. |
| PlayerView.swift:1–162 | Display text, progress, queued list and AppKit actions; observes Reader, Replies and ModelDownloads. | A29, A41 and runtime's global download progress. |
| PlayerView.swift:165–278 | Chunk, fade, dot/timeline and accessibility/mouse seeking. Emits position to Reader. | A03, A15, G-A2. Normal producers provide finite geometry/values. |
| PlayerView.swift:280–405 | Buttons present and apply playback controls, speed, stop. | A13, G-A3. |
| PlayerView.swift:409–572 | List title/toggle, latest twenty, row date/playing state and replay action. | A29, A41. Recent list limit has full History counterpart. |
| Window/AboutSettings.swift:1–49 | Render version/notice, open local logs in Finder. MainView caller. | Log folder path is local, and errors are logged. No further finding. |
| Window/ConnectionSettings.swift:1–88 | Poll tool state, map rows and buttons to Connections. MainView route. | A33, G-A4. Task cleanup cancels on unmount. |
| Window/ConnectionSettings.swift:90–163 | Shared working indicator/instructions and tool artwork. SetupSheet also calls. | A10, A12, A33. |
| Window/HistoryPages.swift:1–135 | Home counters/recent/empty state and actions. MainView route. | A08, A12, A29. |
| Window/HistoryPages.swift:139–293 | Filter/group/clear/undo history, native search view. Mutates Replies and view-local fields. | A06, A19, A39, G-A5. Search coordinator refreshes binding; undo task checks cancellation. |
| Window/HistoryPages.swift:297–421 | Replay, preview, expand/copy/remove ReplyCard. Home and History call; pasteboard only on action. | A18, A27, A29, A41; link behavior would require click and native open semantics. |
| Window/MainWindow.swift:1–154 | AppKit window lifecycle and autosave, route view and setup sheet. AppDelegate and menu call. | A19, A26, A36. |
| Window/MainWindow.swift:157–240 | Unified header modifier and page titles. Home, History and settings call. | No new issue. Scroll-geometry and Reduce Motion inputs only. |
| Window/MainWindow.swift:242–384 | Sidebar arrow/hover/tile controls, selected state and queue badge. | About is a separate control. Native keyboard/focus accessibility remains unchecked. |
| Window/MainWindow.swift:388–487 | Now Playing or configured voice, bottom tile style and shared footer. Sidebar calls. | A29, G-A1. |
| Window/ReadingSettings.swift:1–110 | Read/speech options, sound sample, playback, Escape and ServiceManagement toggle. MainView calls. | A09, A23, G-A3. |
| Window/ReadingSettings.swift:112–125 | Register/unregister launch-at-login and show system result. Toggle calls. | External Login Items changes while form stays visible require native check. |
| Window/SetupSheet.swift:1–134 | First-run tool selection, download offer, approval polling. MainView sheet. | A26, A32; backups advertised here depend on integration implementation. |
| Window/SetupSheet.swift:138–313 | Step states, detail, download progress, and dispatch batch. Choice/progress UI and Connections/runtime call. | A10, A32, A35. |
| Window/SetupSheet.swift:315–434 | Reusable titles, choice/step/voice tiles and accessibility/meter. | A10 selectable instructions. Other handling is presentation of passed state. |
| Window/Surfaces.swift:1–76 | Palette and surface/style projections. Shared settings/sidebar callers. | No new issue; deterministic visual tokens. |
| Window/Surfaces.swift:77–142 | Card-style Form sections, labeled content and toggles. Settings pages call. | Switch accessibility tree requires native check. |
| Window/VoicesPage.swift:1–126 | Select model/voice engine, show install/remove/sample and derive choice. Runtime and AppDelegate callbacks. | A11, A16, A35, G-A1. |
| Window/VoicesPage.swift:129–259 | Render cache/download/installer retry and status. ModelCache filesystem reads and runtime actions. | A11, A16 and runtime tracking. Repeated reads performance needs profiling. |
| Window/VoicesPage.swift:261–423 | Model-specific options, system voice grouping and engine row state. Prefs binding and VoiceCatalog/ModelCache consumers. | A16, runtime catalog-membership/cache issues. |
| ReadbackCore/ReplyHistory.swift:1–49 | Reply payload, title/request/preview and persisted representation. App/reader/History callers. | A18, A28, A30, A41. |
| ReadbackCore/ReplyHistory.swift:51–105 | Keep/prune/order/restore queue records; Replies uses directly, core tests verify. | A21, A39, G-A5. |
| ReadbackCore/ReplyHistory.swift:106–121 | Decode optional or save throwing atomically. Replies bridges persistence. | A06, A14, A39. Tests cover only success and missing. |
| ReadbackCore/PlayerGeometry.swift:1–73 | Cocoa conversion, overlap, clamp, migration. PlayerPanel calls. | A20 at app call site; force unwrap has a short-circuit guard. |
| Tests/ReadbackCoreTests/ClearUndoTests.swift:1–57 | Queue/kept retention, Undo order, duplicate prevention and limit. | No interrupted undo in UI, backward wall clock or persistence failures. |
| Tests/ReadbackCoreTests/ReplyHistoryTests.swift:1–62 | Core arrival/FIFO, preview, request, cap and disk round-trip. | No core decode-failure fixture or app route/AVPlayer queue coverage. |
| Tests/ReadbackCoreTests/PlayerGeometryTests.swift:1–99 | Coordinate conversion, overlap, clipping, oversized frame and old placement. | No live NSPanel/Space integration. |


### Runtime, model and HTTP units

Positions 1–15 match deep-review/lenses.md. Other positions were checked without a new candidate where applicable. Lens 14 is N/A throughout because no scoped project rules were found. Common scope exclusions include SQL, HTML injection, web accounts/sessions, native package signing and crypto libraries. Process invocation, optional error coalescing, timers, casts, JSON, and skipped irrelevant entries were checked as Swift tripwire equivalents.

| Unit/file | Input/output, reads/writes, effects, direct callers | Lenses with findings or refreshed candidates | Other N/A |
|---|---|---|---|
| Runtime.init/isInstalled/needsUpdate/refresh/State/packages, Runtime.swift:8–64,106–115 | Read executable/receipt and publish runtime readiness. AppDelegate.swift:74–80,162–169,309–319, VoicesPage, SetupSheet, MainWindow. | 1–7,9–13,15 GR-01/02/07/08/24 | 8 no user selector |
| Runtime.update/retry, Runtime.swift:66–104 | Install packages and receipt, update state, optionally warm models. AppDelegate.swift:76–78; VoicesPage.swift:246. | 1,3–7,9,10,12,13,15 GR-01/02/07/24 | 8 one runtime |
| Runtime.install overloads/cancel, Runtime.swift:117–181 | Install Python and model from preferences, publish progress, terminate or finish user-visible operation. AppDelegate.swift:313; SetupSheet.swift:304; VoicesPage.swift:212,258. | 1–7,9–13,15 GR-07/08/24 plus cancellation | 8 one runtime |
| Runtime.startMeter/bytes, Runtime.swift:183–207 | Measure allocation; installer starts meter, SetupSheet.swift:190–211 consumes. | 3,5,6,9,12 and operation-scoped progress | 8 one runtime, 10 read-only filesystem |
| Runtime.remove/run/InstallError, Runtime.swift:209–272 | Remove private runtime or run installer child and save diagnostic lines. AppDelegate.swift:316 and VoicesPage.swift:94 call removal; update/install invoke run. | 1,3–7,9–13,15 GR-01/08/11/17/24 | 8 one runtime |
| SpeechMaker/NeuralVoice/SpeechError, SpeechMakers.swift:5–35,137–154 | Translate text and voice into an audio file or error. AppDelegate.swift:162–171 creates; Reader.swift:84–106 consumes. | 1,2,5,6,9,11,12,15 GR-04/13 plus peer identity/audio | 10 temp files only |
| SystemVoice/SystemVoiceJob init/run/received/delegate/finish, SpeechMakers.swift:39–133 | Use native AV synthesis to write CAF and complete once. AppDelegate.swift:171,342; VoicesPage.swift:323; Reader. | 2,3,5–7,9,12,15 GR-13/22/24 | 8 one voice request, 10 no migrations |
| VoiceServer.init/isInstalled/ensureRunning/synthesize/start/isUp, SpeechMakers.swift:157–228,385–409 | Own child and warm set, transport text/settings and return WAV. AppDelegate.swift:200,211; Runtime.swift:165, NeuralVoice methods. | 1–9,11–13,15 GR-04/05/09/19/24 and identity/audio | 10 persistent install handled separately |
| VoiceServer.stop/end/stopStray/listeners/command/run, SpeechMakers.swift:230–298 | Discover and retire child/process, signal stop. AppDelegate.swift:92–97,177–192; Runtime.swift:210–212; ensureRunning. | 1,3–9,11,12,15 GR-09/10/11/15 | 10 no durable data |
| VoiceServer.ensureDownloaded/download/makeNLTKFolder/logHandle, SpeechMakers.swift:302–383 | Start Python child, update UI, manage per-model tasks, log output. ensureRunning calls; ModelDownloads receives; start uses logHandle. | 1–13,15 GR-06/07/08/09/12/15/16/21/24 | none |
| DownloadLines.init/finished/failure/add, SpeechMakers.swift:414–447 | Buffer partial child stdout, parse events under lock, then notify callbacks. VoiceServer.download calls. | 1–3,5–7,9,12,15 GR-06/12/24 | 4,10 no persistence, 8 caller owns model |
| ModelDownloads.Status and started/failed/progress/ended/status, ModelDownloads.swift:6–57 | Track one model's progress/error. VoiceServer.download writes; AppDelegate.swift:185, PlayerView.swift:87, SetupSheet.swift:191, VoicesPage.swift:20,133,152,214 read. | 1–3,5–9,12,15 GR-06/09/12 and download races | 4,10 no persistence |
| ModelCache.init/folder/snapshot/contents/isDownloaded/modified, ModelCache.swift:8–85 | Resolve Hub root, read snapshot and blobs, infer availability. VoiceServer.ensureDownloaded, VoicesPage.modelRow/modelIsHere. | 1–13,15 GR-16/18 plus incomplete cache | none |
| ModelDownloadEvent.parse/ModelDownloadScript.source and progress callbacks, ModelCache.swift:89–161 | Send and receive progress JSON from constant Python script with model argv. Downloads Hub/auxiliary resources. VoiceServer.download, DownloadLines.add. | 1–9,11–13,15 GR-08/12/16/21/24 | 10 dependency-owned caches, no app data migration |
| ControlServer handlers/DTO/init/start/accept/receive/route/send, ControlServer.swift:13–163 | Accept loopback HTTP, decode and dispatch to main actor closure, respond. AppDelegate.swift:288–329 injects, CLI/mod/legacy invoke. | 1–13,15 GR-11/19/23/24, missing auth/size/false success | none |
| HTTPRequest.parse/HTTPResponse.json/SpeakRequest.init/tool/title, HTTPRequest.swift:5–95 | Raw bytes to request; JSON and title; ControlServer, Reader and Reply model consume. | 1–3,6–8,11,12,15 GR-19/20/23 | 4,5,9,10 pure helpers |
| SpeechText.clean/chunks/sentences/replaceTables/replace, SpeechText.swift:6–93 | Markdown to speech and preview chunks. Reader.swift:67; Replies.swift:44; ReplyHistory.swift:46. | 1–3,6,7,9,11–13,15 GR-03/04/14 | 4,5,8,10 pure text |
| EngineKind/VoiceOption/VoiceCatalog voice IDs, sizes, default and lang, VoiceCatalog.swift:4–131 | Map choices to UI labels and engine config. Preferences.voiceSetup, VoicesPage, AppDelegate.setVoice, ModelCache and ModelDownloads call. | 1–4,6,7,9–13,15 GR-02/05/08/16 | 5 static data, 8 no caller identity |
| Delivery/speechOptions, VoiceCatalog.swift:138–181 | Give neural engine sampling options and length cap. NeuralVoice.make and VoiceServer.synthesize consume. | 1–3,6,7,12,13,15 GR-04 | 4,5,8–10 pure options |
| Log.info/error/write, Log.swift:6–33 | Append asynchronous file diagnostics and publish unified log. App startup, runtime, playback, connections, storage, prefs. | 1–6,8–12,15 GR-15 | 13 diagnostic-only contract |
| ModelCacheTests, EngineCatalogTests, DeliveryTests, SpeechTextTests and HTTPRequestTests in ReadbackCoreTests.swift | SPM tests evaluate synthetic/cache fixtures and pure transforms. Entire files read, runtime seam absent. | 1–8,10–13,15 GR-24 and specific gaps | 9 no native UI |


### Added-line tripwires

| Tripwire | Hits | Disposition |
|---|---:|---|
| Environment defaults | 2 | CLI port and alternate-home fixture setup. The app fixed port and local response trust are reviewed in S01–S02. |
| Type escape | 1 | DownloadLines protects buffer and event state with NSLock. Model-operation ownership still matters in B10. |
| Non-null assertions | 4 | App ports are constant and UI/core optionals have guards where applicable. See GR-19 and the geometry row. |
| Untyped JSON boundary | 8 | CLI dictionary coercions, typed route shapes, subprocess progress and checked runtime receipts were traced. B08, B11, D01, D04, D07, D12, P11. |
| Current time | 7 | Reply and log timestamps, install receipt timestamp, UI counts and date display. Reordering on clock movement remains P13. |
| Timers | 12 | Queue hand-off, audio cue and cancellation, idle stop, install and model progress, panel/UI timers. B03, B10–B11, B19, D02, D10, P07, P11. |
| Batch skips and early returns | 38 | Hook ownership and unrelated entries, old audio names, missing text, malformed rows, and process status exits. See B03, B07–B09, B22–B23, P10. |
| Test skips | 1 | Opt-in real-config round trip. It was skipped by default and failed after an explicit valid settings fixture was supplied. B20. |
| Swift suppressed throw adaptation | 56 | Missing optional files and stale cleanup are expected in several sites. The findings trace misleading fallback or lost errors to B04, B08, B11, D02, D07 and D12. |
| Swift actor-isolation assertions | 11 | Most assert on observed callbacks with an explicitly supplied main queue or native main-thread ownership. The AVFoundation write callback path is P15. |
| Process invocation adaptation | 14 | Fixed executables and argument lists, local operator-controlled design/build paths, subprocess timeout and ownership. B02, B10–B11, B13, S03, S06 and P08. |
| Other skill tripwires | 0 | Empty catch, explicit promise catch-to-default, await-with-empty default, raw SQL, upsert/ignore, parallel promise writes, allSettled, async effect, module mocks, weak existence-only assertions, debug logging, and unfinished markers. Swift analogues are covered above. |

The always-block thresholds were applied to caller authentication (S01), sensitive application diagnostics (S03), and swallowed persistence failures reported as success (B04). Source review identified no database or schema migration. The validation commands and package test scope are recorded in the main report.
