# Ledger for the 2026-11-26 deep reviews of PRs #1–#3

This answers [PR #1's review](2026-11-26-pr-1-deep-review-a6b2b88.md), [PR #2's](2026-11-26-pr-2-deep-review-1942cef.md), [PR #3's](2026-11-26-pr-3-deep-review-1942cef.md) and the [coverage appendix](2026-11-26-readback-prs-deep-review-coverage.md). Fixes for #1 are on `untangle-protocol-queue-integrations`, which was merged into `fix/steady-download-numbers` before #2's fixes. #3's head is #2's head, so it carries both once `release/0.5.0` is moved to it.

Every fix has a test that failed before it and passes after, unless the row says why not: the app and the CLI have no test target (AGENTS.md), so a fix that only lives there was checked by building it and reading the path through. Tests that start with `DeepReview` are in `Tests/ReadbackCoreTests/DeepReview20261126Tests.swift`.

Final run on `fix/steady-download-numbers`: 166 XCTest cases (one opt-in skip), 153 Swift Testing cases, the Claude Code mod's tests, and `scripts/build-app.sh` with `codesign --verify --deep --strict`.

## PR #1

| ID | Claim | Verdict | Invariant | Siblings | Fix | Test: before / after |
|---|---|---|---|---|---|---|
| P1-1 | Cancel deletes model data that was there before the download | Real | Cancel takes back only what that download added | none | 00d1b82 | `ModelCacheTests.cancellingADownloadKeepsWhatWasThereBefore`: with the old whole-model removal, the older revision's weights were gone and 5,806 bytes freed; after, they stay, 1,600 freed, refs/main back to the old commit. Two more cases: a first download goes completely, a file another model links to stays |
| P1-2 | Two turns that both say "Done." become one History row | Real | A reply from an earlier turn never stands in for this turn's | `received()` stamped rows with the real clock, not the queue's `now` | 238b9f3 | `DeepReviewQueueTests.testTwoTurnsSayingTheSameThingAreTwoReplies`: 1 row before, 2 after, each with its own time |
| P1-3 | `/command` has no local caller authentication | Owner | | the base already had the same on `/session`, `/speak`, `/replay` | none | Options are in the hand-off |
| P1-4 | A download that can't open its log stays on screen with nothing to cancel | Real | Every announced download ends on every path | the step failing to launch ended the row without a failure, so there was no Try again | 00d1b82 | App only. The log is opened before the download is announced; both failures now end like a nonzero exit. Built, not run |
| P1-5 | The player can cancel a different voice's download | Real | The player shows and cancels only its own voice's download | none (Voices' install row only shows progress; its Cancel stops the install) | ba71b64 | App only. Built, not run |
| P1-6 | A waiting reply can be trimmed out of History before it speaks | Real | The reply being read stays in History until it has an outcome | none | 238b9f3 | `testTheReplyBeingReadIsntTrimmedBeforeItSpeaks`: gone and not restorable before; kept after. `ReplyHistoryCapTests.testPlayingThroughABacklogDropsTheOldestFirst` asserted the bug and was changed, with the reason in it |
| P1-7 | A 0.4 helper and a newer app (or the reverse) can't do /read | Real | Both versions in the migration window understand /read | none | ac5195d | `DeepReviewCompatibilityTests`: 404 before, `.replay` after. The reverse (new helper, old app) now says to reopen Readback on a 404; CLI only, built, not run |
| P1-8 | Saving History makes a read-only folder writable again | Real | Making something private only removes group and other bits | `LogFile.append` and the engine log both forced 0600; a read-only log was replaced outright | 38e2800 | `DeepReviewPrivateFilesTests`: 0700 and a successful save before; 0500 and a thrown error after. Same for a 0444 log |
| P1-x | (Found here) the History recovery log writes the full path | Real | A log names versions and file names, never paths that name the person | P2-4 is the same class | 15b3b3c | Log line only |

Pre-existing and left alone: HTTP 202 before History is on disk, exact Codex hash validation, an edit to a tool's config made between Readback's read and write, and the arm64-only package (P3-1).

## PR #2

| ID | Claim | Verdict | Invariant | Siblings | Fix | Test: before / after |
|---|---|---|---|---|---|---|
| P2-1 | Try again after a voice-step failure clears a working engine | Real | An install starts past the engine once it's installed | `VoiceServer.isInstalled` checked only the server, `Runtime` also the receipt: now one `ReadbackPaths.engineIsInstalled` | ffd5a1a | `DeepReviewEngineInstalledTests`. The uv path itself wasn't run here |
| P2-2 | A login connected only through CLAUDE_CONFIG_DIR keeps the 0.4 mod | Real | The shared mod copy is refreshed whenever it exists | none | 127be88 | `DeepReviewSharedModTests`: copy stayed 0.2.0 without command files before; 0.3.0 with them after |
| P2-3 | Switching off "Lower other sounds" leaves the tap for 60 s | Real, and wider | Switching it off lets the tap go now | switching off while the tap lingered after a reading did nothing at all; a reading starting in the last 80 ms fade left the target at silence | e05e891 | `DeepReviewDuckingTests`: `restore` and `nothing` before; `release` after. `OtherAudioDuckingTests.switchingOffMidReadingRestoresAtOnce` was changed, with the reason. Core Audio itself not exercised |
| P2-4 | The updater logs the full install path | Real | as P1-x | P1-x | b831d71 | Log line only |
| P2-5 | Install checks busy work only at the click; engine removal not counted | Real | The card and the swap ask one question, and the swap asks it again | two copies of the busy check (card and app) became one | b831d71 | `testRemovingTheEngineHoldsInstallAndTheSwapAsksAgain`. The recheck before the swap is app only; built, not run |
| P2-6 | A copy on a second volume can't be replaced | Real (reviewer's Foundation probe) | Stage on the destination's volume | none | b831d71 | Not reproduced here (no second volume). Uses `.itemReplacementDirectory` as Apple's contract asks |
| P2-7 | A bundle for the wrong version, CPU or macOS can replace a working app | Real, partly fixed | Only a bundle that's the offered version and runs here replaces the app | reading slices with `lipo` would ask to install developer tools (R1-2) | b831d71, 39509a6 | `testTheNewAppMustBeTheOneOfferedAndRunHere`, `DeepReviewMachOTests`. Keeping the old bundle until the new one reports it launched is not done: owner |
| P2-8 | Try again reuses a stale release forever | Real | Try again and Check again ask GitHub again | the can't-replace card had no way to check again | b831d71 | `testTryAgainFetchesTheReleaseAgain`, `testCantReplaceCanCheckAgain`. `UpdatesTests.installFailsThenTryAgain` was changed, with the reason |
| P2-9 | Home can show the older of two same-second replies as newest | Real | Replies keep the order they arrived in | History saved whole seconds; Undo after Clear sorted without a stable tie | bd613ba | `DeepReviewSameSecondTests`: "Older" before; "Newer" after; a whole-second history still loads. `SessionSummaryTests.tiedSessionsKeepOneOrder` was changed, with the reason |
| P2-10 | Setup chip says "connected" while busy | Real | "Connected" only once it is | none | 8a669b7 | App view only, built |
| P2-a | A "hash-only" line is voiced as an empty string | Real, other cause | Nothing empty is sent to a voice | the queue's "speakable" check used a different definition | 4add08f | `DeepReviewVoicedChunkTests`. A lone `#` is spoken as written; the empty one is a line of commit hashes |
| P2-b | A reading in the tap's last 80 ms fade leaves other sound silent | Real by code path | as P2-3 | | e05e891 | Not exercised |
| P2-c | Now card timing, waveform moving while paused, "Play" label while it pauses | Not changed | | | | UI: needs `ui-done-check` on a build |
| P2-d | Dropdown can open off a short screen; reply rows all read "Reply" to VoiceOver | Not changed | | | | UI: as above |
| P2-e | "Genuine" overstates what the update check proves | Real | Copy says what's checked | the spec quoted the same message | d09eb74 | Copy only |

## PR #3

| ID | Claim | Verdict | Note |
|---|---|---|---|
| P3-1 | The draft is arm64-only while the docs promise an Intel fallback | Owner | Pre-existing in 0.4.0. Either a universal build or Apple silicon in the stated requirements |
| P3-2 | #3 carries #1 and #2's blockers | Follows #1 and #2 | `release/0.5.0` has to move to the new #2 head, and the draft release has to be rebuilt from it |

## Fix review

| Round | ID | Finding | Fix | Test |
|---|---|---|---|---|
| 1 | R1-1 | In 0.5, Claude Code's commands are files. If its prompt hook fires for `/readback:read`, P1-2's turn boundary would add a second row every time, or stop the reading it starts | 8ee4cbc | `DeepReviewOwnCommandTests`: a new-turn stop before; nothing after |
| 1 | R1-2 | `/usr/bin/lipo` asks to install developer tools on a Mac without them | 39509a6 | `DeepReviewMachOTests` |
| 1 | | Stale words in the update spec and a Runtime comment | 39509a6, d09eb74 | |
| 2 | | No findings | | |

## Still unverified

These need a real Mac session, a device or a release, not this tree: whether Claude Code's UserPromptSubmit fires for a command file (R1-1 makes it safe either way), an old Claude session across the app's replacement, a real version-to-version update with a newer public asset, a copy on a second volume, the Core Audio tap letting go, a voice-step retry with the real uv and network, and every UI change above on screen.
