# Check for updates, from the sidebar

Owner's ask, 2026-11-26: Readback should be able to update itself, and 0.5.0 shouldn't ship without it, because whoever installs 0.5.0 otherwise has no way to hear about 0.6. Decisions, all the owner's, the same day:

- The check is **manual**: a "Check for updates" line in the sidebar's version card, nothing automatic. No check at launch, no timer. That keeps PRODUCT.md's hard line ("the only network traffic is downloads the person asked for") as it is, with the check and the update added to what the person can ask for.
- When there's a newer version, the button **installs and relaunches**. It doesn't just open a web page.
- **Our own small updater**, not Sparkle. Sparkle's windows aren't Readback's look, and fitting its framework into our hand-built bundle and publishing an appcast is a lot of weight for one button.
- At rest, the version card shows **a second line, "⟳ Check for updates"** (mockup variant 2, `.superpowers/brainstorm/35361-1795717349/content/update-card.html`).

Who and when: a friend running Readback who heard there's a new version, or just wonders. They open the window, click the line, and either learn they're current or install the new one in one more click, without unzipping, dragging, or clicking Open Anyway again.

## Goals, non-goals, anti-goals

- Goal: one click to check, one click to install, and Readback reopens as the new version, still connected to every tool. Codex doesn't ask to approve hooks again, because the CLI path doesn't change.
- Non-goals: automatic checks, release notes inside the app ("What's new" opens the release page), updating the voice engine, rolling back.
- Anti-goals: a half-installed app. Every check happens before the swap, the swap is atomic, and any failure leaves the old copy exactly as it was. No request the person didn't trigger. Nothing about the person in the request: a generic `Readback/<version>` User-Agent and nothing else.

## Constraints

- Releases live at `github.com/iykazrji/readback`. The latest is read from `https://api.github.com/repos/iykazrji/readback/releases/latest` (unauthenticated, 60 requests an hour per IP, plenty for a button). This makes the release layout a contract: the tag is `v<version>`, there's an asset named exactly `Readback.zip`, and inside it is `Readback/Readback.app` with bundle id `local.readback`. AGENTS.md and DEVELOPMENT.md record that.
- GitHub gives each asset a `digest` (`sha256:<hex>`, checked on v0.4.0). The download must match it.
- The build is ad-hoc signed and not notarized. The swap has to clear the quarantine flag from the new copy before reopening, or macOS refuses to open it.
- Ad-hoc signatures change with every build. macOS ties the audio-capture permission ("lower other sounds") to the signature, so it will probably ask again after an update. This isn't new (a manual update does the same), and the cure is a stable signing identity, which is separate work. Unverified on this Mac.
- `READBACK_*` variables (test copies) have to survive the relaunch. A spike on 2026-11-26 showed a plain `open` reopens a test copy against the real home. The relaunch passes each `READBACK_*` variable with `open --env`.

## Approaches

- **Own updater (picked).** Core parses the release, compares versions, checks the digest and the new bundle, and drives the card's states. The app downloads, unzips, swaps and relaunches. It trusts GitHub as much as the first install does (AGENT-SETUP downloads the same URL), so it adds no new weak spot. It wouldn't stop a hijacked GitHub account. An Ed25519 signature on the zip could be added later, at the cost of a key the owner keeps forever.
- **Sparkle 2.10.1 (not picked).** Proven install and relaunch, and EdDSA built in. Not picked for its UI, the framework embedding and signing in our hand-built bundle, and an appcast per release.
- **Open the download page (not picked).** Least to build, but the person has to replace the app and click Open Anyway again. The owner chose install and relaunch.

## How it behaves

The version card at the bottom of the sidebar, under the Voice card, shows one of these:

1. **At rest:** "Readback 0.5.0" (click opens About), and under it a quiet line "⟳ Check for updates".
2. **Checking:** the line reads "Checking…" with the arrow turning (still under Reduce Motion).
3. **Up to date:** "Readback 0.5.0 ✓" and "You have the newest version." for 3 seconds, then back to rest.
4. **Available:** "Readback 0.6.0 is out", "You have 0.5.0.", a primary "Install and relaunch" button, and a quiet "What's new" that opens the release page.
5. **Can't replace itself:** shown instead of Available when the app can't be swapped in place. Either its folder or bundle isn't writable ("It isn't allowed to change the folder it's in. Download 0.6.0 and replace it yourself."), or macOS is running it from a temporary copy (`/AppTranslocation/` in the path: "macOS is running it from a temporary copy. Move Readback to Applications, open it, and check again."). One button: "Download page".
6. **Downloading:** "Downloading 0.6.0", a meter, "12.4 of 21.4 MB" and a quiet Cancel. Cancel goes back to Available.
7. **Installing:** "Installing 0.6.0" and "Readback will close and reopen in a moment." Then the app quits and the new one opens.
8. **Couldn't check:** "Couldn't check for updates", a reason, "Try again" and a quiet "Close" (back to rest). Reasons: no connection ("Readback couldn't reach GitHub. Check your internet connection."), rate-limited (403 or 429: "GitHub is turning requests away for a moment. Try again in a few minutes."), anything else ("GitHub sent back something Readback didn't expect.").
9. **Couldn't install:** "Couldn't install 0.6.0", a reason, "Try again" and a quiet "Download page". Reasons: the digest doesn't match ("The download didn't match the one on GitHub, so Readback left your copy as it is."), the zip has no Readback in it, it's a different app or not newer, the signature check fails, or the swap fails. Each reason ends with "Readback left your copy as it is."

Install, in order, stopping at the first failure:
1. Download `Readback.zip` to a fresh temp folder, with progress.
2. Check its sha256 against the asset's digest. If GitHub gave no digest, that's a failure, not a pass.
3. Unzip with `ditto -x -k`. Take `Readback/Readback.app`, or failing that, the only `.app` at the top.
4. Read its Info.plist. The bundle id must equal the running app's, and its version must be newer than the running one (numeric compare, `0.10.0` beats `0.9.0`).
5. `codesign --verify --deep --strict` on it.
6. Clear `com.apple.quarantine` from it.
7. `FileManager.replaceItemAt(running bundle, withItemAt: new)`: an atomic swap that removes the old copy (proven in the spike while the app ran).
8. Start a detached `/bin/sh` that waits for this process to exit, then runs `open` (with `--env` for each `READBACK_*` variable) on the bundle path, then quit. A reading in progress stops. Waiting replies stay in History.

After it reopens, the new version clears its own quarantine flag as it already does, re-copies the Claude Code mod only if its bytes changed, and the hooks keep working because the CLI path is the same.

## Where the code goes

- Core `Updates.swift`: `Release` (version, zip URL, sha256, page URL) parsed from the releases JSON; `isNewer(_:than:)`; `UpdateCard` state and the transitions (the `ReplyQueue` pattern: the app reports what happened, Core says what to show and what to do next); the install checks that don't need the system (digest of a file, what the new Info.plist says, whether a path can be replaced); the failure copy. All tested.
- App `Updater.swift`: the URLSession calls, `ditto`, `codesign`, `xattr`, the swap and the relaunch. Thin.
- Sidebar: the version tile becomes `VersionCard`, drawn from the state.
- `READBACK_UPDATES_URL` points the check at another JSON, for testing against a local fake release. Ignored when unset.

## Left to the builder

The card's spacing follows the sidebar's Voice card (10 pt padding, 12 pt radius). Exact log lines. How progress is reported (a download delegate or async bytes).
