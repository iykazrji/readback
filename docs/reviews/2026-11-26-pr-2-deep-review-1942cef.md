# PR #2 · Home, controls, audio and Check for updates

**Verdict · Blocked**

Reviewed [PR #2](https://github.com/iykazrji/readback/pull/2) from its stack base `a6b2b88a22a9585140f03e47990d1d2993b4fe2d` to head `1942cefe6e7378b3cf18849b7c342a9390864ae4`. This layer changes 80 files. Inherited findings are in the [#1 review](2026-11-26-pr-1-deep-review-a6b2b88.md). The [coverage and evidence appendix](2026-11-26-readback-prs-deep-review-coverage.md) records candidate dispositions and independent review coverage.

## Findings

### High · Retrying a voice failure clears the already installed engine

**Introduced.** A fresh install can finish installing Python and the engine, write the engine receipt, then fail while downloading or warming the model. **Try again** enters the complete install path. The new `uv venv --clear` deletes the valid environment before any new package install succeeds. Another network error or Cancel now leaves the previously usable environment gone.

- **Code** `Sources/Readback/Runtime.swift:105–107,152–192,198–205`, `Sources/ReadbackCore/EngineInstall.swift:3–9`, `Sources/Readback/Window/VoicesPage.swift:250–266`.
- **Evidence** The draft's bundled uv 0.10.4 rejected the old invocation on a populated scratch venv with exit 2 and preserved a sentinel. With `--clear`, it exited 0 and removed the sentinel.
- **Fix** Distinguish failure before the engine receipt from failure in the voice step. Retry only the voice step when the receipt and executable are healthy, and restrict clearing to an incomplete environment Readback owns.

### High · The advertised Claude commands can be absent after upgrading

**Worsened.** A person who connected only a separate Claude login using the documented `CLAUDE_CONFIG_DIR` setup can update and start a new Claude session but still have the copied 0.4 mod. Launch refreshes the shared mod only if the default Claude home appears connected or incomplete. The old mod registers the bare commands. The new namespaced command files are present only in the new bundle.

- **Code** `Sources/Readback/Connections.swift:32–37,97–109`, `Sources/ReadbackCore/IntegrationFiles.swift:47–56,208–249`, `integrations/claude-code/readback/commands/{read,speak}.md`. Second-login setup is documented at `AGENT-SETUP.md:68` and `docs/README-for-friends.md:35`.
- **Evidence** The archived 0.4 plugin uses `command.register` for the bare names. The signed 0.5 archive contains both command files. A scratch migration using both shipped bundles found the default home disconnected and the alternate home incomplete. The launch refresh decision left the copied mod at 0.2.0. Reconnecting the alternate home copied 0.3.0 and the missing commands. This layer first changes the names.
- **Fix** Refresh an existing, owned shared mod independently of the default Claude settings row. Test an upgrade where only a nondefault home is connected.

### High · Turning off audio ducking leaves the system audio tap running

**Introduced.** Switch **Lower other sounds while reading** off during playback. Core returns Restore and records its state as normal. The adapter raises gain but leaves its muted-source system audio tap and playback device active for 60 seconds. The feature is off in Settings while system audio is still routed through Readback.

- **Code** `Sources/Readback/AppDelegate.swift:79–87,305–327`, `Sources/ReadbackCore/OtherAudioDucking.swift:47–54`, `Sources/Readback/OtherAudioLowerer.swift:40–43,64–69,86–100,115–118`.
- **Evidence** The switch-off event and normal playback completion share the `restore()` adapter. That method always schedules the 60-second linger when running. The test at `OtherAudioDuckingTests.swift:62–67` ends at the Core state change. The tap passes audio through in memory.
- **Fix** Give opt-out its own adapter effect that releases the tap promptly, with only the brief fade needed to avoid a click. Reserve the linger for the enabled setting.

### High · The updater writes the absolute install path to its local log

**Introduced.** Install from a home-relative copy, such as one in the user's own Applications or projects folder. A successful replacement writes the entire path, including the account name and any identifying folder names, to the app log. The skill treats a new personal value in a log as a merge blocker.

- **Code** `Sources/Readback/Updater.swift:177–186`, `Sources/Readback/Log.swift:13–20`.
- **Evidence** Unified-log privacy applies to that OS log call. The same message reaches the private on-disk log as plain text. No reply content is involved.
- **Fix** Log the old and new versions and a bounded failure reason. The bundle location is unnecessary for a success record.

### Medium · The install gate expires as soon as the user clicks

**Introduced.** Click **Install and relaunch** when no other work is running. While the update ZIP downloads or is checked, start a model download, engine installation, or Connect. The updater replaces and quits as soon as verification returns. It checks busy state only on the original click. Engine removal is also absent from that initial predicate.

- **Code** `Sources/Readback/Updater.swift:30–39,90–111,177–199`, `Sources/Readback/AppDelegate.swift:65–70`, `Sources/Readback/Runtime.swift:247–275`.
- **Evidence** Complete async path through two suspension points and an unconditional swap. The spec expressly waits for active downloads and integration work. Core tests cover busy state supplied at the click.
- **Fix** Keep the verified ZIP staged and recheck activity immediately before swap. Use one predicate for the card and actual operation gate, including work that can be started while checking.

### Medium · Writable copies on a second volume get an update that cannot install

**Introduced.** A writable app and folder on an external or secondary volume pass the card's eligibility check. The new bundle is unpacked on the startup volume. Foundation's replacement call rejects the cross-volume move.

- **Code** `Sources/Readback/Updater.swift:77–98,177–185`.
- **Evidence** The same Foundation call on an isolated APFS volume reported both target and parent writable, then returned Cocoa 512 with POSIX 18, “Cross-device link.” The old marker remained present. [Apple FileManager replacement contract](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat%28_%3Awithitemat%3Abackupitemname%3Aoptions%3A%29?language=_2)
- **Fix** Create the final replacement staging directory with Foundation's `.itemReplacementDirectory` for the destination bundle.

### Medium · A matching digest and bundle ID can still replace a working app with an unlaunchable bundle

**Introduced.** If a later release accidentally targets the wrong architecture or a higher macOS minimum, signature integrity and the manifest version can still pass. The old app is removed before macOS attempts to open the new one. The detached helper has no way to return a launch error, and the original app quits even if the helper fails to start. The check also accepts a bundle version that differs from the version offered.

- **Code** `Sources/Readback/Updater.swift:144–159,177–199`, `Sources/ReadbackCore/Updates.swift:97–109`.
- **Evidence** A Core probe showed an offered 0.6.0 release can pass manifest checks with a 0.7.0 bundle. The check reads neither architecture nor platform minimum. The supplied 0.5 archive itself declares macOS 15 and carries only arm64 binaries. A future incompatible update is a code-path finding.
- **Fix** Validate the announced version, executable slices and OS eligibility before replacement. Keep a recoverable previous bundle until the replacement reports that it launched.

### Medium · Try again can reuse a stale release indefinitely

**Introduced.** A checksum failure or withdrawn asset gets a corrected upload or a subsequent release while the app stays open. The failure card's **Try again** uses the old URL and digest. The check and close events do nothing in the install-failed state. The read-only card has a similar path with no recheck after the underlying location is fixed.

- **Code** `Sources/ReadbackCore/Updates.swift:243–250,269–277,291–309`, `Sources/Readback/Window/VersionCard.swift:59–67,91–102`.
- **Evidence** A production `UpdateFlow` probe reported `can refresh release metadata after failure: false` after a digest mismatch and close attempt.
- **Fix** Offer **Check again** in terminal failure and unavailable states, or refresh the metadata before retry.

### Medium · Home can make the wrong reply the session's newest

**Introduced.** Two replies within one second retain their insertion order on disk but decode to identical timestamps. Home sorts their session by an unrelated UUID tie-breaker. It can select the earlier reply for the preview and the “play newest” action.

- **Code** `Sources/ReadbackCore/ReplyHistory.swift:65–68,130–141`, `Sources/ReadbackCore/SessionSummary.swift:20–30`, `Sources/Readback/Window/Home/SessionsList.swift:75,100,111`.
- **Evidence** A round trip with two distinct arrival times in one second loaded `["Newer", "Older"]` with tied timestamps. `SessionSummary` reported `"Older"` as newest.
- **Fix** Preserve the history's insertion order as the stable tie-breaker for replies inside each session.

### Medium · Setup reports a busy tool as connected

**Introduced.** While a tool is connecting or disconnecting, Home's Setup chip shows “connected” regardless of the previous and current status. The busy branch returns the same value as a healthy connection, and its consumer always renders “connected.”

- **Code** `Sources/Readback/Window/Home/SetupChips.swift:81–106`, `Sources/Readback/Connections.swift:64–92`.
- **Fix** Render a connecting or disconnecting state from `row.busy` and use “connected” only for succeeded status.

## Plausible and smaller findings

- A hash-only line is a valid queue chunk but rewrites to an empty string. The app passes it to synthesis and can abort later audible chunks if the voice rejects it. The production macOS voice on this host returned an audio file for the empty string. Neural outcomes and silent duration on other versions need runtime verification. `Sources/Readback/Reader.swift:72–74,98–115`, `Sources/ReadbackCore/SpokenText.swift:57,137–151`.
- A new reading during the tap's final 80 ms fade cancels its teardown while leaving the target at zero. Other sound remains silent during the new preparing phase. The state path is static. A native output check can confirm the audible effect. `Sources/Readback/OtherAudioLowerer.swift:45–53,88–100`.
- On Home, the Now card's 600 ms hide delay is shorter than the ordinary 800 ms handoff. A session reply's waveform stays animated while paused or preparing, and the compact Now control says “Play” while its next action pauses pending playback. These follow from the state predicates. `Sources/Readback/Window/Home/NowCard.swift:29–41,68,205–218`, `Sources/Readback/Window/Home/SessionsList.swift:109–113,173–197`, `Sources/Readback/AppDelegate.swift:276–280`.
- The custom dropdown's fallback moves it above the button without checking room above. Setting geometry for a voice menu near the edge of a short display can place part of it offscreen. The Home reply rows also replace their spoken accessible names with repeated “Reply” labels. The spec's keyboard and assistive-technology paths need native evaluation. `Sources/Readback/Window/Components/Dropdown.swift:111–124,203–214`, `Sources/Readback/Window/Home/SessionsList.swift:173–197`.
- GitHub supplies both metadata and the ZIP digest, and the shipped bundle is ad-hoc signed. The updater verifies integrity under the documented GitHub trust model. A stable publisher signature would require a separate trust decision. The user guide's “genuine” wording should match that model. `docs/superpowers/specs/2026-11-26-update-check-design.md:18–29`, `Sources/Readback/Updater.swift:145–158`, `docs/README-for-friends.md:64`.

## Verification

- Clean Swift suite passed 139 XCTest cases with one opt-in skip and 150 Swift Testing cases. The Claude Code plugin suite passed eight tests. Release build and deep strict signature verification passed.
- The overlap gate, relaunch, Core Audio and native UI were reviewed at the app boundary. Scratch checks covered the Foundation swap, bundled uv, Core state, and macOS synthesis. Full keyboard and VoiceOver interaction, Bluetooth and multichannel output, and older macOS runtime behavior remain unverified.
