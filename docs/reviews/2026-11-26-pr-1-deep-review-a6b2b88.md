# PR #1 · Protocol, queue, integrations and voice downloads

**Verdict · Blocked**

Reviewed [PR #1](https://github.com/iykazrji/readback/pull/1) from merge base `b4d6449e1d5a9bb49e8437da50cdff8a3594772c` to head `a6b2b88a22a9585140f03e47990d1d2993b4fe2d`. The range changes 52 files. The [coverage and evidence appendix](2026-11-26-readback-prs-deep-review-coverage.md) records the changed contracts, independent review passes, and candidate dispositions.

## Findings

### Critical · Cancel deletes model data that existed before the download

**Introduced.** An existing Hugging Face cache can have a usable older revision and an incomplete current revision. Readback checks only the current snapshot when deciding to download, then Cancel calls the whole-repository deletion routine. That routine removes every revision and the unshared blobs it finds, including files another program may still need. The UI promises to remove what this download fetched.

- **Code** `Sources/Readback/SpeechMakers.swift:350–359,418–427`, `Sources/ReadbackCore/ModelCache.swift:35–45,77–85,107–128`.
- **Evidence** A scratch fixture with an incomplete `refs/main` and an existing older weights file produced `active snapshot incomplete: true` and `old weights exist after cancel cleanup: false` through production `ModelCache`. The base has no per-voice Cancel or cache removal routine. The same head behavior is present in #2 and #3.
- **Fix** Give the download job ownership of its staging files and remove only that job's uncommitted files. Keep full cache cleanup behind an explicit remove action.

### Critical · Two separate replies can become one History entry

**Introduced.** Save a turn that says “Done.” Start another turn in the same session that also says “Done.” If the user runs `/read` after the second turn is in the transcript and before its Stop hook arrives, the app reuses the first row and marks it as awaiting the hook. The second Stop consumes the marker. The second turn never gets its own row, timestamp, or queue decision.

- **Code** `Sources/ReadbackCore/ReplyQueue.swift:51–63,75–92,114–120`. The base adds a row for an ordinary Stop in `Sources/Readback/AppDelegate.swift:257–265`.
- **Evidence** A probe ran both turns through production `ReplyQueue`, including the intervening new-prompt stop. It ended with one row.
- **Fix** Pass a stable turn or message identifier from each producer. Deduplicate across `/read` and Stop only when both deliveries identify the same turn.

### High · The new command handler lacks local caller authentication

**Introduced handler with a pre-existing local trust gap.** The new `/command` path accepts control operations after checking Host, method, media type and body shape. The server does not establish which local client sent the request before the app reads or changes session state or starts replay. The base already had comparable unauthenticated operations under `/session`, `/speak` and `/replay`. This finding applies the skill's merge gate to the new handler. The loopback bind and browser-facing request checks are improvements.

- **Code** `Sources/ReadbackCore/ControlProtocol.swift:219–237,265–270`, `Sources/Readback/AppDelegate.swift:332–335,367–379`. Static defensive review.
- **Fix** Establish a local client identity contract before dispatch and apply it consistently to the CLI, Claude mod, and OpenCode path. Keep unauthenticated readiness minimal if needed.

### Medium · A voice download can remain stuck after its job has exited

**Worsened.** The download publishes its active state before opening the engine log. If opening the log fails, the job exits before the cleanup block. The active row remains on screen, and Cancel finds no job to stop. The base already published progress before opening the log, but the new per-row download, Cancel, and updater busy state consume that stale value.

- **Code** `Sources/Readback/SpeechMakers.swift:341–361,381–414,449–458`, `Sources/Readback/ModelDownloads.swift:27–61`. #2 also uses it in `Sources/Readback/AppDelegate.swift:65–69`.
- **Evidence** Ran the production `VoiceServer.download` adapter in a temp home with an unusable log path. The call returned a filesystem error. `downloads.active` still contained the model after the call and after Cancel.
- **Fix** Finish every announced download on all setup, launch, cancellation, and process-exit paths. Make startup failure reach the same per-row retry state as a nonzero process exit.

### Medium · The player can cancel a different voice's download

**Introduced.** With the macOS voice selected, start a separate model download, then start a reading. While the player is preparing or waiting for its cue, it describes the active background job as its own voice and sends Cancel for that model. The base displayed generic progress but did not expose this destructive player action or the independent per-row download.

- **Code** `Sources/Readback/PlayerView.swift:89–101`, `Sources/Readback/PlayerPanel.swift:41–46`, `Sources/Readback/AppDelegate.swift:220–222`.
- **Evidence** The player tests only its phase, progress and the global download cell. It makes no comparison against the speech maker or model for the reading.
- **Fix** Pass the reader's download identity into the player and show cancellation only for that operation.

### Medium · A waiting reply can disappear before it speaks

**Introduced.** With more entries waiting than the history cap, the oldest still starts first. Marking it played trims it out of history before the engine speaks. A subsequent preparation failure cannot mark it kept, so the person cannot replay it.

- **Code** `Sources/ReadbackCore/ReplyQueue.swift:125–148`, `Sources/ReadbackCore/ReplyHistory.swift:70–75,120–123`, `Sources/Readback/AppDelegate.swift:253–255).
- **Evidence** With a cap of two and three pending entries, the production queue started the oldest, immediately lost its row, and could not restore it with `readingFailed`. The base retained the active row in the same marking step.
- **Fix** Keep the active item outside the trim candidates until actual playback or a terminal disposition.

### Medium · The refactor breaks replay when the helper and running app differ

**Introduced.** A 0.4 helper talks to an already-running newer app on the shared port. Its replay route returns 404. A new helper can similarly treat the still-running old app as healthy and then send a command it cannot answer. This matters with a second copy pointed at the same port or an old hook path during a manual upgrade.

- **Code** Base `Sources/Readback/ControlServer.swift:118–122` and `Sources/readback-cli/main.swift` replay dispatch. Head `Sources/ReadbackCore/ControlProtocol.swift:256–279` and `Sources/readback-cli/main.swift:100,114–129,252–275`.
- **Fix** Keep a compatibility route for the supported migration window or require protocol compatibility before the helper uses the live app.

### Medium · History writes can override an intentionally read-only directory

**Introduced.** An existing Readback data folder owned by the person can be deliberately set to mode `0555`. The new privacy helper sees group or other bits and unconditionally changes the folder mode to `0700` before the write. This adds owner write permission and lets the save proceed. The base save had no mode rewrite.

- **Code** `Sources/ReadbackCore/AppBundle.swift:45–62`, `Sources/ReadbackCore/ReplyHistory.swift:137–141`.
- **Evidence** Static mode transition on the normal history-save path.
- **Fix** Preserve owner permission bits while clearing group and other bits. Surface a save failure when the owner has removed write permission.

## Pre-existing behavior and open checks

- A history disk error is visible in History while the transport still acknowledges the reply. The base also returns success before durable persistence. The new UI warning improves observability. The current contract treats HTTP 202 as accepted for processing. Clarify durability requirements before changing it. `Sources/Readback/Replies.swift:75–87`, `Sources/Readback/AppDelegate.swift:318–324`.
- Local peer authentication, exact Codex hash validation, arm64-only v0.4 packaging, and safe handling of an intervening edit to a tool's config remain open. See the appendix for evidence and the baseline comparison.
- Verify a live older Claude/Codex session across an app replacement, a cancelled download while another voice is speaking, and actual Codex and Orca approval. The independent passes reviewed the native event and process paths statically. The scratch checks did not drive these host flows.

## Verification

- Clean source archives on arm64 macOS 27.2.1, Apple Swift 6.4.2 and Claude Code 2.1.332. The base passed 62 XCTest cases with one opt-in skip, 38 Swift Testing cases and six Claude plugin tests. #1 passed 138 XCTest cases with one opt-in skip, 43 Swift Testing cases and seven Claude plugin tests.
- The `build-app.sh` build and `codesign --verify --deep --strict` passed. The compact-fixture opt-in `RoundTrip` case failed on the base and both PR heads. The JSON writer reformats it.
