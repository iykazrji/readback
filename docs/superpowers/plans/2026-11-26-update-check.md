# Check for updates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A manual "Check for updates" in the sidebar's version card that finds a newer GitHub release, installs it in place and relaunches.

**Architecture:** Core `Updates.swift` holds the release parsing, version compare, digest, the checks on the new bundle, the relaunch command and the card's state machine (`UpdateFlow`), all tested. The app's `Updater` carries out the effects `UpdateFlow` returns (fetch, download, install). The sidebar's `VersionCard` draws the state.

**Tech Stack:** Swift, SwiftUI, Foundation URLSession, CryptoKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-26-update-check-design.md`

## Global Constraints

- No network request unless the person clicked. Request headers: `Accept: application/vnd.github+json`, `User-Agent: Readback/<version>`. Nothing else.
- Release contract: tag `v<version>`, asset `Readback.zip`, `Readback/Readback.app` inside, bundle id equal to the running app's.
- Any failure before the swap leaves the installed copy untouched; every install failure message ends "Readback left your copy as it is."
- The relaunch passes every `READBACK_*` variable with `open --env`.
- Copy is the spec's, word for word.

## Review Focus

- A release with no `Readback.zip` or no digest: check fails as "unexpected" / install fails as no digest, never installs (Task 1 tests `parseRejectsMissingZip`, `noDigestIsAFailure`).
- `0.10.0` vs `0.9.0`, and `v` prefixes: numeric compare (Task 1 `newerIsNumeric`).
- A test copy relaunching: `READBACK_*` variables survive, others don't leak (Task 1 `relaunchCarriesReadbackVariables`).
- Clicking twice, or Install while downloading: ignored (Task 1 `flowIgnoresRepeats`).
- An app path under `/AppTranslocation/` or not ending in `.app`: can't-replace, never a swap (Task 1 `replaceProblems`).

---

### Task 1: Core `Updates.swift`

**Files:** Create `Sources/ReadbackCore/Updates.swift`, `Tests/ReadbackCoreTests/UpdatesTests.swift`.

**Interfaces (produces):**
- `public struct Release: Equatable { version, zip: URL, sha256: String?, page: URL, size: Int64? ; static func parse(_ data: Data) throws -> Release }`
- `public enum Updates { static let defaultURL; static func latestURL(environment: [String: String]) -> URL; static func isNewer(_:than:) -> Bool; static func sha256(of: URL) throws -> String; static func replaceProblem(bundlePath: String, writable: Bool) -> ReplaceProblem?; static func check(newInfo: [String: Any], bundleID: String, current: String) -> InstallFailure?; static func relaunch(pid: Int32, app: String, environment: [String: String]) -> [String] }`
- `public enum CheckFailure { offline, busy, unexpected; init(status: Int?, error: Error?) ; var message }`, `public enum InstallFailure { ... ; var message }`, `public enum ReplaceProblem { readOnly, translocated, notAnApp ; var message }`
- `public struct UpdateFlow { var card: UpdateCard; mutating func check() -> UpdateEffect?; checked(_:current:problem:) -> UpdateEffect?; install() -> UpdateEffect?; progress(received:total:); downloaded(); failed(_ :InstallFailure); cancel() -> UpdateEffect?; close(); upToDateExpired() }`, `public enum UpdateEffect { fetch, download(Release), cancelDownload, expireUpToDate(seconds: Double) }`

- [ ] Tests first, then the code; `swift test` green; commit `feat: update check (Core)`.

### Task 2: App `Updater` and the sidebar `VersionCard`

**Files:** Create `Sources/Readback/Updater.swift`, `Sources/Readback/Window/VersionCard.swift`; modify `AppDelegate.swift` (own an `Updater`), `MainWindow.swift` (sidebar uses `VersionCard`).

- [ ] Build with 0 warnings.
- [ ] End to end on the isolated test copy with `READBACK_UPDATES_URL` pointing at a local fake release (a newer build of the test copy, its real sha256): check, install, relaunch keeps `READBACK_*`; then a wrong digest, no internet, up to date.
- [ ] `ui-done-check`; commit `feat: Check for updates in the sidebar, installs and relaunches`.

### Task 3: Docs and contracts

- [ ] PRODUCT.md hard line names the update check; AGENTS.md and DEVELOPMENT.md record the release contract; README-for-friends gets "Updating"; commit.
