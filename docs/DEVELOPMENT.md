# Readback: building and how it works

A macOS menu bar app that reads coding agents' replies out loud (Claude Code, Codex, OpenCode), with a superwhisper-style floating player: pause, sentence back and forward, a scrubber, speed, Esc to close. Voices run on the Mac: the macOS voices out of the box, or Kokoro / Qwen3-TTS through mlx-audio, which the app installs itself.

What to send someone: the latest release on GitHub, or `build/Readback.zip` and `docs/README-for-friends.md`.

## Layout

```
Sources/ReadbackCore     logic with no UI: markdown → speakable text, sentence chunks, the control
                         protocol (ControlProtocol.swift: routes, request bodies, the /speak and /read
                         answers), the reply queue (ReplyQueue.swift), hook payloads, the bundle
                         layout (AppBundle.swift), the voice catalog, order-keeping JSON, the
                         integration edits (one ToolHome per tool folder, Orca's Codex included),
                         and the Codex plugin (Codex.swift: its files, /speak and /read parsing,
                         reading approvals from config.toml, finding the codex command)
Sources/Readback         the app: menu bar, floating player (with the reply list), the main
                         window (Window/: Home, History, Voices, Reading, Connections, About),
                         voice engines, engine installer, control server on 127.0.0.1:8908
Sources/readback-cli     the `readback` command the tools' hooks run (bundled as Contents/Helpers/readback)
integrations/claude-code/readback
                         the Claude Code mod: /readback:speak on|off, /readback:read (commands/*.md, answered by its command.run hooks), the "Reading aloud · Stop" band
Resources                third-party notices, the app icon (AppIcon-1024.png: Cadence, rendered in
                         Blender) and its 18 pt menu bar template
design/icon              the icon's Blender source and design notes (see NOTES.md to rebuild it)
scripts/build-app.sh     builds build/Readback.app and build/Readback.zip
docs/README-for-friends.md
```

## How a reply gets read

1. The tool's Stop hook runs `readback hook <tool>` with the hook's JSON on stdin. OpenCode has no hooks file, so a plugin does the same on `session.idle`.
2. The CLI posts the reply to the app (`POST /speak` with `session` and `source`). It starts the app only if the reply is meant to be read, checking the same switches the app does (`ReadingSwitches`).
3. Every reply goes into the history (`~/Library/Application Support/Readback/history.json`, last 50). The app reads it if that session switched read-aloud on (`/readback:speak on` in Claude Code, `/speak on` in Codex) or that tool's "read every reply" switch is on. `ReplyQueue` in Core makes every one of these decisions; the app carries out what it returns. If something is already playing it waits its turn (or cuts in, per Reading → "Switch to it"); when a reply ends, the oldest waiting one plays. Close/Esc means quiet: what was waiting stays in History unplayed. A tool's "new message" hook drops only that session's reading and waiting replies.
4. The reply is cleaned (code blocks and tables become a short spoken note), split into sentence chunks, and voiced chunk by chunk. Each chunk is rewritten for the ear just before it's voiced (`SpokenText`: paths as their file, no commit hashes, symbols as words); the player still shows the reply as written. Playback starts on the first chunk while the rest are made.
5. The tool's UserPromptSubmit hook runs `readback stop`, which stops the reading only if it came from the same session. Codex's runs `readback prompt codex` instead, which does the same for an ordinary prompt and answers `/speak on|off` and `/read` itself, blocking the prompt so the model never sees it.
6. The commands from either tool (`/readback:speak` and `/readback:read` in Claude Code, `/speak` and `/read` in Codex) go to `POST /command`, and the app writes the answer (`CommandAnswer`, which names each tool's own commands), so Claude Code and Codex say the same thing. Claude Code's `/readback:read` sends the reply's text along, for when Readback wasn't running when the reply finished. The app still answers 0.4's `POST /replay {"session"}` with `{"played"}`, for a 0.4 helper running against a newer app. The other way round, a helper that gets 404 from `/command` is talking to an older app and tells the person to reopen Readback (`CommandAnswer.appIsOlder`).

### Codex

Codex gets a plugin, not entries in its `hooks.json`. Connect writes a small marketplace to `~/Library/Application Support/Readback/CodexPlugin` (the two hooks with this app's CLI path, plus `speak` and `read` skills that exist only so the commands show in Codex's slash menu) and runs `codex plugin marketplace add` and `codex plugin add readback@readback`. It uses the `codex` inside ChatGPT.app when there is one, so Codex app users don't need the terminal version; otherwise the usual install places (Homebrew, npm under nvm, `~/.local/bin`, bun, volta), and as a last resort the folders in the login shell's PATH (`$SHELL -l -i`, since nvm and the like are often set up in .zshrc). It needs Codex 0.131.0 or newer (`codex plugin marketplace` and plugin hooks, #21396 and #22549) and checks `codex --version` first. Finding codex happens only on Connect, never on the Connections page's regular refresh. Connect also removes the hooks.json entries older Readback versions wrote.

Codex runs a plugin's hooks only after a person approves them (`/hooks`, or Settings → Hooks in the Codex app). Readback never writes that approval; it reads `[hooks.state."readback@readback:hooks/hooks.json:…"]` in `config.toml` to tell the person what's left. The plugin's files only change when the CLI path does, so a Readback update doesn't ask for approval again.

- The Codex app runs hooks for its own background jobs (task suggestions, replies like `{"suggestions":[]}`). Those threads aren't saved, so `readback hook codex` skips any reply whose `transcript_path` is empty or names no file.
- Orca runs Codex with its own `CODEX_HOME` (`~/Library/Application Support/orca/codex-runtime-home/home`), so it gets its own row and approval. Its `plugins` folder is a link to `~/.codex/plugins`: both homes run one installed copy, and disconnecting one reinstalls it for the other.
- The app's Codex row always means `~/.codex`, whatever `CODEX_HOME` the app was started with. `CODEX_HOME=<dir> readback connect codex` reaches another home.

The on-device engine lives in `~/Library/Application Support/Readback/runtime`: a Python 3.12 and `mlx-audio[tts,server]==0.6.7`, installed by the bundled `uv`, run as a server on 127.0.0.1:8909 that the app starts and stops.

## Build and test

```
swift test                                   # core logic
claude plugin test integrations/claude-code/readback
./scripts/build-app.sh                       # needs uv on PATH (it's copied into the app)
```

The JSON editor keeps every key, its order, numbers and escapes as they were, and writes the 2-space layout Claude Code and Codex use. A file Readback has nothing to change in is never rewritten. A file in another layout (compact, tabs) is rewritten in that 2-space layout the first time Readback edits it. `READBACK_ROUNDTRIP_FILES="a.json:b.json" swift test --filter RoundTrip` checks, read-only, that real config files in that layout come back byte for byte.

## Signing

The build is ad-hoc signed. Without a Developer ID certificate it can't be notarized, so a downloaded copy needs System Settings → Privacy & Security → Open Anyway once. On first launch the app clears the download flag from its own bundle so the hooks can run its CLI.

An ad-hoc signature changes with every build, and macOS ties the audio-capture permission ("lower other sounds") to it. After an update the app asks for that permission once more: silently when the grant still holds, with macOS's prompt when it doesn't.

## Releasing

1. Bump `VERSION` in `scripts/build-app.sh` (and the mod's or the Codex plugin's version if their files changed), then run `./scripts/build-app.sh`.
2. Make a GitHub release tagged `v<VERSION>` and upload `build/Readback.zip` as `Readback.zip`. Check for updates relies on exactly that: the tag, the asset name, GitHub's sha256 for it, and `Readback/Readback.app` inside (see AGENTS.md).

To try Check for updates without publishing anything, point a test copy at a fake release with `READBACK_UPDATES_URL=file:///path/to/latest.json`. The file has GitHub's shape (`tag_name`, `html_url`, and `assets` with `name`, `size`, `digest` and `browser_download_url`), and the URLs can be `file://` too. The relaunch passes every `READBACK_*` variable through, so the test copy comes back as itself.
