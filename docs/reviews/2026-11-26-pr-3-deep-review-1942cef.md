# PR #3 · Readback 0.5.0 release

**Verdict · Blocked**

Reviewed [PR #3](https://github.com/iykazrji/readback/pull/3) against `main` at `b4d6449e1d5a9bb49e8437da50cdff8a3594772c`. The release head is `1942cefe6e7378b3cf18849b7c342a9390864ae4`, identical to [PR #2](https://github.com/iykazrji/readback/pull/2). The aggregate diff changes 110 files. The [#1 review](2026-11-26-pr-1-deep-review-a6b2b88.md), [#2 review](2026-11-26-pr-2-deep-review-1942cef.md), and [coverage appendix](2026-11-26-readback-prs-deep-review-coverage.md) cover the two layers.

## Release blockers

- Cancelling a voice download can delete older cached revisions. Identical replies in two turns can collapse into one History entry when `/read` overlaps the second Stop hook. The release also adds a state-changing command handler without local caller authentication. These findings are attributable to #1.
- A voice-only installation failure can make **Try again** clear a usable engine. The newly named Claude commands can be absent after an alternate-home-only upgrade. The audio tap lingers after opt-out, and the updater writes the full installation path to the local log. These findings are attributable to #2.
- **The draft is arm64-only.** The public README and setup instructions promise an Intel fallback using macOS voices. The app, CLI and bundled uv are all `arm64`. The public 0.4.0 ZIP has the same architecture gap, so it is pre-existing against `main`. Publishing this draft still ships the gap to Intel users. Either provide an Intel-capable release and validate it, or align the published minimum requirements with this artifact. `README.md:9`, `AGENT-SETUP.md:14–15`, `scripts/build-app.sh:16–27`.

## Draft artifact verified

| Check | Observed |
|---|---|
| GitHub release | Draft `v0.5.0` targets `main`. The public latest endpoint still returned `v0.4.0`. |
| Exact asset | `Readback.zip`, 22,177,973 bytes. SHA-256 `b33bc5febd0bdeca44f320822ae53869eb4fab0f56b2c535e08dd7da88d27d93` matched GitHub. |
| Archive | `unzip -tq` passed. Extraction produced `Readback/Readback.app` and `Readback/README.md`. |
| App identity | Bundle ID `local.readback`, app version `0.5.0`, bundle build `202611261401`. The executable load command declares macOS `15.0`. |
| Signing | `codesign --verify --deep --strict` passed on the unpacked app. Signature is ad hoc. |
| Packaged resources | The draft and clean build resource trees matched byte-for-byte. Claude mod manifest declares `0.3.0`. Both namespaced command files are present and native validation recognized them. All seven generated Codex plugin files and both bundled Codex icons matched v0.4.0 for the same CLI path. |
| Clean source verification | Rebuilt from the pinned tree, verified its signature, and passed 139 XCTest cases with one opt-in skip, 150 Swift Testing cases and eight Claude Code plugin tests. |

The rebuilt package used a new bundle build number. The comparison covers signed draft identity, declared support, layout, bundled resources and verification against the pinned source. It does not establish byte-reproducible binaries.

## Remaining release checks

- Verify an isolated upgrade with only an alternate Claude home connected, then open a fresh session and check that both namespaced commands appear and work. Verify live Codex/Orca approval in the same supported migration flow. Existing shared plugin paths and the release-ready status need checking together.
- Validate a real version-to-version update after a newer public asset exists. A latest-release metadata pull and the local simulated install exercise different parts of the update path. Also exercise a busy operation started after the ZIP begins downloading, followed by a successful relaunch after it finishes.
- On each advertised Mac architecture and minimum OS, launch the distributed app from a clean install and read a reply using the macOS voice. The supplied archive has no Intel executable slice. Exercise system-audio permission and release from the tap, voice download cancellation, and keyboard and VoiceOver behavior on a supported Mac.
