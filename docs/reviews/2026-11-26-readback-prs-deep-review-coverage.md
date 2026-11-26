# Readback PRs #1–#3 · Deep review evidence and coverage

[PR #1 report](2026-11-26-pr-1-deep-review-a6b2b88.md) · [PR #2 report](2026-11-26-pr-2-deep-review-1942cef.md) · [PR #3 report](2026-11-26-pr-3-deep-review-1942cef.md)

The comparisons use the fetched GitHub ref OIDs and the computed merge bases. #3 is the aggregate of #1 and #2 against main, plus its draft release artifact. Stable OIDs were checked again after the review. Clean archives kept local changes and real tool configuration out of the checks. Independent readers covered integrations and protocol, app and runtime, releases and updater, UI, playback and audio, and upgrade boundaries. Whole source files and their direct callers were the unit of reading. The tables group connected contracts for presentation. The extra readers added separate passes at the upgrade, release, UI, and Core boundaries. The consolidated review does not provide an independent second result for every individual changed declaration.

## Evidence by snapshot

| Snapshot | Changed files | XCTest pass / skip | Swift Testing pass | Claude plugin pass | Build |
|---|---:|---:|---:|---:|---|
| Main `b4d6449` | Baseline | 62 / 1 | 38 | 6 | Published archive inspected |
| #1 `a6b2b88` | 52 | 138 / 1 | 43 | 7 | Release build and strict deep signature verification passed |
| #2 `1942cef` | 80 | 139 / 1 | 150 | 8 | Release build and strict deep signature verification passed |
| #3 `1942cef` | 110 | Same head | Same head | Same head | Reused pinned build and independently verified draft |

- Reproduced the default suite from clean pinned sources with `swift test` and `claude plugin test integrations/claude-code/readback`. The opt-in `READBACK_ROUNDTRIP_FILES=<scratch compact JSON> swift test --skip-build --filter RoundTrip` case failed on all three snapshots due to byte formatting. Both other selected RoundTrip tests passed. No database is used by this app.
- Built two clean archives with `./scripts/build-app.sh`. No warning or error was emitted in either build. Verified both with `codesign --verify --deep --strict`.
- Compiled against production ReadbackCore using a scratch fixture. It demonstrated older-revision model deletion, a collapsed identical turn, a failed active reply evicted at the history cap, an empty spoken chunk, stale update metadata, a mismatched release version that passes manifest checks, and a wrong newest reply after history reload. Code paths are in the two PR reports.
- Invoked production `VoiceServer.download` with a temp home and a filesystem failure opening its log. Its active model stayed set after the thrown error and Cancel. The scratch test of SystemVoice packaging an empty utterance returned an audio file on this host. No conclusion about empty neural synthesis was drawn.
- Ran the attached uv 0.10.4 against a throwaway Python 3.12 environment, with offline mode. The original command refused to replace a populated venv and preserved its sentinel. The new argument list containing `--clear` replaced it and removed that sentinel.
- Invoked Foundation on two scratch volumes and confirmed `isWritableFile` on both app and parent, replacement failure with POSIX 18, and the original marker still readable. The volume was detached.
- Installed the extracted 0.4 Claude mod into a scratch alternate-only setup. The default launch gate left 0.2.0 installed. A CLI-equivalent reconnect copied 0.3.0 and both commands. This exercised production Core file APIs and the exact launch condition. A live Claude app reload was outside the fixture.
- Validated the draft's packaged Claude plugin with `claude plugin validate --json`. Both namespaced commands were recognized. `--strict` additionally returned an author metadata warning. Generated Codex files and shipped icons matched the old release byte-for-byte for the same helper path.
- Inspected the actual draft archive, hash, signature, bundle version, minimum platform and slices. Inspected the same three slices from the public 0.4 archive. See the #3 report for exact artifact identifiers.
- Ran all 21 skill tripwires on added lines and added Swift checks for silent fallbacks, early returns, task suspension, time and file writes. The combined range #3 has 355 hits including 254 in #1 and 101 in #2. Counts include prose and multiple rules on the same line. False matches include `waitUntilExit()` matching a JS test-skip pattern. The fixture's `as any` header representation is assessed under I-29. SQL, transaction, JavaScript component effects, and database migration checks are inapplicable to the binaries.

## Lenses

1 contract, 2 bounds, 3 duplicated state, 4 state across runs, 5 ordering, 6 errors, 7 skips, 8 identity, 9 lifecycle, 10 persisted data, 11 security and privacy, 12 tests, 13 specification, 14 repo rules, 15 wording. In coverage tables, an ID points to the dispositions below. Explicit inapplicability in the source coverage is preserved. The matching reference in the candidate ledger supplies the unit path and trigger.

## Whole-stack boundary checks

| Boundary | Input → state or effect | Producer and consumer | Result |
|---|---|---|---|
| Hook wire protocol | Session, tool and reply → queue or reading | CLI hook / Claude mod / generated OpenCode → ControlProtocol → AppDelegate → ReplyQueue | I-01, I-09, A04. The plugin suites cover their fixtures. Live rolling upgrades require host verification. |
| Durable queue | Waiting and active IDs → history, restart and replay | ReplyQueue → Replies → ReplyHistory → Reader and Home | A03, A05, G01. Temp-history probes covered the caps and tie. |
| Voice work | Runtime task or named model → downloads, player, cache | VoicesPage / Runtime / PlayerView → VoiceServer → ModelDownloads and ModelCache | A01, A02, A07, D02, U01. Error and directory probes covered data ownership and lifecycle. |
| Shared Claude module | Default or alternate login settings → installed shared mod | IntegrationFiles / Connections → packaged commands and runtime handlers | H01 confirmed. H02 missing packaging rejected by extraction and native validation. |
| Cached Codex definition | CLI path → generated files and approval state | CodexPlugin → Codex CLI/cache → IntegrationFiles.status | H05 byte drift ruled out. I-12 live hash readiness remains open. |
| Release and updater | Tag, ZIP digest, bundle plist and signature → platform install and app relaunch | Draft metadata / build-app.sh → Release / Updater → Foundation / LaunchServices | U02/U04/U05/U08/U17/U24. Exact archive verification and a cross-volume test; native full relaunch remains open. |
| Capture consent and playback | Lower-other-audio preference and Reader phase → audio tap | AppDelegate → OtherAudioDucking → OtherAudioLowerer → Core Audio | D03/D05/D06/D07/D08/D09/D12. Checked state and adapter ownership. Real devices can settle format and callback behavior. |

## Candidate dispositions and contract coverage

### PR #1 · App, queue and voice

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| A01 | Cancelling downloads deletes data present before Readback started fetching. | `SpeechMakers.swift:418–424` | **Confirmed · #1**. Older revision lost in the cache probe. |
| A02 | Logs cannot open and the progress state is left spinning after the job exits. | `SpeechMakers.swift:381–414`, `AppDelegate.swift:210–216` | **Confirmed · #1**. Active state reproduced after production adapter failure. |
| A03 | HTTP acknowledges receipt even when the only saved copy fails. | `Replies.swift:75–87`, `AppDelegate.swift:318–324`, `HistoryPages.swift:154,201–215` | **Pre-existing**. Base also acknowledged memory receipt before durability. |
| A04 | Two consecutive replies with the same text collapse to one even after the new-turn hook. | `ReplyQueue.swift:75–92`, `AppDelegate.swift:257–265` | **Confirmed · #1**. Two valid deliveries become one row in production queue. |
| A05 | A failed queued reply can no longer be replayed. | `ReplyQueue.swift:137–148`, `ReplyHistory.swift:70–75,120–123`, `AppDelegate.swift:253–255`, `ReplyQueue.swift:125–129` | **Confirmed · #1**. Base retained the active row. Head drops it before the failure callback. |
| A06 | Newly visible Cancel can mark a task yet fail to stop it until the download completes. | `SpeechMakers.swift:383,401–406` | **Plausible**. Controlled scheduler or on-device early Cancel can settle the registration window. |
| A07 | The floating player's new Cancel stops an unrelated download. | `PlayerView.swift:89–101`, `PlayerPanel.swift:43`, `AppDelegate.swift:220–221` | **Confirmed · #1**. Global model and reader state never share an operation identity. |
| A08 | Retrying failed removal and an Install can overlap against the same engine directory. | `Runtime.swift:252–276`, `AppDelegate.swift:345–356` | **Plausible**. Exercise failed removal retry against normal install in a temp runtime to confirm overlap. |
| A09 | Closing or replacing a reading still starts and warms its model after the work is already obsolete. | `Reader.swift:94–113,127–129`, `SpeechMakers.swift:183–193` | **Plausible**. Stop the reader during model prep and trace actual server startup against both revisions. |
| A10 | Completeness uses metadata and byte counts from potentially different revisions, and model checks repeatedly read the entire snapshot on the main actor. | `ModelCache.swift:49–70`, `VoicesPage.swift:401–415`, `ModelDownloads.swift:41–46` | **Plausible**. Slow or replace a fixture snapshot during inventory. Measure UI main-actor cost on a populated cache. |
| A11 | A line containing an escaped pipe after a table is swallowed even though it is ordinary text. | `SpeechText.swift:108–118` | **Plausible**. Compare a pipe-bearing Markdown block after a table against the parser contract. |
| A12 | Valid fenced code under quotes or lists can leak into text or remove following prose. | `SpeechText.swift:17–28,80–98` | **Pre-existing**. Prior implementation already lacked nested tilde fence support. |
| A13 | Retry ownership is keyed to a model, so stale same-model progress or another attempt can change current meter and failed status. | `ModelDownloads.swift:31–46`, `SpeechMakers.swift:384–387,429–434` | **Plausible**. Inject two ordered attempts and delayed meter callbacks through the app adapter. |
| A14 | A new reading can start while an idle stop check is suspended, then the old stop still kills its engine. | `AppDelegate.swift:168–183` | **Pre-existing**. Same async stop window in the base. No worsening established. |
| A15 | Accepts model and language while a built-in engine is selected, silently writes future Custom preferences, and reports built-in values. | `AppDelegate.swift:385–414` | **Pre-existing**. Base writes the same future Custom preferences. |
| A16 | A cancelled voice step can show engine Installed despite Kokoro missing, and Setup reports that the voice is ready. | `Runtime.swift:180–192`, `SetupSheet.swift:170–172` | **Plausible**. Cancel in the model stage via each control and compare the onboarding step against actual model readiness. |
| A17 | The new model row can show download succeeded then still offer Download for a healthy newer smaller release. | `VoiceCatalog.swift:35–43,55–68`, `ModelCache.swift:84`, `VoicesPage.swift:401–416` | **Plausible**. Expected bytes are a heuristic already used by the base. Confirm with a real smaller valid revision. |
| A18 | A reading can count the entire reply as heard after starting the player and before decoded audio is heard. | `Reader.swift:240–255`, `AppDelegate.swift:244–249`, `Replies.swift:65–70` | **Pre-existing**. Base counted earlier, before synthesis. No worsening established. |
| A19 | Failure to start Python ends the meter but leaves no failure. | `SpeechMakers.swift:404–414`, `AppDelegate.swift:215` | **Confirmed observation**. Explicit launch catch clears the meter without publishing per-row failure. Merges into A02 fix surface. |
| A20 | A home removed while Setup is running drops out of the progress steps and can turn an unfinished operation into All set. | `SetupSheet.swift:23–25,42–45,136–158,197–203` | **Plausible**. Change a discovered home during Setup and observe the final status. |
| A21 | Picking Play a sample disables the current reply without preserving its playback state; after the sample the queue advances. | `AppDelegate.swift:224–228` | **Pre-existing**. Base starts previews through the same replace-current reading behavior. |
| A22 | Main actor normalizes and tokenizes the same long reply three times before playback. | `AppDelegate.swift:319–324`, `ReplyQueue.swift:138–141`, `Reader.swift:71–73` | **Confirmed observation**. Changed callers independently repeat the transform. Time long replies to measure user impact. |
| A23 | Escape follows settings change while visibility and active status can be transitional. | `PlayerPanel.swift:60–77` | **Plausible**. Native player key registration and visibility transitions remain unverified. |
| A24 | Downloading actor race between task queue insertion and dictionary registration could reorder waits. | `SpeechMakers.swift:350–377` | **Rejected**. Once admitted to the actor queue, downloadInTurn waits on the earlier entry in SpeechMakers.swift:367–377. No caller FIFO contract established. |
| A25 | Runtime installed plus blank Custom model displays an empty model despite using macOS voice. | `AppDelegate.swift:153–162`, `MainWindow.swift:431–442` | **Pre-existing**. Same empty Custom display on the base. |
| A26 | General app/engine errors and paths survive message redaction. | `Reader.swift:109–113`, `SpeechMakers.swift:243–245`, `Runtime.swift:304–311` | **Pre-existing**. Private logs still include engine diagnostics. Raw diagnostics existed before this diff. |
| A27 | Removal waits on the voice child but signals model downloads without waiting for them or suppressing queued tasks. | `Runtime.swift:256–276`, `SpeechMakers.swift:255–266,367–377` | **Plausible**. Stop/remove with one active model and one queued model in an isolated runtime. |
| A28 | A crash before any new edit leaves the restored state marked waiting on disk. | `ReplyQueue.swift:40–46`, `Replies.swift:37,75–82` | **Rejected**. ReplyQueue.swift:40–46 renormalizes every launch. Stale on-disk waiting does not replay. |
| A29 | A cleanup failure may remove some old files and still advertise a normal cancellation and no failure. | `ModelCache.swift:120–127`, `SpeechMakers.swift:420–427` | **Merged**. A01 includes ownership of pre-existing cache and failure during whole-repo cleanup. |
| A30 | Standard real hook timing relies on a marker without an internally persistent per-turn identity. | `ReplyQueue.swift:55–61,75–92,114–120` | **Merged**. A04 covers the missing turn identity with both hooks working. |

#### Contract and lens coverage

| Area | Contract units and their owners | State, side effects and direct callers | Lens references |
|---|---|---|---|
| Queue and foreground audio | `AppDelegate.swift:230–299,314–379`, `ReplyQueue.swift:35–149`, `ReplyHistory.swift:3–141`; restore → receive → dedup → play/keep → stop/advance | ControlServer.handle, ordinary prompt, replay, Player/History cards and Reader phases drive saving and rendering | 1 A04/A05, 2 A22, 3 A04, 4 A04/A28, 5 A04/A05/A30, 6 A03/A05, 7 A05, 8 A04/A30, 9 A05, 10 A03/A05/A28, 11 A03 (private file boundary), 12 A03/A04/A05, 13 A03/A05, 14 A22, 15 A03/A05 |
| History disk and display | `Replies.swift:15–87`, `Log.swift:1–25`, `ReplyHistory.swift:126–140`, `HistoryPages.swift:140–250`; persisted receipt, readable corruption warning and clear/undo | ReadbackPaths support/logs, queue copy on MainActor, PrivateFiles, Card and History error UI | 1 A03, 2 missing history paths and file decode examined, 3 A03, 4 A28, 5 A03, 6 A03/A26, 7 A03, 8 owner-only mode via PrivateFiles, 9 A03/A28, 10 A03/A28, 11 A26, 12 A03, 13 A03/A26, 14 PrivateFiles/Core ownership, 15 A03 |
| Reader and player controls | `Reader.swift:25–287`, `PlayerPanel.swift:32–108,232–245`, `PlayerView.swift:25–165,281–358,580–598`, `AppDelegate.swift:224–228,239–281`; prepare/seek/cue/close, player Cancel, Escape and hide settings | Reads rendered audio and publishes Phase, uses AVPlayer, uses prefs controls and subscriber order, controls independent panel lifecycle | 1 A07/A18, 2 seek end to 0.999 checks, 3 A07, 4 — active playback process state, 5 A09/A14/A18/A21/A23, 6 A05/A18, 7 pause/seek cue-current/run guards, 8 A07, 9 A07/A18/A21/A23, 10 — no persisted playback migration, 11 A26, 12 A07/A18/A23, 13 A07/A18/A21, 14 app only has manual checks, 15 A07/A18 |
| Engine installation/removal | `Runtime.swift:18–127,130–218,220–328`, `AppDelegate.swift:65–72,168–183,345–356,447–455`; update installed receipt, install/cancel, remove/retry/install state | CLI /engine handler, app launch, Setup and Voices mutate runtime/uv receipt/process and read current state | 1 A08/A16, 2 no engine/none package states, 3 A08/A16/A27, 4 A16, 5 A08/A14/A16/A27, 6 A08/A16/A26/A27, 7 A08, 8 OS process ownership/reference, 9 A08/A14/A16, 10 A08/A16, 11 A26, 12 A08/A16, 13 A08/A16, 14 caller scope and runtime state, 15 A16 |
| Model load/synthesis and download actor | `SpeechMakers.swift:139–249,252–325,327–488`, `ModelDownloads.swift:27–62`, `AppDelegate.swift:196–221`; queues and owns model transitions/downloads, progress, failures, cancel | Warm-up, Runtime, sample/current reading, Voices and player call into actor; receipt/generation/server/cache/log side effects | 1 A07/A19, 2 A17/A19, 3 A07/A13, 4 A13/A17, 5 A06/A09/A13/A24/A27, 6 A02/A06/A19/A27/A29, 7 A02/A06/A19, 8 A01/A07, 9 A02/A09/A13, 10 A01/A27/A29, 11 A26, 12 A02/A06/A09/A19/A24, 13 A02/A06/A07/A09, 14 process logic adapter by design but actor races require test seam, 15 A07/A29 |
| Model cache | `ModelCache.swift:14–46,48–105,107–155` plus :158–231 process events/script seam; detect a usable revision and clean complete/partial model | VoiceServer calls cache and script, Voices calls cache repeatedly, reads Hugging Face metadata and symlinks, mutates shared Hugging Face files | 1 A01/A17, 2 A10/A17, 3 A01/A10, 4 A17, 5 A01/A10/A29, 6 A01/A17/A29, 7 A29, 8 A01, 9 A10, 10 A01/A29, 11 A01 (defensive ownership only), 12 A01/A17/A29, 13 A01/A17, 14 A01, 15 A01/A29 |
| Voice controls & plain UI | `VoicesPage.swift:7–52,125–271,352–481`, `MainWindow.swift:142–146,245–350,381–443`, `Surfaces.swift:11`, `ReadingSettings.swift:15–22`; engine and voice row, runtime status, prefs toggles, sidebar hover | Calls AppDelegate, Runtime, ModelCache and Preferences, subscribes to ModelDownloads/Reader/Connections | 1 A07/A25, 2 A25, 3 A07/A16/A25, 4 — view-local hover/layout, 5 A07/A08/A13, 6 A02/A16/A19, 7 A02/A25, 8 A07, 9 A07/A13/A25, 10 — prefs keys remain read at same domain, 11 A01 via Cancel, 12 A07/A16/A25, 13 A07/A25, 14 thin UI adapters, 15 A07/A16/A25 |
| Setup & connection display | `ConnectionSettings.swift:8–138`, `SetupSheet.swift:18–68,84–194,197–215,259–296`, `HistoryPages.swift:29–69`; select tool homes, install/status/approval, proof and next steps | Reads Connections, model download, Runtime and History; UI poll and action callbacks drive updates; connection writers separately owned | 1 A20, 2 no tools/no rows checked, 3 A16/A20, 4 approval polling reads live data, 5 A20, 6 A16/A20, 7 A20, 8 home status delegated to ConnectionFiles, 9 A16/A20, 10 — no persisted setup data schema changed in this slice, 11 actual mutation reviewed by other finder, 12 A16/A20, 13 A16/A20, 14 same ToolHome vocabulary, 15 A16/A20 |
| Clean/chunk/voice value transforms | `SpeechText.swift:7–157`, `VoiceCatalog.swift:87–104`, `Preferences.swift:30–75,89–108`, `AppDelegate.swift:385–414`; transform Markdown, validate engine voice, store per-tool switches | Reply preview, queue, reader, CLI/HTTP voice operation; UserDefaults via ReadingSwitches, SystemVoice list | 1 A11/A15, 2 A11/A12, 3 A15/A22, 4 — transforms themselves pure, 5 A22 via main actor, 6 unknown voice handled before writes, 7 A11/A12, 8 tool scope via ReadingSwitches, 9 A22, 10 preferences key compatibility, 11 speech content remains local, 12 A11/A12/A22, 13 A11/A12/A15, 14 A22, 15 A15 |
| Regression seams | `ControlAndQueueTests.swift:95–216,359–386,461–489,620–636,674–730,763–835`; `ModelCacheTests.swift:8–168`; `ReadbackCoreTests.swift:105–137`; `ReplyHistoryTests.swift:65–106` | Tests produce deterministic queue/time/voice/cache fixtures; app and live engine/process excluded from Core target | 1 A04/A05, 2 A11/A12/A17, 3 A01/A04, 4 A04/A28, 5 A04/A05/A06/A24, 6 A02/A03/A05/A19, 7 A05/A11/A19, 8 A01/A07, 9 A07/A23, 10 A01/A03, 11 owner-only modes covered, 12 A01/A04/A05/A06/A07/A16/A19, 13 A01/A04/A07, 14 Core-only target, 15 A03/A05/A07 |

### PR #1 · Integrations and protocol

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| I-01 | The new command route does not authenticate a local caller. Similar session/replay operations existed in the base. | Dispatch and AppDelegate command | **Confirmed · #1**. Newly introduced command handler. Existing trust limitation recorded separately. |
| I-02 | Removal script retains the app when engine removal fails but continues after an integration fails to disconnect and omits Orca/custom homes altogether. | Removal contract and CLI | **Pre-existing**. Base uninstall sequence already ignored disconnect failure. New shell chain correctly gates removal on engine exit. |
| I-03 | Later read-back is no freshness guard. Replacing with an earlier transformation can lose an intervening edit. | JSON read, backup and replace | **Pre-existing**. The later read does not compare the original document and the base also had an unlocked read/modify/write. |
| I-04 | Reconnect rewrites a byte-for-byte unchanged owned plugin. | OpenCode Connect | **Pre-existing**. Base also atomically rewrote the generated OpenCode file on a repeat connect. |
| I-05 | PR #1 changes Claude hook bytes/wire behavior without bumping mod version. PR #2 bumps to 0.3.0. | Claude bundle version | **Confirmed observation**. Standalone Claude plugin bytes change under the 0.4 app version. #2 bumps the plugin manifest. |
| I-06 | New fixed byte window can lose Claude's latest readable short assistant text despite falling inside the old 400-record scan. | HookPayload transcript fallback | **Plausible**. Shortened fallback window is clear. A real Claude transcript with the needed record outside that window would settle user impact. |
| I-07 | Failure to enumerate bundle resources produces an empty list and vacuously reports the mod present. | Claude mod presence/status | **Confirmed observation**. Vacuous allSatisfy can accept an empty bundle resource tree. Actual signed release contains the required files. |
| I-08 | Successful file/child calls result in an unconditional Connected line even when computed status says incomplete/stale or throws. | CLI connection report | **Confirmed observation**. CLI reports mutation success without checking postcondition. No live Codex install failure exercised. |
| I-09 | Old Codex CLI's read breaks against new app, and new clients' command breaks against the old service. | Mixed-version replay | **Confirmed · #1**. Old /replay was removed while the health check does not negotiate protocol version. |
| I-10 | Connection state closure captures the same connection strongly. Depending on Network.framework teardown, completed connections could retain a state callback cycle after deadline closure expires. | Connection deadline, resource retention | **Plausible**. See whether Network.framework releases the callback after connection cancellation with native allocations. |
| I-11 | Shared port reader accepts zero, the Network framework's unspecified-port value, while clients and Host validation expect literal 0. | CLI health and socket config | **Plausible**. Check port-zero binding on the supported OS. Invalid configuration outside documented launches. |
| I-12 | Hook approval can appear current after a change because approval is parsed by field existence. | Config trust scanner | **Pre-existing**. Field-presence check existed on base. An actual Codex approval test would resolve live impact. |
| I-13 | A customized OpenCode plugin that retains marker and CLI assignment is treated as wholly owned. | OpenCode ownership | **Pre-existing**. Base accepted weaker ownership and replaced any existing plugin. No regression established. |
| I-14 | No explicit Readback backup around Codex's changes to config.toml. | Codex backup and disconnect | **Pre-existing**. Codex child made config registration edits on base and head. No extra backup guarantee verified. |
| I-15 | Disabled plugin or failed half-connect can leave marketplace/registration behind with no supported remove action. | Codex connect/disconnect state | **Plausible**. Inject a half-completed install or disabled plugin with live Codex in a disposable home. |
| I-16 | Cache lookup finds the greatest entry before checking whether it has hooks, hiding a lower valid copy behind a partial or unrelated entry. | Codex current cache selection | **Plausible**. Construct cache layout with an incomplete higher version and inspect which Codex actually loads. |
| I-17 | Version/install subprocess timeout does not necessarily bound fallback discovery or child mutation. | Login shell / Codex subprocess lifecycle | **Plausible**. Compare discovery process timeout with a long shell initialization and a stuck child in an isolated home. |
| I-18 | New strict AutoRequest enum no longer accepts formerly normalized spellings, and manual clients must send JSON for bodyless actions. | HTTP shapes and scalar types | **Confirmed observation**. Direct API shape is stricter. Bundled callers emit canonical JSON and use normalized tool names. |
| I-19 | JSON encoding failure becomes a success-status response with {}; clients use fallback Off or Unknown or terminate wait early. | HTTP response encoding / CLI failure | **Plausible**. Normal payloads use encodable primitive types. A production encoder failure input was not established. |
| I-20 | Hand-off failure stays exit 0 for hooks, and best-effort stop double-probes health before sending. | Hook Stop/read failure | **Pre-existing**. Old hook also returned success after an asynchronous handoff failure. Docs describe best effort. |
| I-21 | Hooks/status treat any exact command shape as internal regardless of enclosing custom matcher; settings transform may replace structurally invalid non-object hooks or root. | Claude config path and exact ownership | **Plausible**. Represent a nested custom matcher or wrong-shape settings in a temp home and check ownership expectations. |
| I-22 | Shared named staging and remove/move can leave no active mod on cross-process collision, and bundled subset does not remove obsolete installed module files. | Claude copy staging and comparison | **Plausible**. Force two simultaneous manual/launch plugin copies in a scratch home and record each filesystem result. |
| I-23 | Queue and persistent switch state use bare session string without tool or home. API permits empty for speak and nil for read; exact distinct tool callers prevent common collisions only by producer IDs. | CLI tenancy / session identity | **Plausible**. No collision from supported producers demonstrated across tools/homes. Identity review remains open. |
| I-24 | Existing broad log files are narrowed only when each file is written, and ignored chmod results mean failure to narrow may go unnoticed. | PrivateFiles old logs | **Pre-existing**. Old broader file mode persists until its file is handled. This diff improves ordinary new writes. |
| I-25 | CLI log opens and seeks separately, then writes without O_APPEND or cross-process locking. | Private log writes | **Plausible**. Test concurrent log entries through real CLI processes in a scratch home. |
| I-26 | Helper initializer only checks app suffix after stripping three components, so a wrongly located executable is accepted and integration generates a different helper path. | AppBundle helper resolution | **Rejected**. Current packaged caller uses Contents/Helpers/readback in build-app.sh and AppBundle.swift. Unsupported location needed. |
| I-27 | Unconditional first-line discard loses an exact-aligned valid row; on seek failure or concurrent growth readToEnd is not a strict 2 MB bound. | Transcript tail correctness and budget | **Plausible**. Isolated large-file boundary and concurrent append fixtures can quantify reach and result. |
| I-28 | Intake blocks outside deadline checks; absolute timing comment overstates guarantees. | New typed hook deadlines | **Plausible**. Use a benign open but unsent stdin to characterize deadline behavior. |
| I-29 | CLI/server round trip builds request manually. Claude fixture JSON/Host behavior and command dispatch use stubbed transport; type cast avoids checking real header representation. | Test seam and fixture | **Confirmed observation**. Fixture verifies constructed requests. A fixture cast and mock do not verify the native client's header shape or full routing. |
| I-30 | Setup can remain Connecting / Setting up indefinitely after successful work that status says incomplete or stale. If a selected row becomes working before pressing Setup, stale chosen state can reinstall it. | Setup / connection row after partial connect | **Plausible**. Native Setup with a successful connect returning incomplete or stale would settle the stuck-row case. |
| I-31 | Enqueue-to-actor deadline cannot report late queued work before response to shorter client or enforce total handler bound; four-second prompt hooks can already have given up when server considers request timely. | Live NS/AppKit transport | **Plausible**. Control stream and actor timing under load were reviewed statically. No socket pressure probe was run. |
| I-32 | Events arrive asynchronously and do not supply turn identifier; stale idle results can land after the next busy. Generated plugin is still V1-only. | OpenCode busy/idle emitter | **Pre-existing**. Unchanged OpenCode 1.x compatibility limitation plus possible ordering among existing asynchronous events. |
| I-33 | Normal app startup only refreshes copied mod if default Claude home has connections; a machine only connected through CLAUDE_CONFIG_DIR retains old custom copy on update. | Claude version migration across config homes | **Merged**. H01 carries the release-specific trigger and scratch proof. |
| I-34 | JSON cast in Claude mod accepts arrays/scalars and reachApp tests only truthiness of /health, not identity/schema. | Unstructured network payload boundaries | **Pre-existing**. Unauthenticated health presence was already trusted on the base. No harmful JSON shape demonstrated against expected hosts. |

#### Contract and lens coverage

| Units and code | Promise, state and side effects | Direct callers or producers found with grep | Candidate IDs | N/A |
|---|---|---|---|---|
| ReadbackPaths initialization, alternate directories, ToolHome identity and homes discovery (Core/IntegrationFiles.swift:3–102,144–160) | Resolve an isolated home or environment, enumerate installed homes. Reads env and folder presence. | App/Connections.swift:33–48, CLI:168–170,316–345, Core/Codex.swift:385–390 | I-23, I-33 | 9 for path value functions |
| JSON read/write and backups (Core/IntegrationFiles.swift:370–403) | Read strict JSON, preserve untouched settings bytes and backup, atomically write changed properties. | Core/IntegrationFiles.swift:175–177,195–197,273,303,308,356–359 | I-03, I-14, I-21 | 9 |
| HookCommand argument mapping, shell escaping/recognition, JSON addition/removal, Claude extension env and hook status (Core/Integrations.swift:36–243) | Recognize generated commands, transform tool-specific hooks, classify completeness, keep foreign entries. | Core/Codex.swift:23–25,152; Core/IntegrationFiles.swift:176,196,214,303,308,357–359; OpenCode generator:251,287–289 | I-13, I-21, I-30 | 9 |
| Claude connect/disconnect, status, bundled enumeration and module staging (Core/IntegrationFiles.swift:170–177,191–197,208–262) | Connect settings to copied module, remove recognized settings, check presence, refresh bytes. Touches shared per-home support and Claude settings. | App/Connections.swift:64–69,97–109; CLI:319–323; Core/AppBundle.swift:33–35; build-app.sh:30–33 | I-03, I-05, I-07, I-21, I-22, I-30, I-33 | None |
| Codex connect/disconnect, repair for shared cache, status, cache lookup and source writes (Core/IntegrationFiles.swift:264–359) | Install/remove native plugin after inspecting settings, repair other active homes, classify approval/cache. | App/Connections.swift:33–37,64–69; CLI:316–345; Core/Codex.swift:23–87,125–170,361–371; Tests/CodexTests.swift:127–357 | I-03, I-08, I-12, I-14–I-16, I-30 | None |
| OpenCode plugin connect, disconnect, file status, ownership and JS generation (Core/IntegrationFiles.swift:180–188,200–204,364–368; Core/Integrations.swift:245–306) | Recognize generated plugin, guard unrelated file, write JavaScript, route idle and busy through CLI. | App/Connections.swift:64–69; CLI:316–345; OpenCode app event interface at generated JS:274–289 | I-04, I-13, I-20, I-32 | None |
| CodexPlugin generated files, hook approval/enabled parsers and PromptCommand parsing/near-miss (Core/Codex.swift:10–222) | Stable versioned files, read-only enable/approve status, decide which exact prompt is local command. | Core/IntegrationFiles.swift:275–293,304–345; CLI:240–261; Tests/CodexTests.swift:34–126 | I-09, I-12, I-29 | 9 for pure files/parser |
| Collected and CodexCLI version/discovery/run/output (Core/Codex.swift:224–440) | Find readable and supported Codex, collect native process output, bound the direct child lifetime. | Core/AppBundle.swift:33–35; Core/IntegrationFiles.swift:274–294; Core/Codex.swift:361–371; Tests/ControlAndQueueTests.swift:413,604,747 | I-14, I-17, I-25 | 10 |
| ReadbackApp constants and AppBundle composition (Core/ControlProtocol.swift:3–13, Core/AppBundle.swift:3–37) | Derive app bundle, executable and integration asset URLs, share port. | App/Connections.swift:33–37, App/Runtime.swift uv use, App/ControlServer.swift:8,17–25, CLI:31,104–105,168–170 and fallback in ensureApp | I-07, I-09, I-11, I-26 | 9 for bundle value functions |
| PrivateFiles permissions/atomic write and LogFile append (Core/AppBundle.swift:39–90, App/Log.swift:5–25) | Private files from creation, migration for existing logs, persist history/log updates. | App/Log.swift:18–23, CLI:38–45, Core/ReplyHistory.swift save, App/SpeechMakers.swift log file | I-24, I-25 | 9 for pure helpers |
| Request structs and Health/CommandReply encoders (Core/ControlProtocol.swift:17–197) | Typed body mapping and null session response, success/status shape. | CLI:144–150,211–299; App/AppDelegate.swift:314–379,417–433; Claude register.tsx:83–106 | I-09, I-18, I-19, I-23, I-29 | 9 for pure encoders |
| HTTPRequest parser and HTTPResponse format/encoding (Core/HTTPRequest.swift:5–74) | Separate bounded frame, generate close-delimited JSON response. | App/ControlServer.swift:63–107; tests framing at ControlAndQueueTests.swift:396 | I-18, I-19, I-29, I-31 | 4, 10 for stateless parser |
| ControlRequest parse, decode helpers, per-route table and CommandAnswer (Core/ControlProtocol.swift:199–303) | Guard local host, exact media type and endpoint verb, typed actions and text replies. | App/ControlServer.swift:82–98; App/AppDelegate.swift:314–379; CLI:190–308; Claude register.tsx:22–35,83–106 | I-01, I-09, I-11, I-18–I-20, I-23, I-29, I-31 | 9 for parser and answer helpers |
| Server start/accept/receive/send (App/ControlServer.swift:7–110) | Bind a local listener, cap active connections, dispatch parsed requests to app, close socket. | App/AppDelegate.swift launch and handle:314–379; listener connects CLI, Claude, OpenCode via CLI | I-01, I-10, I-11, I-18–I-20, I-29, I-31, I-34 | 10 |
| HookPayload parse, transcript selection/tail, background guard, StopRequest/speakRequest adapters (Core/HookPayload.swift:5–124) | Interpret hook input and transcript fallback, keep stop scoped, produce shared request types. | CLI:134–150,190–208,225–261; Core/Integrations.swift:276–289; tests ControlAndQueueTests.swift:221–226,404,438–449,706,781–835 | I-06, I-20, I-23, I-27–I-29, I-32 | 9 for parser helpers |
| ReadingSwitches and App preference adapters (Core/ReadingSwitches.swift:6–47) | Shared defaults keys, bounded session list, per-tool auto switches, cheap hook read. | CLI:207, App/Preferences.swift:54–77, App/AppDelegate.swift:322–339,361–373; ControlAndQueueTests.swift:202 | I-20, I-23 | 9 for value wrapper |
| CLI transport, app discovery/start, stdin helpers, deadlines, status commands and dispatch (CLI:31–352) | Resolve app, supervise local HTTP, honor platform command exit and output conventions. | Claude and Codex configured hooks from Core/Integrations.swift:176–179 and Core/Codex.swift:24–25; OpenCode generated JS; AGENT-SETUP.md | I-02, I-08–I-09, I-11, I-18–I-20, I-23, I-25–I-29, I-31 | None |
| Claude mod session state, HTTP, launch, command, view/Stop (integrations/claude-code/readback/hooks/register.tsx:16–124) | Read current tool/session, offer read/speak and local Stop, render indicator only for matching active session. | Claude runtime's session.start, command.run and ui.render contracts; commands.test.ts:16–34,48–111; target Core/ControlProtocol.swift | I-01, I-05, I-09, I-18, I-23, I-29, I-33–I-34 | None |
| Connections.view state, refresh, queueing, disconnection actions and setup progress (App/Connections.swift:5–111, App/Window/ConnectionSettings.swift:4–143, App/Window/SetupSheet.swift:18–298, Home count via HistoryPages.swift:63) | Refresh status, run background actor-separated setup changes, report truthful readiness/approval/progress. | App/AppDelegate.swift launch; SetupSheet, Connections page and Home; Core/IntegrationFiles status/connect/disconnect | I-07–I-08, I-12, I-15–I-16, I-22–I-23, I-30, I-33 | None |
| Build staging, mod version, helper paths, docs/script output (scripts/build-app.sh:13–33,45–48,72–85, plugin manifest, AGENT-SETUP.md:49–81,116–129, docs/DEVELOPMENT.md) | Ship expected bundle assets and use documented command/permission path for setup and removal. | Core/AppBundle.swift:8–35, Core/IntegrationFiles.swift:240–260, CLI:168–170,316–345, release step | I-02, I-05, I-07–I-09, I-14, I-26, I-29, I-33 | 9 for written artifact |
| Changed Swift and Claude tests (ControlAndQueueTests.swift, CodexTests.swift, integrations/claude-code/readback/tests/commands.test.ts) | Pin wire framing/commands, config preservation, status and permissions using scratch input. | Swift test target and Claude host fixture runner; cross-reference production builders in each row above | I-07, I-10, I-12, I-16–I-17, I-19, I-27–I-29, I-31, I-34 | None |

### PR #2 · Release and updater

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| U01 | Install can quit after another operation starts | `Updater.swift:31,39,90–99,199`, `AppDelegate.swift:65–70`, `MainWindow.swift:176–183`, `UpdatesTests.swift:208–219` | **Confirmed · #2**. Code follows click-time predicate to an unconditional post-await swap. |
| U02 | A strictly signed newer bundle can be unusable on the installing Mac or lack the hook helper | `Updates.swift:97–100`, `Updater.swift:152–158,181–199`, `build-app.sh:19–27,58–63`, `AppBundle.swift:8–11,25–29`, `UpdatesTests.swift:65–78` | **Confirmed · #2**. Compatibility is absent in actual preflight. Combined with U04 launch recovery. |
| U03 | User guide overstates what is independently authenticated | `Updater.swift:145–158`, `build-app.sh:73–76`, `docs/README-for-friends.md:64`, `docs/superpowers/specs/2026-11-26-update-check-design.md:28` | **Confirmed observation**. GitHub trust assumption is explicit in update spec §Approaches. User guide overstates independent authenticity. |
| U04 | Successful swap can leave the app closed with no recovery or user-visible result | `Updater.swift:177–199`, `Updates.swift:105–109` | **Merged**. U02 covers post-swap launch failure and old-app recovery. |
| U05 | Writable app on a separate volume is offered an install that always fails | `Updater.swift:77–86,92–98,181–184` | **Confirmed · #2**. Cross-volume error reproduced through Foundation. |
| U06 | Replace error can report the old app is untouched without checking its original path | `Updater.swift:181–185,104–107`, `Updates.swift:145–146,169–173` | **Plausible**. Apple documents a relocatable original on error. This probe kept the old item in place. |
| U07 | Active engine removal is omitted from busy detection, and app rows cover only app operations | `AppDelegate.swift:65–70`, `VersionCard.swift:105–110`, `Runtime.swift:247–275`, `Connections.swift:74–94` | **Merged**. U01 also covers engine removal and the scope of the gate. |
| U08 | Release tag and selected app version can disagree | `Updates.swift:36–56,68–76,97–100,253–265`, `Updater.swift:144–156`, `UpdatesTests.swift:47–54,65–71` | **Merged**. U02 includes manifest mismatch reproduced through production Core. |
| U09 | Sources-run app can see Up to date rather than the documented can't-update card | `AppDelegate.swift:620`, `Updates.swift:74–76` | **Confirmed observation**. Core probe confirmed that a normal release compares older than dev. Dev app can show up to date without the intended card. |
| U10 | A permanently failing or outdated release cannot be dismissed or fetched afresh | `Updates.swift:243–250,269–275,306–309`, `VersionCard.swift:48–64,91–102`, `MainWindow.swift:92,116–120` | **Confirmed · #2**. Corrected metadata cannot be fetched after install failure in a production Core probe. |
| U11 | Cancel followed immediately by Retry can let first run mutate the second run | `Updater.swift:39–43,95–111,116–129`, `Updates.swift:280–303`, `UpdatesTests.swift:221–230` | **Plausible**. Force a non-cancellation completion after retry to exercise attempt ownership. |
| U12 | An uncleared quarantine flag can be ignored even when the flag is the reason for relaunch failure | `Updater.swift:156–159,207–215`, `docs/superpowers/specs/2026-11-26-update-check-design.md:22,56–64` | **Plausible**. Repeat installation on a scratch bundle with an attribute that cannot be cleared and check launch behavior. |
| U13 | Permission ask can be based on unrelated or stale marker | `Updater.swift:16,177–185,224–228`, `OtherAudioLowerer.swift:73–77` | **Plausible**. Interrupt before the swap or open a second copy with the same defaults and inspect marker consumption. |
| U14 | Disabled Try again gives no reason | `VersionCard.swift:48–57,91–110`, `AppDelegate.swift:65–70` | **Confirmed observation**. Failed card disables retry while busy but only Available displays the wait reason. |
| U15 | Missing digest still downloads the full archive, and bytes/expanded size have no enforced bound | `Updates.swift:39–56,269–275`, `Updater.swift:95–98,117–134,145–149` | **Confirmed observation**. No-digest asset downloads before digest refusal. Actual draft has a matching digest. |
| U16 | New updater logs absolute install path, which can contain personal info | `Updater.swift:91,105–110,186`, `Log.swift:13–20` | **Confirmed · #2**. Raw install path reaches private file log. |
| U17 | Shipping package may be unusable on a documented supported Intel system | `build-app.sh:19–27`, `README.md:9`, `AGENT-SETUP.md:14–15` | **Pre-existing**. Both actual v0.4.0 and v0.5.0 archives are arm64-only. #3 separately records the release gap. |
| U18 | Broader rsync can publish local plugin working files | `build-app.sh:30–33`, `IntegrationFiles.swift:227–249` | **Rejected**. Ships a broad plugin copy by design. Draft and clean build resource trees matched and no extra plugin input was found. |
| U19 | New error/banner content may be clipped at minimum window or accessibility scale | `VersionCard.swift:33–101,143–152`, `MainWindow.swift:300–336` | **Plausible**. Exercise the long error card with minimum window and accessibility text/VoiceOver. |
| U20 | Friend guide's promise about all future Codex updates is unconditional | `docs/README-for-friends.md:64`, `AGENTS.md:18`, `AppDelegate.swift:63`, `Connections.swift:97–109` | **Confirmed observation**. Future-hook assurance is broader than the approval rule. Current generated bytes equal the base. |
| U21 | PR conflates inability to exercise full future published-version install with ability to test live check today | `Updater.swift:56–79` | **Confirmed observation**. Live GitHub metadata already verified independently of a newer published update. |
| U22 | API version comparison is not normalized for numerically equivalent part counts, and malformed semantic forms are accepted | `Updates.swift:68–76`, `UpdatesTests.swift:47–54` | **Rejected**. Supported release instructions require a plain version tag. U08 covers actual tag/bundle mismatch. |
| U23 | Latest checking and card actions are not bounded to intended origin/scheme | `Updates.swift:36–56,64–65`, `Updater.swift:34,56–64,90–95` | **Plausible**. Intentional alternate fixture URL is documented. Production origin path was checked without a vulnerability probe. |
| U24 | Build script acceptance is weaker than updater acceptance | `build-app.sh:73–84`, `Updater.swift:156` | **Confirmed observation**. Build script's own pre-zip signature check is shallower. The verified draft passes the updater's deeper check. |
| U25 | Rejected non-200 asset response may leave URLSession temp file behind | `Updater.swift:128–134,202–204` | **Plausible**. Check cleanup of URLSession-owned files after a normal non-200 test server response. |
| U26 | Wait uses an unbounded poll on a process number, including reuse | `Updates.swift:105–109`, `Updater.swift:188–199` | **Plausible**. Observe relaunch when the process does not terminate promptly. PID reuse not reproduced. |
| U27 | GitHub's eventual retry fate can be mislabeled | `Updates.swift:117–135` | **Rejected**. Update design explicitly pairs 403 and 429 with a busy card. |

#### Contract and lens coverage

| Unit and locations | Promise and state | Side effects and direct callers | Lenses 1–15 |
|---|---|---|---|
| Release data model, parse, version and latest endpoint, Updates.swift:14–76 | GitHub latest JSON, environment, bundle version → parsed candidate | No side effects in Core, Updater.fetch / download, UpdateFlow.checked and Tests | 1 U08/U22/U23, 2 U08/U09/U15/U22/U23, 3 U08/U22, 4 C, 5 C, 6 U08, 7 C, 8 U23, 9 NA no UI state, 10 NA transient metadata, 11 U23, 12 U08/U09/U15/U22/U23, 13 U08, 14 U08/U23, 15 C |
| Hash, bundle path and manifest eligibility, Updates.swift:79–101 | Current and replacement paths, bundle data and file bytes → SHA / replacement eligibility | Reads file for SHA only, Updater.fetch / unpackAndCheck, tests | 1 U02, 2 U02, 3 U08, 4 NA no stored cursor or version, 5 U05, 6 U02/U05, 7 C, 8 C, 9 U02/U05, 10 NA no data schema, 11 U03, 12 U02/U05/U08, 13 U02, 14 U08, 15 C |
| Relaunch arguments and version marker, Updates.swift:103–109 and Updater.swift:177–199,224–228 | Replacement, PID, READBACK_* and defaults marker → swap, old process quit, or ask OS on new process | FileManager, defaults, shell/open, NSApp, AppDelegate.applicationDidFinishLaunching and Updater.download | 1 U02/U04, 2 C, 3 C, 4 U13/U26, 5 U01/U04/U05/U13/U26, 6 U04/U06/U13/U26, 7 U04/U06/U26, 8 U13, 9 U02/U04/U05/U06/U13/U26, 10 U06/U13, 11 U16, 12 U04/U06/U13, 13 U01/U04/U06, 14 U16, 15 U04/U06 |
| Failure and wait types, Updates.swift:113–209 | Underlying failure/busy statuses → task eligibility and messages | No direct side effects; Updater, VersionCard wait and Tests | 1 U07, 2 C, 3 U07/U14, 4 U27, 5 U01/U07, 6 U06/U27, 7 U06/U07/U14/U27, 8 NA no persisted user scope, 9 U14/U27, 10 NA no stored schema, 11 C, 12 U01/U06/U27, 13 U01/U07/U27, 14 C, 15 U06/U27 |
| UpdateFlow state transitions, Updates.swift:211–314 | User actions and async outcomes → card/effect | Mutates transient state; Updater carries effects, VersionCard renders and Unit tests | 1 U10, 2 U11/U15, 3 U08, 4 U10, 5 U01/U11, 6 C, 7 U10/U11, 8 NA app-global one flow, 9 U10/U11, 10 NA no persistence, 11 U15, 12 U01/U10/U11, 13 U01/U09, 14 C, 15 C |
| Updater fetch/effect/download/meter and watcher, Updater.swift:18–140,202–215,232–241 | Click and update effect → ephemeral HTTP, hashing inputs, progress, cancel and scheduling | Creates tasks, files, logs; called by AppDelegate construction, VersionCard buttons and internal carryOut | 1 U01/U10, 2 U11/U15, 3 U07, 4 U10, 5 U01/U11/U25, 6 U04/U15/U25, 7 U11/U15, 8 C, 9 U01/U10/U11/U25, 10 NA temp workspace, 11 U15/U16/U23, 12 U01/U11/U15/U23, 13 U01/U09, 14 U16, 15 C |
| Unpack, find and check candidate, Updater.swift:142–172 | ZIP hash, staged app identity, integrity and quarantine → eligible app | ditto, plist, codesign, xattr; download runs on detached task | 1 U02/U05, 2 U02, 3 U08, 4 NA no durable state before swap, 5 U05, 6 U02/U12, 7 U12, 8 U03, 9 U02/U12, 10 NA no application-data mutation, 11 U03/U15, 12 U02/U05/U08/U12, 13 U02/U12, 14 U08, 15 U03 |
| AppDelegate update integration, AppDelegate.swift:21–22,56–114; direct calls in MainWindow.swift:300–336 | Runtime/download/config state and post-update marker → update gating and permission effect | Defaults, launcher, CoreAudio through existing owner; application lifecycle and Sidebar | 1 U01/U07, 2 C, 3 U07/U14, 4 U13, 5 U01/U07/U13, 6 U13, 7 U07, 8 U13, 9 U01/U13, 10 U13/U20, 11 C, 12 U01/U13, 13 U01/U07/U20, 14 C, 15 U20 |
| VersionCard and CheckLine, VersionCard.swift:8–183 | Card state and observed busy objects → accessible AppKit/SwiftUI controls | Opens About/releases, starts updater effects; direct Sidebar caller | 1 U14, 2 U19, 3 U14, 4 U10, 5 C, 6 U19, 7 U10/U14/U19, 8 NA no separate identity, 9 U10/U14/U19, 10 NA no persistence, 11 C, 12 U14/U19, 13 U14/U19, 14 C, 15 C |
| UpdatesTests.swift:7–232 | Exercise pure release parsing, checks, sorting, command args, failures and state events | SHA fixture uses temp file, no networking or app launch | 1 U02/U09, 2 U02/U22, 3 U08, 4 U10/U13, 5 U01/U11, 6 U04/U05/U12, 7 U10, 8 U13, 9 U19, 10 NA no schema fixtures, 11 U03/U15, 12 U01/U02/U04/U05/U11/U21, 13 U01/U21, 14 C, 15 U21 |
| Build script, release workflow and published docs, build-app.sh:13–86, docs/DEVELOPMENT.md release section, AGENTS release contract, README.md:9, AGENT-SETUP.md:14–15, README-for-friends.md:60–67 | Host source/binaries → signed archive, consistent supported systems and docs | Packaging writes scratch build folder; release publisher, setup agent, updater, app startup copyPlugin and actual user | 1 U17/U24, 2 C, 3 U20/U24, 4 U20, 5 C, 6 U17/U24, 7 C, 8 U18, 9 U17, 10 U20, 11 U03/U18, 12 U17/U21/U24, 13 U03/U17/U20, 14 U18/U24, 15 U03/U17/U20/U21 |

### PR #2 · Playback and audio

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| D01 | Removing a hash-only chunk can abort the rest of a readable reply. | `SpeechText.swift:39–59`, `SpokenText.swift:57,137–151`, `Reader.swift:98–115`, `SpeechMakers.swift:122–131` | **Plausible**. Empty chunk reached the production synthesis input. Local macOS voice wrote a file. Neural models need checking. |
| D02 | Try again after a model failure clears a working engine and reinstalls the packages. | `Runtime.swift:180–192`, `EngineInstall.swift:3–9`, `EngineInstallTests.swift:7–16` | **Confirmed · #2**. Actual bundled uv clears the scratch venv when the new flags are used. |
| D03 | The previous reading leaves music at 30% for the full wait for a slow next reply or model. | `AppDelegate.swift:276–288,291–322`, `OtherAudioDucking.swift:60–73,78–81`, `Reader.swift:177–188` | **Confirmed observation**. A prior lowered state stays lowered through all preparing phases. Code does not bound an unusually long gap. |
| D04 | One zero-size output could force all buffered channels to silence. | `DuckingMix.swift:43–51` | **Plausible**. SDK keeps nominal sizes for disabled streams. Confirm whether real zero-sized output buffers occur. |
| D05 | Switching off leaves broad capture and audio routing active for sixty seconds. | `AppDelegate.swift:79–86,324–326`, `OtherAudioDucking.swift:51–55`, `OtherAudioLowerer.swift:64–68,88–100,115–118` | **Confirmed · #2**. Switch-off uses the enabled-state linger and leaves the tap active. |
| D06 | A reading while the tap's fallback fade is in progress stops teardown and leaves other apps' sound muted during preparation. | `OtherAudioLowerer.swift:88–100` | **Confirmed observation**. Takeover during teardown can cancel the stop while leaving a zero target. Verify audible result on a device. |
| D07 | Some real microphone streams are left enabled in the process tap device. A second, unexpected microphone permission or failure is possible. | `OtherAudioLowerer.swift:169,306–324`, `scripts/build-app.sh:67`, `ReadingSettings.swift:44–47` | **Plausible**. Use duplex hardware with asymmetric stream counts and inspect permission and selected streams. |
| D08 | Preferred stereo is bypassed so other sounds can be lost or heard on different channels on multichannel interfaces. | `OtherAudioLowerer.swift:110–145,233–247`, `DuckingMix.swift:63–75` | **Plausible**. Try a multichannel interface with non-default preferred stereo channels. |
| D09 | Switch stays on despite permission/setup decline. It may request again later during a reply. | `AppDelegate.swift:79–87`, `OtherAudioLowerer.swift:73–78,105–132,171–177` | **Plausible**. Deny permission in a clean OS user and inspect the switch and prompts on a subsequent reading. |
| D10 | Updating can proactively access the permission on relaunch even though Reading says when the switch is flipped. | `AppDelegate.swift:71`, `docs/superpowers/specs/2026-11-26-update-check-design.md:71` | **Rejected**. Re-ask after update is explicitly described by the update design and only runs with the switch on and marker present. |
| D11 | Restoring from device loss leaves a process ID marked running with no working I/O. | `OtherAudioLowerer.swift:38,47–68,205–227` | **Plausible**. Change or remove output device while the tap is active and measure recovery. |
| D12 | The click/cut can occur well before any cue. | `Reader.swift:81–105`, `AppDelegate.swift:291–311`, `PRODUCT.md:37` | **Confirmed observation**. Preparing triggers takeover before synthesis and can precede the cue by an entire model download. |
| D13 | File paths containing spaces in ordinary quoted/inline file names are only partially shortened. | `SpeechText.swift:26`, `SpokenText.swift:21–35` | **Confirmed observation**. Whitespace tokenization handles separate words and cannot always normalize quoted file names with spaces. |
| D14 | Some legitimate hash forms are still read, and literal hex identifiers can disappear. | `SpokenText.swift:57,137–152` | **Confirmed observation**. Hash detection is heuristic and must not be represented as complete lexical recognition. |
| D15 | Full replacement for each rewritten word repeats many allocations on an oversized speech chunk. | `SpeechText.swift:41–59`, `SpokenText.swift:27–32,196–205` | **Plausible**. Measure a large rewritten chunk before claiming user-visible cost. |
| D16 | Test claiming use in the reading path can pass while Reader omits or misapplies the transform. | `SpokenTextTests.swift:89–91`, `Reader.swift:103` | **Confirmed observation**. Rewrite tests exercise a pure wrapper while production Reader rewrites individual chunks. Empty-chunk seam is D01. |
| D17 | Tests prove handlers on injected events but miss actual namespaced command discovery and intercept ordering. | `commands/read.md`, `commands/speak.md`, `register.tsx:67–102`, `commands.test.ts:50–123` | **Merged**. H02 and H03 cover native packaging/discovery and what mocks miss. |
| D18 | New pinned meter displays any shared download as the install's model and an ordinary visual status may continue with wrong model. | `VoicesPage.swift:297–312`, `PlayerView.swift:90–110` | **Confirmed observation**. Pinned setup meter can read a global active download. Contains A07's operation identity issue in another view. |
| D19 | At MB/GB boundary, part can appear ahead of total rendering or same as done; width changes as an unknown/estimated total is revised. | `ModelDownloads.swift:41–46`, `DownloadAmount.swift:19–36` | **Plausible**. Amount can change when the inferred total changes. Verify typical host progress reports. |
| D20 | The public percentage formatter traps on a finite input that cannot be converted to Int after multiplication. | `DownloadAmount.swift:41–43`, `ModelDownloads.swift:14–16`, `ModelCache.swift:204–217` | **Rejected**. No observed caller supplies out-of-range finite fraction. Gate range before supporting arbitrary public inputs. |
| D21 | Reduce Motion keeps driving a visibly sweeping highlight and redraws continuously while playing. | `Waveform.swift:26–35`, `WaveformMotion.swift:27–32` | **Rejected**. Waveform.swift:4–7 expressly keeps the highlight sweep while reducing bar movement. Other G10 animations are separate. |
| D22 | Arrow keys are handled even if selected option is missing, and actual VoiceOver/focus contract lives outside the tested integer helper. | `Segmented.swift:38–44,68–75`, `VoicesPage.swift:87–93` | **Plausible**. Verify on native keyboard and accessibility tree. Core integer rules alone are insufficient. |
| D23 | Connected appearance copy claims a blue state after migration to the explicitly neutral grayscale UI. | `docs/README-for-friends.md:36`, `ConnectionSettings.swift:55–64` | **Merged**. H10 records the shipped visual-doc drift. |

#### Contract and lens coverage

| Area | Units (inputs → outputs, state/side effects and direct callers) | Lens review |
|---|---|---|
| Audio phase and app wiring | `AppDelegate.swift:36–39,71–87,107–113,249–347` maps Reader phases and preference to AppKit tap calls; `OtherAudioDucking.swift:11–82` selects takeover/lower/restore; `Preferences.swift` persists opt-in, `ReadingSettings.swift:43–47` sets it. Driven by reader.play/prepare/stop, a preference toggle, and updater relaunch. | 1 D03/D05/D12, 2 disabled/default checked, 3 D05/D09, 4 D03/D10, 5 D03/D05/D06/D12, 6 D09/D11, 7 D03, 8 D05, 9 D03/D05/D06/D09, 10 new boolean default off, 11 D05/D09/D10, 12 D03/D05/D12, 13 D03/D05/D09/D10/D12, 14 Core step separates from app actions, 15 D05/D09/D10/D12 |
| Core Audio resource lifecycle | `OtherAudioLowerer.swift:24–101,105–227` handles atomic gain, delayed release, audio tap, aggregate device and output listener; `AppDelegate.swift:305–328` sets desired state. Creates and destroys owned audio device/proc resources, watches device changes, forwards no network. | 1 D05/D06/D11, 2 D07/D08, 3 D05/D06/D09/D11, 4 linger D06, 5 D06/D11, 6 D07/D09/D11, 7 D07/D09, 8 D05/D07/D08, 9 D06/D09/D11, 10 — tap is ephemeral, 11 D05/D07/D09, 12 D05/D06/D07/D09/D11, 13 D05/D07/D09, 14 platform adapters have no XCTest target, 15 D05/D07/D12 |
| Real-time buffers and device input selection | `OtherAudioLowerer.swift:229–325`, `DuckingMix.swift:8–82`; buffer list → gain-adjusted channels. AudioDeviceIOBlock provides actual buffers, and SDK distinguishes enabled/disabled streams and preferred stereo pair. | 1 D04/D08, 2 D04/D07/D08, 3 D07/D08, 4 — callback reads current gain in memory only, 5 callback + atomic gain, 6 D04/D07/D08, 7 D04/D07, 8 D07/D08, 9 D11, 10 — no stored audio, 11 D07, 12 D04/D07/D08, 13 D07/D08, 14 renderer in Core, 15 D07/D08 |
| Speech transform and Reader | `SpokenText.swift:8–215` word and whole-string rewrites, `Reader.swift:71–115` passes generated text through the real `SpeechMaker` contract; `SpeechText.swift:39–71` yields cleaned chunks, Speaker writes AVAudioFile or receives local NeuralVoice. | 1 D01/D13/D16, 2 D01/D13/D14/D15, 3 D16, 4 — transform pure, 5 D01/D12, 6 D01/D16, 7 D01/D13/D14, 8 — no auth/identity introduced, 9 D01/D15, 10 — no persisted speech schema changed, 11 no external sending introduced, 12 D01/D13/D14/D16, 13 D01/D13/D14, 14 D15/D16, 15 D13/D14/D16 |
| Engine install, model and progress | `Runtime.swift:105–218`, `EngineInstall.swift:3–9`, `ModelDownloads.swift:7–56`, `DownloadAmount.swift:19–61`, `VoicesPage.swift:23–38,105–115,205–325,399–560`, `SetupSheet.swift:171–193`, player :90–126; builds command, changes runtime footprint and reports install/download status. | 1 D02/D18/D19, 2 D19/D20, 3 D02/D18, 4 D02, 5 D02/D18, 6 D02/D18/D19/D20, 7 D02, 8 D18, 9 D02/D18/D19, 10 D02 deletes working files, 11 original shared cache under PR1, 12 D02/D18/D19/D20, 13 D02/D18/D19, 14 runtime process remains adapter, 15 D02/D18/D19 |
| Player waveform and segmented audio selection | `PlayerView.swift:292–370`, `Waveform.swift:9–50` + `WaveformMotion.swift:8–58`, `Segmented.swift:9–79` + `SegmentStep.swift:2–5`; button actions, keyboard and pos/time → logical transitions/pixels. Voice settings and window/player reuse same helpers. | 1 D21/D22, 2 zero count guarded; app enumerates Delivery, 3 single waveform shared, 4 no persistent motion state, 5 view-local focus change, 6 no async operation introduced in helpers, 7 D22, 8 — no account or device access in animation helpers, 9 D21/D22, 10 — no migration, 11 — no privacy surface in animation, 12 D21/D22, 13 D21/D22, 14 local Controls, 15 D21 |
| Claude command wire and visible names | `ControlProtocol.swift:278–314`, plugin manifest, Markdown, `register.tsx:22–118`, `commands.test.ts:1–123`, `SetupSheet.swift:143–161,263–270`, `ReadingSettings.swift:23–27`, `ConnectionSettings.swift:20,124–149`, `HistoryPages.swift:78–83`, `AppBundle.swift:25–35`, `IntegrationFiles.swift:218–263`; host slash command, session/stop/reply metadata and local HTTP → response; install refresh copies files. | 1 D17, 2 nil/empty with user override examined, 3 names and tool-specific output mapped, 4 migration via plugin byte comparison, 5 D17, 6 fallback D17, 7 no reply/invalid args visible, 8 session taken from tool host, 9 D17, 10 manifest version bumped and bundled files copied, 11 uses prior loopback trust boundary, 12 D17, 13 D17, 14 documentation updated across consumers, 15 D17/D23 |
| Scoped Core tests | `OtherAudioDuckingTests.swift:7–72`, `DuckingMixTests.swift:7–147`, `EngineInstallTests.swift:7–18`, `DownloadAmountTests.swift`, `SpokenTextTests.swift`, `SegmentStepTests.swift`, `WaveformMotionTests.swift`, new command naming test in `ControlAndQueueTests.swift`. Fixtures render typed Core values and manually inject host values. | 1 D16/D17, 2 D04/D20/D22, 3 D05/D16, 4 D02/D10, 5 D03/D06/D17, 6 D01/D02/D05/D07, 7 D01/D05, 8 D07/D08, 9 D03/D05/D21, 10 D02, 11 D05/D07, 12 D01/D02/D03/D05/D07/D08/D16/D17/D20/D22, 13 D03/D05/D12/D17/D21, 14 Core target only, 15 D16/D17 |

### PR #2 · Home, History and custom controls

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| G01 | A session can call an older reply “newest” after restart | `ReplyHistory.swift:65–67,130–140`, `SessionSummary.swift:21–26`, `Home/SessionsList.swift:75,100,111`, `SessionSummaryTests.swift:59–71` | **Confirmed · #2**. Save/load probe shows UUID sort can pick older reply as newest. |
| G02 | Waveform remains animated when replying has not started or is paused | `Reader.swift:35–36`, `Home/SessionsList.swift:112–113`, `Components/Waveform.swift:26–34` | **Confirmed observation**. Session animation uses reader.isSpeaking rather than phase.playing. |
| G03 | Tall menus can extend past both visible edges or flip toward the tight edge | `Dropdown.swift:113–124`, `Dropdown.swift:202–214`, `VoicesPage.swift:334–340,376–381` | **Plausible**. Native panel positioning can further constrain requested geometry. Test with the largest voice list on a short display. |
| G04 | Accessibility name hides distinguishing content | `Home/SessionsList.swift:173–197`, `HistoryPages.swift:353–355` | **Confirmed observation**. Explicit generic labels discard distinctive child text from the exposed label. Native AX traversal still pending. |
| G05 | A tool that is still connecting is shown as already connected | `Connections.swift:74–83`, `Home/SetupChips.swift:98–106`, `ConnectionSettings.swift:117–120` | **Confirmed · #2**. Busy branch of setup resolver shares its result with connected. |
| G06 | The Now card still disappears during automatic queue handoff | `Home/NowCard.swift:31–41`, `AppDelegate.swift:276–280,358–364` | **Confirmed observation**. Normal 800 ms queue handoff exceeds 600 ms hide threshold. |
| G07 | Now’s Play button pauses pending playback, without a reflected state change | `NowCard.swift:68,205–218`, `Reader.swift:87–88,189–190` | **Confirmed observation**. Buffering Play label gives the opposite of the first playback-intent action. |
| G08 | Position control has no Tab/arrow keyboard path | `Home/NowCard.swift:240–272` | **Confirmed observation**. The scrubber exposes pointer and accessibility adjustments without a keyboard-only focus/action path. |
| G09 | Global player Escape competes with local Escape handling | `PlayerPanel.swift:52,159,406–427`, `Dropdown.swift:257`, `SearchField.swift:34–38` | **Plausible**. With floating player visible, press Escape in a dropdown/search field. Inspect Carbon versus key event behavior. |
| G10 | Geometry changes still animate with Reduce Motion | `Segmented.swift:51–62,75`, `Switch.swift:22–40`, `NowCard.swift:54–59`, `SessionsList.swift:24–37,65`, `Motion.swift:10–23` | **Confirmed observation**. Switch, segmented thumb and stack layout still animate geometry under Reduce Motion. |
| G11 | History still uses the old waveform, unlike other playing surfaces | `HistoryPages.swift:389–394`, `Waveform.swift:4–8` | **Rejected**. Spec scope lists the player, Home and sidebar. History row parity was not required. |
| G12 | Nonempty session IDs across tools share one unnamespaced history key | `SessionSummary.swift:21,35–37`, `ReplyFilter.swift:24–28`, `Integrations.swift:277–287`, `HookPayload.swift:17` | **Plausible**. No cross-tool ID collision from actual producer formats verified. Key lacks namespacing. |
| G13 | Trigger is a generic button and VO focus remains on initial row during custom highlight changes | `Dropdown.swift:45–61,237–244,253–264,293–297` | **Plausible**. Inspect trigger role and selected row movement in the macOS accessibility tree. |
| G14 | Parent content can scroll under a menu that remains at its old screen anchor | `Dropdown.swift:66–75,111–140` | **Plausible**. Scroll the parent or change its geometry while the child panel is key. |
| G15 | Home can keep “needs you to approve” after approval | `Connections.swift:44–61`, `MainWindow.swift:100–108`, `ConnectionSettings.swift:24–29`, `HistoryPages.swift:23–62` | **Plausible**. Return from external approval with Home still visible and observe which refresh callbacks actually run. |
| G16 | Keyboard ring depends on delivery timing of focus-change callback | `FocusRing.swift:27–29`, `Home/SessionsList.swift:228`, `Buttons.swift:81,102` | **Plausible**. Verify keyboard focus rings at minimum window size with focus arriving from Tab and programmatic navigation. |
| G17 | Up/Down stops doing anything when About selected | `MainWindow.swift:297–318` | **Confirmed observation**. Sidebar's custom arrow handler has no About in its order and exits when selection is About. |
| G18 | “Connect”/“Fix”/“Update” labels promise actions but trigger generic navigation | `Home/SetupChips.swift:81–107` | **Confirmed observation**. A rest chip leads to Connections even when its visible action label says Connect, Fix or Update. |
| G19 | Removing last only-session reply can show first-run instructions rather than filtered-empty recovery | `HistoryPages.swift:130–139` | **Confirmed observation**. Scoped history can fall through to first-run messaging after removal of the only reply. |
| G20 | Relative times stay at “just now” while idle Home remains open | `Home/ToolMark.swift:59–65`, `Home/SessionsList.swift:148–152,183` | **Plausible**. Let idle Home stay on screen across a relative time threshold. Native body refresh from other state can mask the gap. |
| G21 | Click-dragging off the switch still toggles it or interrupts scrolling rather than canceling | `Switch.swift:41–48` | **Plausible**. Test cancellation and click-drag on real AppKit delivery paths. |
| G22 | New window movement can reject legal drags when crossing displays or a display with separate Spaces | `SelfDraggingWindow.swift:29–55` | **Plausible**. Verify on multiple displays and separate Spaces on macOS 27.2. |
| G23 | Folded queue rows remain keyboard focusable though they are visually unavailable | `Home/NowCard.swift:115–129` | **Plausible**. Test Tab and Space on the folded queue with full keyboard access. |
| G24 | Several queued replies from one session expose duplicate names to VoiceOver, and mouse users cannot tell contents | `Home/NowCard.swift:168–188` | **Confirmed observation**. Generic queue labels do not distinguish multiple pending replies from a single session. |
| G25 | Long settings content can place a chip outside the page | `ToolMark.swift:83`, `SetupChips.swift:73–79,160–198` | **Confirmed observation**. Intrinsic chip measurement lacks a width cap for a long custom label. Verify presentation at minimum window. |
| G26 | Spoken progress can disagree with clamped drawn progress | `Meter.swift:21–25,43`, `VersionCard.swift:65–70` | **Confirmed observation**. Visual progress clamps while accessibility formats the original fraction. Native producer bounds still matter. |
| G27 | Missing selected option produces blank button and no first highlight | `VoicesPage.swift:335–340,376–381`, `Dropdown.swift:40–41,69–75`, `MenuNavigation.swift:16–18`, `ToolMark.swift:78` | **Plausible**. Supply an unavailable saved voice to the real dropdown and verify empty selection UI. |
| G28 | Held key retains unbounded repeated prefix till idle pause, recopying array for every type | `MenuNavigation.swift:41–54` | **Plausible**. Observe operating system repeats over a long held-key session. User-visible latency unmeasured. |
| G29 | Clicking currently selected History sidebar row leaves its home-derived session filter and hides clearing | `MainWindow.swift:53–67,340–342` | **Confirmed observation**. Activating the selected History row leaves a session filter in place because navigation resets it on a different section only. |
| G30 | Undo window disappears when navigating off History | `HistoryPages.swift:121–122,219–234`, `MainWindow.swift:138` | **Pre-existing**. View-local Undo lifetime existed before the new page transition. |
| G31 | A tool already connected while setup remains open can remain in chosen until clicked | `SetupSheet.swift:55–66,94–104,117–122` | **Merged**. I-30/A20 share setup selection and live status reconciliation. |
| G32 | Minimum-window threshold and unverified native contrast | `Glass.swift:17–39`, `Surfaces.swift:32–54` | **Plausible**. Run light/dark, minimum and expanded sizes with Reduce Motion and accessibility settings. |
| G33 | Newly installed tool absent on Home until status refresh | `Home/SetupChips.swift:65–69` | **Merged**. G15 covers stale Home status and its refresh entry points. |
| G34 | Dedicated Kokoro step and resume/unheard remain missing from committed broad spec | `SetupSheet.swift:40–46,106–112`, `SessionSummary.swift:26` | **Rejected**. Resume, unheard and dedicated Kokoro setup are subsequent pieces in the staged design and absent from the PR scope. |

#### Contract and lens coverage

| Unit | Promise and mutable state | Callers / side effects | Lens coverage |
|---|---|---|---|
| MainWindow, MainView, Navigation, Sidebar, PageHeader, NowPlayingCard | Main section/session routing and page/window layout, window focus | AppDelegate, Home/History and settings, NSWindow activation/focus | 1 G17/G29, 2 G19/G25/G32, 3 G02/G11, 4 G15/G30, 5 G09/G22/G29, 6 G22, 7 G17/G29/G30, 8 G12, 9 G09/G16/G17/G22/G29/G30/G32, 10 NA no data migration, 11 C, 12 G17/G22/G29/G30/G32, 13 G17/G29/G32, 14 C, 15 C |
| SelfDraggingWindow and WindowDragWorkaround | Handling title-bar event sequence only on specified OS thresholds | MainWindowController, AppKit events, NSScreen positioning | 1 G22, 2 G22, 3 C, 4 NA no state beyond drag, 5 G22, 6 G22, 7 C, 8 NA no user data, 9 G22, 10 NA no persistence migration, 11 C, 12 G22, 13 G22, 14 C, 15 C |
| Dropdown schema, trigger, AnchorView, DropdownPresenter, MenuWindow and MenuPanel | Show menu for selected value, place it, update selection from pointer/keyboard, restore focus | History, Reading and Voices; AppKit NSPanel/event APIs, SwiftUI ScrollView | 1 G09/G13/G27, 2 G03/G27/G28, 3 C, 4 NA temporary menu state, 5 G09/G13/G14, 6 G03/G27, 7 G09/G14, 8 C, 9 G03/G09/G13/G14/G27, 10 NA no migration, 11 C, 12 G03/G09/G13/G14/G27/G28, 13 G03/G09/G13/G14, 14 C, 15 C |
| MenuNavigation and MenuNavigationTests | Key event, selected index and monotonic time to highlighted index | Dropdown.MenuPanel only; local state, no platform | 1 G13, 2 G27/G28, 3 C, 4 G28, 5 G13/G28, 6 C, 7 C, 8 NA no data identity, 9 G13, 10 NA no persisted state, 11 C, 12 G13/G28, 13 C, 14 C, 15 C |
| ControlMetrics, ReadbackButtonStyle, IconPlate, KeyboardFocusRing, Hairline, Glass, Motion | Consistent sizes, neutral focus/press/motion and translucent window | All window pages, setup and some PlayerView; environment inputs | 1 G16, 2 G32, 3 G10/G16, 4 NA local focus/placement, 5 G16, 6 C, 7 G16, 8 NA visual controls, 9 G10/G16/G32, 10 NA no migration, 11 C, 12 G16/G32, 13 G10/G16/G32, 14 C, 15 G10 |
| Checkbox/SetupSheet, ReadbackSwitch/SpreadSwitchStyle, Segmented/SegmentStep, SearchField | Mutate right Binding, keyboard and accessibility actions, display state | SetupSheet, Reading/Voices, Home and History, preferences and runtime | 1 G08/G09/G21, 2 C, 3 G10/G16, 4 G31, 5 G09/G16/G21/G31, 6 C, 7 G09/G21/G31, 8 C, 9 G09/G10/G16/G21/G31, 10 NA binding shape unchanged, 11 C, 12 G09/G16/G21/G31, 13 G09/G10/G21, 14 C, 15 G10 |
| Waveform, WaveformMotion and tests, Meter | Playback and download state to bounded appearance and accessibility | PlayerView, MainWindow, NowCard, SessionsList, Versions, Voices, SetupSheet | 1 G02/G26, 2 G26, 3 G02/G11/G26, 4 NA ephemeral, 5 C, 6 G26, 7 C, 8 NA no identity, 9 G02/G11/G26, 10 NA no migration, 11 C, 12 G02/G11/G26, 13 G02/G11, 14 C, 15 G02/G11 |
| HomePage, EmptyReplies/EmptyCard, NowCard, WaitingRow, PlayPauseButton, LineScrubber | Playing/paused/pending state, waiting stack order and intent, move playback | Reader, Replies, AppDelegate; UI controls call queue/reader | 1 G06/G07/G08/G24, 2 C, 3 G06/G07, 4 NA presentation state except restoration, 5 G06/G07, 6 C, 7 G23, 8 C, 9 G06/G07/G08/G10/G23/G24, 10 NA no data migration, 11 C, 12 G06/G07/G08/G23, 13 G06/G07/G08/G10/G24, 14 G08, 15 G06/G07 |
| SessionsList, SessionRow, SessionReply and UnheardBadge | Group summary to open row, latest and visible replies, playing/unheard semantics | HomePage, Reader, AppDelegate, Navigation | 1 G01/G02/G04, 2 C, 3 G01/G02, 4 G01/G20, 5 G01/G16, 6 C, 7 G04, 8 G12, 9 G02/G04/G10/G16/G20, 10 G01, 11 C, 12 G01/G02/G04/G12, 13 G01/G02/G10/G34, 14 C, 15 G02/G34 |
| SessionSummary and tests, ReplyFilter and tests | Group/identify/filter stored reply with title/tool/search using documented session identity | Home, History, Now and test fixtures; no external side effects | 1 G01/G12, 2 G12, 3 G01/G12, 4 G01, 5 C, 6 C, 7 G12, 8 G12, 9 NA pure Core, 10 G01, 11 C, 12 G01/G12/G34, 13 G01/G12/G34, 14 C, 15 G12/G34 |
| HistoryPage, ReplyCard, SessionChip and older search seam | Search/session filter, clear/undo, card expand/menu | Navigation, Replies, AppDelegate, clipboard and removal; Search/Dropdown | 1 G09/G11/G19/G29, 2 G19, 3 G11/G12, 4 G29/G30, 5 G09/G29, 6 C, 7 G19/G29/G30, 8 G12, 9 G09/G11/G19/G29/G30, 10 C, 11 C, 12 G09/G11/G19/G29/G30, 13 G11/G19/G29/G30, 14 C, 15 G11 |
| SetupChips, SetupChip, ChipFlow, EveryReplyRow, ToolMark, ShortTime and VoiceSummary | Tool/read-all/voice state → current labeled actions and correctly sized chips | Home/Now/History/MainWindow, Preferences, Connections and Runtime | 1 G05/G15/G18/G25/G27/G33, 2 G25/G27, 3 G05/G15, 4 G15/G20/G33, 5 G05/G33, 6 G05, 7 G15/G18/G33, 8 C, 9 G05/G15/G18/G20/G25/G27/G33, 10 NA no new storage, 11 C, 12 G05/G15/G18/G25/G33, 13 G05/G10/G15/G18/G33/G34, 14 C, 15 G05/G20 |

### PRs #2–#3 · Upgrade paths

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| H01 | Install 0.4 with only the documented work/account config dir connected. Replace the app in place with 0.5 and follow the release notes. The installed Claude integration stays on old bare commands, and new commands do not exist even in a new session. | Standalone alternate-home Claude upgrade | **Confirmed · #2**. Shipped Claude module fixture retained bare commands on alternate-only migration. |
| H02 | The mocked command tests can pass even if the packaged plugin excludes command files or supplies a different namespace. | Claude command provider | **Rejected**. Extracted draft had both files. Native validation recognized names and gating handlers. |
| H03 | Replace installed module while an old Claude session remains open. Command inventory may still reflect 0.2, or new module-level `me` / `cwd` may be empty if Claude only calls `session.start` at a genuinely new session. | Interactive Claude session reload | **Plausible**. Keep an old Claude session open during app and plugin replacement, then try both new commands. |
| H04 | Unquoted `argument-hint: [on\|off]` is a YAML one-element sequence, potentially losing autocomplete hint if Claude expects text. | Claude argument hint | **Rejected**. Standard Claude plugin validation discovered the command. Strict metadata warning is recorded. |
| H05 | Version 1.1.0 unchanged even when generated plugin source implementation was refactored in #1. | Codex plugin and shipped icons | **Rejected**. All seven generated files and both packaged icons matched between base and head. |
| H06 | Upgrading with another running app version or using a second installed copy can make version selection appear stable while the command endpoint disagrees. | Mixed copy and CLI path | **Merged**. I-09 covers the mixed-version replay path. |
| H07 | Friends guide promises Codex never asks again while releasing future changes to Codex hook bytes requires approval. | Future Codex approval promise | **Merged**. U20 covers future Codex approval wording. |
| H08 | Old OpenCode v1 package may be considered connected and skipped for refresh. Code-based migration is safe for unchanged V1 plugin semantics but does not carry V2 support. | OpenCode legacy plugin regeneration | **Merged**. I-32 covers unchanged OpenCode v1 scope. |
| H09 | Installed user follows guide from release zip and looks for Download now under selected Qwen3. | Qwen3 voice download docs | **Confirmed observation**. Friends guide says Download now for Qwen3. Only the Custom section uses that label. |
| H10 | User approves both hooks and follows the guide's visual verification. The tile never turns blue in the new monochrome design. | Connection design docs | **Confirmed observation**. Friends guide describes a blue approval tile. Head uses neutral state rendering. |
| H11 | A supported macOS 15+ Intel user downloads app and finds no working macOS voice. | Intel-compatible published package | **Merged**. U17 and #3 cover verified asset slices. |
| H12 | Update an ad-hoc-signed copy with Open Readback when you log in enabled. LaunchServices / SMAppService may reset OS approval because code identity changes. | Login item across in-place replacement | **Plausible**. Exercise actual login item following replacement in a disposable account. Compare before and after. |
| H13 | Replacing app at same path could reset prefs or invalidate existing History rows if storage key/decoding changes. | Legacy preferences / session history | **Rejected**. Decoded production history fixture and same installed ID/path show no migration issue in the tested shape. |
| H14 | Publish before merging, or ship an archive from a different version despite unchanged tag. | Asset draft versus intended PR | **Confirmed observation**. Draft matches recorded metadata. Publishing before merging is a release operation to avoid, not a current artifact defect. |

#### Contract and lens coverage

| Units | Inputs → outputs | State and effects | Direct callers / producers | Candidates | N/A |
|---|---|---|---|---|---|
| IntegrationFiles and AppBundle status, paths, copy refresh | Default or alternate settings plus packaged module → installed module and connection state | Reads Claude settings, source files and bundled paths; writes installed mod on Connect or default launch decision | `AppDelegate.applicationDidFinishLaunching`, `Connections.refreshPlugin`, CLI Connect | H01–H03, H06 | None |
| Claude manifest, Markdown commands, module, tests | Named slash command → local /command call or fallback | Module lifecycle carries session, API requests and in-app preference change | Runtime session.start/command.run, tests, build rsync | H01–H04, H06 | None |
| Codex plugin generator and assets, approval status | Fixed helper path and config → generated hooks, plugin bytes and status | Builds 7 files and asset copies, reads hook trust state | `IntegrationFiles` connect/status; CLI, app Connections; build.sh icons | H05–H07 | 9 for the pure generator |
| OpenCode V1 hook generator, installed file and compatibility | Tool event / file → same CLI arguments and unchanged source schema | Writes their plugin on Connect; legacy installed file unchanged on app upgrade | `IntegrationFiles.openCodeStatus`, external V1 host, CLI HookPayload | H08 | None |
| Release bundle and draft metadata | Source/build / draft tag → app archive, manifest, updater inputs | Packaging and architecture; CFBundle version markers | Release builder, GitHub draft, Updater and manual users | H02, H05, H11, H14 | 9 for static archive |
| Runtime upgrade preferences, storage and app OS registrations | Older installed app state → new launch, retained settings | Migration file/decode, OS trust, login settings | AppDelegate, Updater.afterLaunch, ReadingSettings, Replies | H12–H13 | None |
| Documentation and UI wording | Setup/update/approval instructions → reproducible visible action | Prompted Connect, downloaded voices, update and tools | README, friends guide, AGENT-SETUP, release notes; Connections and Voices UI | H01, H06–H11, H14 | None |

### PR #1 · Core follow-up

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| K01 | Existing history may stay in pre-upgrade permission state, and the unreadable backup inherits permissions | `Replies.swift:21–39,75–83`, `ReplyHistory.swift:130–140`, `AppBundle.swift:45–62`, `ControlAndQueueTests.swift:363–378` | **Pre-existing**. Legacy public modes remain until a successful write. No upgrade migration tightened idle history or moved-aside data. |
| K02 | Continuous descendant output keeps reader allocation and detached thread alive after the operation returns | `Codex.swift:398–419`, `Codex.swift:424–438`, `Codex.swift:364–368`, `ControlAndQueueTests.swift:745–757` | **Plausible**. Exercise an ordinary wrapper whose descendant continuously emits output and measure cleanup versus the base. |
| K03 | File logs can still contain tool paths and output error detail | `Connections.swift:80–88`, `Codex.swift:254–256`, `Log.swift:16–22`, `IntegrationFiles.swift:134–139` | **Merged**. A26 covers private file logs carrying raw diagnostics and identifying paths. |
| K04 | Alternate bundle isolation does not apply to CLI defaults for a cold copy | `ReadingSwitches.swift:12–14`, `Preferences.swift`, `main.swift:194–208`, `main.swift:151–154`, `ControlProtocol.swift:4–11` | **Pre-existing**. Base CLI also reads a fixed local.readback defaults domain. Isolated app IDs require explicit testing. |
| K05 | Privacy helper widens owner's permissions while removing group/other bits | `AppBundle.swift:45–53` | **Confirmed · #1**. Permission rewrite to 0700 adds owner write on an existing 0555 data directory. |
| K06 | Last eligible reply outside the two-MB window is lost, and a full first line can be dropped | `HookPayload.swift:38–64`, `main.swift:199–208,255–257`, `main.swift:134–143` | **Merged**. I-06 and I-27 track the bounded transcript and exact-offset concern. |
| K07 | Failed nonblocking setup or interrupted final read is ignored | `Codex.swift:399–400,408–429` | **Plausible**. Trigger a benign read interruption or unsupported F_SETFL in a scratch subprocess and verify reader termination. |
| K08 | Stop fallback can replay an older completed reply when recent turn has none | `HookPayload.swift:25–50,75–85`, `main.swift:191–208` | **Plausible**. Use a captured ordinary Codex Stop payload from an empty or interrupted turn to confirm prior-turn fallback behavior. |
| K09 | Concurrent hook log entries overwrite or interleave even when calls succeed | `AppBundle.swift:74–88` | **Merged**. I-25 covers unlocked file-offset operations across CLI processes. |
| K10 | Valid inline-commented disabled values are ignored and empty textual hashes count as approved | `Codex.swift:125–169` | **Merged**. I-12 retains live-host trust and parser check. |
| K11 | A below-minimum desktop-bundled CLI hides a supported standalone CLI | `Codex.swift:269–289,359–371` | **Plausible**. Check actual discovery precedence on a Mac with both official distribution channels installed. |
| K12 | Warnings appended to version output can cause false outdated refusal | `Codex.swift:303–321,391–395` | **Plausible**. Run a supported executable that emits a non-version warning during --version and check fallback rules. |
| K13 | Renamed uppercase .APP helper does not match bundle contract; helper identity detection is geometrical | `AppBundle.swift:19–22` | **Merged**. I-26 covers bundled helper resolution. |
| K14 | Empty explicit READBACK_HOME has real home path despite appearing isolated | `IntegrationFiles.swift:11–34` | **Plausible**. Test empty overrides with a deliberately isolated launch. An explicitly supplied scratch home takes precedence in supported verification. |
| K15 | Generic HTTP parser omits duplicate detection and accepts shape valid enough for its small route layer | `HTTPRequest.swift:29–44`, `ControlProtocol.swift:222–234` | **Plausible**. Static defensive review flagged ambiguous duplicate header handling. No protocol exploitation or external ingress check was performed. |
| K16 | 200-shaped error on typed encoding failure is silently sent as empty JSON | `HTTPRequest.swift:56–63` | **Merged**. I-19 covers success-shaped encoder fallback. |
| K17 | Timestamp backup only second granularity can lead to stranded unsaved run after recoverable transient move failure | `Replies.swift:26–38,75–85` | **Confirmed observation**. Unreadable history is protected on move failure but saves remain disabled until restart after permissions recover. |
| K18 | Two tools with same supplied session identifier affect each other's read switch | `ReadingSwitches.swift:30–44`, `AppDelegate.swift:360–376` | **Merged**. I-23 covers bare session identifiers across tools and homes. |
| K19 | A profile connected only through CLI does not get installed Claude mod update at app launch | `Connections.swift:33–37,98–109`, `IntegrationFiles.swift:44,170–177` | **Merged**. H01 carries the alternate-only release probe. |
| K20 | No regular-file check, byte cap is inferred by seek, and macOS CRLF grapheme can frustrate line split | `HookPayload.swift:38–64,90–97` | **Plausible**. Verify expected transcript files and CRLF behavior using ordinary fixtures from real tool producers. |
| K21 | Generated fallback Codex skill instructions target consuming tool but superficially resemble reviewer direction | `Codex.swift:90–103` | **Rejected**. Generated skill text instructs the installed feature and contains no directive to this review. |

#### Contract and lens coverage

| Unit | Promise | Direct callers/tests | Lenses |
|---|---|---|---|
| AppBundle layout and helper resolution | Shared bundle paths and integration factory keyed to executable copy | AppDelegate, Connections, Runtime, main CLI, build-app.sh | 1 K13, 2 K13, 3 C, 4 NA no persistence, 5 C, 6 K13, 7 K13, 8 C, 9 NA no UI, 10 K19, 11 C, 12 K13, 13 K19, 14 K13, 15 C |
| PrivateFiles and LogFile | Private sane-mode directory/file, safe write and log append | ReplyHistory.save, Log.swift, main.swift, PrivateFilesTests | 1 K03/K05, 2 K05, 3 K01/K09, 4 K01, 5 K05/K09, 6 K01/K09, 7 K01, 8 C, 9 C, 10 K01/K05, 11 K01/K03/K05, 12 K01/K05/K09, 13 K01/K03, 14 K05, 15 K03 |
| CodexPlugin generated definitions and trust parse | CLI+immutable component files and read-only trust/config check | IntegrationFiles, generated host plugin, CodexTests | 1 K10, 2 K10, 3 C, 4 K10, 5 C, 6 K10, 7 K10, 8 C, 9 C, 10 C, 11 K10, 12 K10, 13 K21, 14 K21, 15 K10/K21 |
| CodexCLI detection, run, drain and Collected | Find supported appropriate codex, run within deadline and return output | AppBundle default injection, IntegrationFiles, CodexTests and CodexDrainTests | 1 K11, 2 K02/K12, 3 K12, 4 NA no persistence across runs, 5 K02/K07/K09, 6 K02/K03/K07/K11/K12, 7 K07/K11, 8 K03, 9 K02, 10 NA invokes program without data schema, 11 K03, 12 K02/K07/K11/K12, 13 C, 14 C, 15 K03 |
| ReadbackPaths, ToolHome routing | Select real/custom/scratch home without leaking user environment | Connections, IntegrationFiles, Runtime, Replies, both app/CLI logs, Codex tests | 1 K14/K19, 2 K14, 3 C, 4 K19, 5 C, 6 C, 7 K14/K19, 8 K14/K19, 9 K19, 10 K19, 11 C, 12 K14/K19, 13 K19, 14 K14, 15 C |
| ReadingSwitches | Shared app/CLI UserDefaults and bounded session auto-reading list | Preferences and main CLI, ReadingSwitches tests | 1 K04/K18, 2 C, 3 K04/K18, 4 K18, 5 K18, 6 C, 7 C, 8 K04/K18, 9 K04, 10 C, 11 C, 12 K04/K18, 13 K04/K18, 14 C, 15 C |
| HTTPRequest/HTTPResponse | Frame ControlServer byte buffers and encode replies | Production ControlServer, ControlRequest, direct Core tests | 1 K15, 2 K15/K16, 3 C, 4 NA no persisted protocol state, 5 K15, 6 K15/K16, 7 K16, 8 K15, 9 NA no native UI, 10 NA no schema migration, 11 K15, 12 K15/K16, 13 C, 14 C, 15 C |
| ReplyHistory storage/restore and Replies adapter | Data file recoverable, cap and saved precedence preserved | AppDelegate, ReplyQueue, history UI, ReplyHistoryTests and PrivateFilesTests | 1 K01/K17, 2 C, 3 K01, 4 K01/K17, 5 K17, 6 K01/K05/K17, 7 K17, 8 C, 9 K17, 10 K01/K05/K17, 11 K01/K05, 12 K01/K05/K17, 13 K01, 14 C, 15 C |
| HookPayload parser, transcript scan and StopRequest adapter | Typed reply/current session from hook JSON and valid optional transcript | CLI stop/prompt/read/hook, Claude and OpenCode emitted fields, Codex/ControlAndQueue tests | 1 K06/K08/K20, 2 K06/K20, 3 K08/K18, 4 K06/K08, 5 C, 6 K06/K20, 7 K06/K08, 8 K18/K20, 9 NA input only, 10 NA reads transcript without migration, 11 K20, 12 K06/K08/K20, 13 K06/K08, 14 C, 15 C |

### PR #2 · Updater follow-up

| ID | Candidate | Code path or contract | Disposition |
|---|---|---|---|
| J01 | A new engine install/download/Connect can be interrupted despite the updater's wait guard. | `Updater.swift:31`, `AppDelegate.swift:65–69`, `Updater.swift:95–99,177–199`, `Connections.swift:64–94`, `UpdatesTests.swift:206–218` | **Merged**. U01 confirms busy work can start after the first check. |
| J02 | A fixed release asset cannot be loaded after an initial install failure in the same app run. | `Updates.swift:243–250,268–275,306–309`, `VersionCard.swift:48–64,91–102` | **Merged**. U10 confirms stale metadata through production UpdateFlow. |
| J03 | Updater accepts a writable app on a different volume and always fails replacing it. | `Updater.swift:82–85`, `NSFileManager.h:770` | **Merged**. U05 carries the APFS probe and Apple contract. |
| J04 | Late events from a cancelled attempt alter the retry. | `Updater.swift:39–42,95–112,118–134`, `Updates.swift:280–298`, `UpdatesTests.swift:221–231` | **Merged**. U11 tracks the remaining attempt-ownership timing check. |
| J05 | A release can install a newer-than-current app that isn't the advertised version. | `Updater.swift:152–156`, `Updates.swift:96–100` | **Merged**. U08 captures the release tag/bundle mismatch under U02. |
| J06 | A future release can validate, replace and then fail to launch on the old supported OS or CPU. | `Updates.swift:96–100`, `Updater.swift:156–158,177–199`, `scripts/build-app.sh:19–27,63` | **Merged**. U02 records absent architecture and OS eligibility. |
| J07 | Failure can remove old copy from expected location while card promises unchanged. | `NSFileManager.h:772`, `Updater.swift:179–185`, `Updates.swift:145–173` | **Merged**. U06 records the documented but unobserved relocated-original condition. |
| J08 | User can be left on no running app with no visible explanation after a successful replacement. | `Updater.swift:188–199`, `Updates.swift:105–109` | **Merged**. U04 folds actual relaunch failure and recovery into U02. |
| J09 | Marker can falsely report a successful same-version update or be lost before startup capture permission recovery. | `Updater.swift:177–185`, `AppDelegate.swift:71` | **Merged**. U13 tracks the stale marker check. |
| J10 | Force quit or crash leaves archives and expanded bundles indefinitely in temp storage. | `Updater.swift:90–112,187,202–204`, `AppDelegate.swift:56–64,145–174` | **Plausible**. Force quit during a scratch update and check startup scavenging and eventual OS cleanup. |
| J11 | A failed quarantine removal can yield an installed bundle that cannot open unaided. | `Updater.swift:156–159` | **Merged**. U12 tracks failure to remove quarantine. |
| J12 | Read failure during digest or archive extraction is reported as bad bytes or absent app. | `Updater.swift:145–150,206–215` | **Confirmed observation**. SHA read error maps to digest mismatch and failed extraction maps to no app. Installed bundle was untouched in verified early failures. |
| J13 | LaunchServices could activate another already-running same-bundle application or the waiting shell could live beyond intended completion. | `Updates.swift:105–109` | **Plausible**. Open two same-ID copies and confirm the detached helper selects the installed path when one remains running. |
| J14 | A URLSession-originated cancellation not initiated by the card leaves it in downloading. | `Updater.swift:100–103` | **Plausible**. Check a Foundation-side cancellation that did not come from the card. Code suppresses transport cancellation independently of card state. |
| J15 | Retry disabled while a different job runs, with no reason communicated. | `VersionCard.swift:91–101` | **Merged**. U14 covers disabled retry with no wait copy. |
| J16 | An API 403 unrelated to limits is diagnosed as a transient GitHub rate limit. | `Updater.swift:62–68`, `Updates.swift:117–135` | **Merged**. U27 documents the spec's 403 and 429 behavior. |
| J17 | Metadata parsing tests establish payload compatibility and copy, not publisher identity or the replacement invariants claimed in the UI. | `Updates.swift:36–56,96–100`, `Updater.swift:144–159` | **Merged**. U03 and U24 cover update integrity, publisher model and replacement test scope. |

#### Contract and lens coverage

| Unit | Contract, state, callers | Lens coverage |
|---|---|---|
| Release parse and check | GitHub/latest and fixture file URL → Release or stable error; App Updater.fetch, UpdateFlow.check/checked, VersionCard; request and transient or cached result. | 1 J05/J16/J17, 2 J16/J17, 3 J02/J05, 4 J02, 5 check guards repeat, 6 J16, 7 J02, 8 existing GitHub trust choice J17, 9 J02, 10 — no persisted release schema, 11 J17, 12 J02/J16/J17, 13 J05/J17, 14 silent automatic fetch is absent, 15 J02/J16 |
| Download, progress and cancel | One download → file, meter, cancelled/failure state; UI Install/Cancel, URLSessionTask delegate, main actor timer, Core transition. | 1 J01/J04, 2 amount optional, 3 J04/J02, 4 stale result J04, 5 J01/J04, 6 J04/J10/J14, 7 J04/J14, 8 per-file UUID but no generation J04, 9 J01/J04, 10 J10 cleanup, 11 already discussed HTTPS/source trust, 12 J01/J04, 13 J01/J04, 14 purpose-bound click, 15 J04/J14 |
| Validation and archive | Archive → staged checked local app; release digest, unpack tool, target identity; Updater.download and Core helpers. | 1 J03/J05/J06, 2 J05/J17, 3 J05/J06, 4 J05, 5 before swap checked, 6 J03/J06/J11/J12, 7 J11, 8 signed bundle/id J17, 9 J06/J11, 10 J03, 11 J11/J17, 12 J03/J05/J06/J11/J17, 13 J05/J06/J11/J17, 14 package id/layout, 15 J05/J11/J12/J17 |
| Swap, cleanup and launch | Staged bundle → installed bundle and async process launch; Foundation mutation, cleanup, defaults, subprocess, Application termination. | 1 J03/J06/J08, 2 app path handled as argv, 3 J07/J09, 4 J09/J10, 5 J01/J07/J08/J09/J13, 6 J03/J06/J07/J08/J10, 7 J07/J08, 8 J13, 9 J01/J07/J08/J09/J13, 10 J03/J06/J07/J10, 11 J09, 12 J01/J03/J07/J08/J09, 13 J01/J03/J06/J07/J08/J09, 14 path contract, 15 J07/J08/J09 |
| Sidebar states and test targets | Updater state + ModelDownloads, Runtime, Connections → rendered status/actions; UI drives flow; tests cover pure transitions and fixtures. | 1 J02/J15, 2 unknown total guards, 3 J01/J02, 4 J02, 5 J01/J04, 6 J02/J15/J17, 7 J02, 8 no app identity mutation in view, 9 J02/J15, 10 — no persisted view state, 11 underlying provider choices, 12 J01/J02/J04/J07/J08/J15/J17, 13 J01/J02/J15, 14 Core only test target, 15 J02/J15/J17 |

## Changed-file inventory

The contract maps above show production relationships. This inventory traces every changed file back to its pinned range, including deleted files, documentation and tests.

### PR #1 · b4d6449...a6b2b88

| File | Added | Removed | Changed spans in head |
|---|---:|---:|---|
| `.agents/review-notes.md` | 40 | 0 | 1–40 |
| `AGENT-SETUP.md` | 6 | 4 | 57, 122–124, 127–128 |
| `AGENTS.md` | 56 | 0 | 1–56 |
| `CLAUDE.md` | 1 | 0 | 1 |
| `PRODUCT.md` | 60 | 0 | 1–60 |
| `Sources/Readback/AppDelegate.swift` | 180 | 135 | 59 (deletion), 62, 103, 203, 208–223, 232–234, 237–262, 265–279, 283–285, 288–298, 305, 309 and 8 further hunks |
| `Sources/Readback/Connections.swift` | 46 | 68 | 4, 11–12, 15–25, 34–37, 42–44, 48–51, 53, 55, 57–58, 60, 61 (deletion), 64–65 and 5 further hunks |
| `Sources/Readback/ControlServer.swift` | 54 | 107 | 5–6, 8–9, 13–14, 19, 22, 25, 35–41, 43–55, 57–63, 66, 78, 83–98 and 1 further hunks |
| `Sources/Readback/Log.swift` | 6 | 13 | 3, 10, 13–14, 20, 22 |
| `Sources/Readback/ModelDownloads.swift` | 6 | 0 | 53–58 |
| `Sources/Readback/PlayerPanel.swift` | 23 | 3 | 43, 60–77, 237, 239–241 |
| `Sources/Readback/PlayerView.swift` | 30 | 4 | 30–31, 99–101, 104, 287–288, 300 (deletion), 344, 348, 356, 580–598 |
| `Sources/Readback/Preferences.swift` | 16 | 18 | 30–31, 33, 59–60, 63–65, 67, 71, 74–75, 104–107 |
| `Sources/Readback/Reader.swift` | 32 | 9 | 29–33, 74, 86–87, 141–142, 149–150, 154, 163, 167–174, 187–188, 214–217, 232, 234–235 and 1 further hunks |
| `Sources/Readback/Replies.swift` | 54 | 22 | 4–5, 8, 11–13, 17–20, 22–38, 41–50, 51 (deletion), 54, 57–58, 65–66, 68, 73–80 and 2 further hunks |
| `Sources/Readback/Runtime.swift` | 74 | 18 | 1, 79, 93–96, 107, 110–111, 112 (deletion), 114–121, 140–144, 146–147, 158–163, 165, 189–191 and 7 further hunks |
| `Sources/Readback/SpeechMakers.swift` | 95 | 15 | 21, 26, 167–171, 180–185, 187–196, 206, 252–260, 290–292, 329–349, 358, 364–379, 381 and 7 further hunks |
| `Sources/Readback/Window/ConnectionSettings.swift` | 51 | 46 | 11–15, 33–37, 42, 45 (deletion), 54, 56–57, 69, 76, 79–81, 85–91, 94, 96–97 and 10 further hunks |
| `Sources/Readback/Window/HistoryPages.swift` | 22 | 3 | 32, 61, 63, 154, 174, 201–217 |
| `Sources/Readback/Window/MainWindow.swift` | 22 | 23 | 146, 248, 250 (deletion), 263 (deletion), 282, 304 (deletion), 329–330, 333–335, 342–345, 349, 384–385, 389–390 and 2 further hunks |
| `Sources/Readback/Window/ReadingSettings.swift` | 2 | 2 | 18–19 |
| `Sources/Readback/Window/SetupSheet.swift` | 36 | 51 | 18, 23–24, 27, 58, 93–96, 98–99, 138–149, 151, 153, 161, 163–164, 263 and 4 further hunks |
| `Sources/Readback/Window/Surfaces.swift` | 1 | 1 | 11 |
| `Sources/Readback/Window/VoicesPage.swift` | 140 | 44 | 13–14, 17–23, 29–31, 39–41, 44–45, 106, 198, 250, 356, 358–359, 361–373, 375–455 and 4 further hunks |
| `Sources/ReadbackCore/AppBundle.swift` | 90 | 0 | 1–90 |
| `Sources/ReadbackCore/Codex.swift` | 76 | 18 | 24–25, 151–153, 194–195, 207–231, 374–378, 381, 396–401, 403–434, 440 (deletion) |
| `Sources/ReadbackCore/ControlProtocol.swift` | 303 | 0 | 1–303 |
| `Sources/ReadbackCore/HTTPRequest.swift` | 13 | 34 | 18, 23, 25, 58–67, 74 (deletion) |
| `Sources/ReadbackCore/HookPayload.swift` | 124 | 0 | 1–124 |
| `Sources/ReadbackCore/IntegrationFiles.swift` | 179 | 87 | 6–9, 14, 17–18, 22–27, 44, 52, 60, 63, 65–66, 76–105, 112, 115–116 and 31 further hunks |
| `Sources/ReadbackCore/Integrations.swift` | 102 | 24 | 16–23, 36–60, 62–63, 65–66, 70–74, 76–92, 95–100, 103, 178–179, 188–197, 200–201, 214–219 and 7 further hunks |
| `Sources/ReadbackCore/ModelCache.swift` | 74 | 3 | 73–76, 79–83, 88–152 |
| `Sources/ReadbackCore/ReadingSwitches.swift` | 47 | 0 | 1–47 |
| `Sources/ReadbackCore/ReplyHistory.swift` | 29 | 8 | 21–24, 67, 70, 74–85, 116–120, 128–131, 134, 140 |
| `Sources/ReadbackCore/ReplyQueue.swift` | 150 | 0 | 1–150 |
| `Sources/ReadbackCore/SpeechText.swift` | 71 | 5 | 7–11, 17–19, 20 (deletion), 74–103, 105, 108, 110–113, 124–150 |
| `Sources/ReadbackCore/VoiceCatalog.swift` | 20 | 0 | 87–106 |
| `Sources/readback-cli/main.swift` | 137 | 162 | 5, 13–14, 17, 19, 31, 39 (deletion), 42, 50–61, 63–65, 71, 75, 77–79 and 45 further hunks |
| `Tests/ReadbackCoreTests/CodexTests.swift` | 23 | 20 | 27–32, 192, 195, 211, 243, 250, 258–259, 261, 263, 265, 279–280, 282–284 and 2 further hunks |
| `Tests/ReadbackCoreTests/ControlAndQueueTests.swift` | 836 | 0 | 1–836 |
| `Tests/ReadbackCoreTests/ModelCacheTests.swift` | 72 | 2 | 28–30, 33, 36, 65–95, 145–180 |
| `Tests/ReadbackCoreTests/ReadbackCoreTests.swift` | 36 | 0 | 102–137 |
| `Tests/ReadbackCoreTests/ReplyHistoryTests.swift` | 43 | 2 | 57, 60–101 |
| `bin/readback` | 0 | 88 | Deleted |
| `design/icon/NOTES.md` | 1 | 1 | 69 |
| `docs/DEVELOPMENT.md` | 11 | 7 | 10–15, 33–34, 37, 54, 59 |
| `docs/reviews/2026-11-25-main-deep-review-b4d6449-coverage.md` | 315 | 0 | 1–315 |
| `docs/reviews/2026-11-25-main-deep-review-b4d6449-ledger.md` | 128 | 0 | 1–128 |
| `docs/reviews/2026-11-25-main-deep-review-b4d6449.md` | 172 | 0 | 1–172 |
| `integrations/claude-code/readback/hooks/register.tsx` | 8 | 10 | 12–13, 94–96, 105–107 |
| `integrations/claude-code/readback/tests/commands.test.ts` | 22 | 9 | 4–5, 29, 37, 40, 52–53, 60–61, 82–83, 85, 103–112 |
| `scripts/build-app.sh` | 5 | 7 | 9, 30–33 |

### PR #2 · a6b2b88...1942cef

| File | Added | Removed | Changed spans in head |
|---|---:|---:|---|
| `.gitignore` | 1 | 0 | 9 |
| `AGENT-SETUP.md` | 2 | 2 | 67, 112 |
| `AGENTS.md` | 3 | 2 | 21, 30, 46 |
| `PRODUCT.md` | 6 | 5 | 21, 35, 37, 39, 46, 48 |
| `README.md` | 1 | 1 | 23 |
| `Sources/Readback/AppDelegate.swift` | 65 | 0 | 21–22, 36–39, 65–71, 77–87, 108, 288–327 |
| `Sources/Readback/ModelDownloads.swift` | 6 | 6 | 19–24 |
| `Sources/Readback/OtherAudioLowerer.swift` | 326 | 0 | 1–326 |
| `Sources/Readback/PlayerView.swift` | 24 | 22 | 45–46, 78, 96–109, 435, 436 (deletion), 493–494, 509, 520, 564, 568 |
| `Sources/Readback/Preferences.swift` | 4 | 0 | 30–32, 61 |
| `Sources/Readback/Reader.swift` | 3 | 1 | 101–103 |
| `Sources/Readback/Runtime.swift` | 1 | 1 | 173 |
| `Sources/Readback/Updater.swift` | 241 | 0 | 1–241 |
| `Sources/Readback/Window/Components/Buttons.swift` | 140 | 0 | 1–140 |
| `Sources/Readback/Window/Components/Checkbox.swift` | 61 | 0 | 1–61 |
| `Sources/Readback/Window/Components/Dropdown.swift` | 319 | 0 | 1–319 |
| `Sources/Readback/Window/Components/FocusRing.swift` | 49 | 0 | 1–49 |
| `Sources/Readback/Window/Components/Glass.swift` | 40 | 0 | 1–40 |
| `Sources/Readback/Window/Components/IconPlate.swift` | 66 | 0 | 1–66 |
| `Sources/Readback/Window/Components/Meter.swift` | 45 | 0 | 1–45 |
| `Sources/Readback/Window/Components/Motion.swift` | 25 | 0 | 1–25 |
| `Sources/Readback/Window/Components/SearchField.swift` | 84 | 0 | 1–84 |
| `Sources/Readback/Window/Components/Segmented.swift` | 80 | 0 | 1–80 |
| `Sources/Readback/Window/Components/Switch.swift` | 63 | 0 | 1–63 |
| `Sources/Readback/Window/Components/Waveform.swift` | 51 | 0 | 1–51 |
| `Sources/Readback/Window/ConnectionSettings.swift` | 21 | 16 | 20, 48, 53–54, 56, 69–74, 88, 97, 127, 136, 146, 159, 164 and 2 further hunks |
| `Sources/Readback/Window/HistoryPages.swift` | 128 | 122 | 12–13, 15, 17–18, 20–22, 25–42, 47–48, 51–59, 64–69, 71, 81, 115–116, 123 and 15 further hunks |
| `Sources/Readback/Window/Home/NowCard.swift` | 274 | 0 | 1–274 |
| `Sources/Readback/Window/Home/SessionsList.swift` | 230 | 0 | 1–230 |
| `Sources/Readback/Window/Home/SetupChips.swift` | 201 | 0 | 1–201 |
| `Sources/Readback/Window/Home/ToolMark.swift` | 86 | 0 | 1–86 |
| `Sources/Readback/Window/MainWindow.swift` | 75 | 53 | 54–59, 62–67, 73–74, 77–78, 81–82, 126, 135–141, 143, 146–149, 152–157, 161, 169–172 and 14 further hunks |
| `Sources/Readback/Window/ReadingSettings.swift` | 20 | 29 | 26, 31–32, 34 (deletion), 40–47, 52–53, 55 (deletion), 64–67, 69 (deletion), 71–73, 75 (deletion) |
| `Sources/Readback/Window/SelfDraggingWindow.swift` | 57 | 0 | 1–57 |
| `Sources/Readback/Window/SetupSheet.swift` | 23 | 16 | 52, 80, 99, 103, 111, 119, 153, 191, 255, 265, 322–325, 339 and 7 further hunks |
| `Sources/Readback/Window/Surfaces.swift` | 58 | 27 | 6–16, 32–36, 38–40, 43–49, 51–53, 55, 57–63, 65, 67, 71, 73, 108 and 6 further hunks |
| `Sources/Readback/Window/VersionCard.swift` | 183 | 0 | 1–183 |
| `Sources/Readback/Window/VoicesPage.swift` | 170 | 106 | 16–17, 19–23, 25–36, 55–58, 63 (deletion), 90–91, 92 (deletion), 104–111, 161, 170, 215–216, 220 and 15 further hunks |
| `Sources/ReadbackCore/ControlProtocol.swift` | 14 | 3 | 284–285, 290, 293, 305–314 |
| `Sources/ReadbackCore/DownloadAmount.swift` | 63 | 0 | 1–63 |
| `Sources/ReadbackCore/DuckingMix.swift` | 83 | 0 | 1–83 |
| `Sources/ReadbackCore/EngineInstall.swift` | 11 | 0 | 1–11 |
| `Sources/ReadbackCore/MenuNavigation.swift` | 56 | 0 | 1–56 |
| `Sources/ReadbackCore/OtherAudioDucking.swift` | 83 | 0 | 1–83 |
| `Sources/ReadbackCore/ReplyFilter.swift` | 34 | 0 | 1–34 |
| `Sources/ReadbackCore/SegmentStep.swift` | 7 | 0 | 1–7 |
| `Sources/ReadbackCore/SessionSummary.swift` | 44 | 0 | 1–44 |
| `Sources/ReadbackCore/SpokenText.swift` | 215 | 0 | 1–215 |
| `Sources/ReadbackCore/Updates.swift` | 314 | 0 | 1–314 |
| `Sources/ReadbackCore/WaveformMotion.swift` | 59 | 0 | 1–59 |
| `Sources/ReadbackCore/WindowDragWorkaround.swift` | 12 | 0 | 1–12 |
| `Tests/ReadbackCoreTests/ControlAndQueueTests.swift` | 13 | 0 | 84–96 |
| `Tests/ReadbackCoreTests/DownloadAmountTests.swift` | 75 | 0 | 1–75 |
| `Tests/ReadbackCoreTests/DuckingMixTests.swift` | 147 | 0 | 1–147 |
| `Tests/ReadbackCoreTests/EngineInstallTests.swift` | 26 | 0 | 1–26 |
| `Tests/ReadbackCoreTests/MenuNavigationTests.swift` | 91 | 0 | 1–91 |
| `Tests/ReadbackCoreTests/OtherAudioDuckingTests.swift` | 73 | 0 | 1–73 |
| `Tests/ReadbackCoreTests/ReplyFilterTests.swift` | 67 | 0 | 1–67 |
| `Tests/ReadbackCoreTests/SegmentStepTests.swift` | 18 | 0 | 1–18 |
| `Tests/ReadbackCoreTests/SessionSummaryTests.swift` | 72 | 0 | 1–72 |
| `Tests/ReadbackCoreTests/SpokenTextTests.swift` | 92 | 0 | 1–92 |
| `Tests/ReadbackCoreTests/UpdatesTests.swift` | 232 | 0 | 1–232 |
| `Tests/ReadbackCoreTests/WaveformMotionTests.swift` | 65 | 0 | 1–65 |
| `Tests/ReadbackCoreTests/WindowDragWorkaroundTests.swift` | 26 | 0 | 1–26 |
| `docs/DEVELOPMENT.md` | 13 | 4 | 22, 34–35, 37, 64–72 |
| `docs/README-for-friends.md` | 13 | 3 | 35, 46, 52–53, 56, 60–67 |
| `docs/superpowers/plans/2026-11-25-polish-and-dashboard.md` | 243 | 0 | 1–243 |
| `docs/superpowers/plans/2026-11-25-readback-look.md` | 158 | 0 | 1–158 |
| `docs/superpowers/plans/2026-11-26-session-see-all.md` | 60 | 0 | 1–60 |
| `docs/superpowers/plans/2026-11-26-update-check.md` | 53 | 0 | 1–53 |
| `docs/superpowers/specs/2026-11-25-polish-and-dashboard-design.md` | 126 | 0 | 1–126 |
| `docs/superpowers/specs/2026-11-25-readback-look-design.md` | 148 | 0 | 1–148 |
| `docs/superpowers/specs/2026-11-26-session-see-all-design.md` | 29 | 0 | 1–29 |
| `docs/superpowers/specs/2026-11-26-update-check-design.md` | 84 | 0 | 1–84 |
| `integrations/claude-code/readback/.claude-plugin/plugin.json` | 2 | 2 | 3–4 |
| `integrations/claude-code/readback/commands/read.md` | 6 | 0 | 1–6 |
| `integrations/claude-code/readback/commands/speak.md` | 7 | 0 | 1–7 |
| `integrations/claude-code/readback/hooks/register.tsx` | 17 | 23 | 6–14, 18–19, 71 (deletion), 75, 84, 86, 91, 93, 102 |
| `integrations/claude-code/readback/tests/commands.test.ts` | 27 | 15 | 4–5, 18–21, 53, 56, 61, 64, 69, 72, 74, 77, 85, 93 and 4 further hunks |
| `scripts/build-app.sh` | 3 | 2 | 8, 13, 67 |

## Production conditions still to check

- Leave an active Claude session and a live Codex or Orca session running through an isolated app replacement. Verify each command still addresses the right session, that Codex uses the same trusted definition, and that a fresh alternate-login Claude session sees both new commands.
- Use two local working directories and several queued readings on a clean test copy. Try keyboard and VoiceOver with the custom menus and Home reply rows, including Escape while the floating player is visible. Switch Reduce Motion on. Check the short-display menu, folded stack, and handoff.
- Keep a real download or Connect active at the point an isolated app update is ready to swap. The old copy should stay active until the operation finishes. For a future release, confirm the new process reports its version while the existing settings, login item and integrations are still live.
- Test output device switching, permission denial, opt-out, multichannel and duplex hardware while another app plays audio. Opt-out should release the tap promptly and system audio should stay audible.
- After a failed download or cancelled local replacement, test two successive retries with separate operation identities. An earlier callback should never change the latest card or row.
- A production release could fail with a valid but incompatible signed app or a new package layout. The exact draft's checks, version/architecture gap and residual launch risk appear in the #3 and #2 reports. Supported older OS runtimes and actual Intel launch were outside the host verification.
