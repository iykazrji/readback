# Readback: notes for agents

Readback reads coding agents' replies out loud on a Mac. Read [PRODUCT.md](PRODUCT.md) before any change a person will see or feel: it has the hard lines and the direction. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the layout, how a reply gets from a tool to the speaker, and the build commands.

## Where code goes

Only `ReadbackCore` has tests (`Tests/ReadbackCoreTests`). The app (`Sources/Readback`) and the CLI (`Sources/readback-cli`) have none, so logic that lives there is checked by hand or not at all. Put new behaviour in ReadbackCore behind a small interface, and keep the app and CLI as thin adapters: sockets, AppKit, SwiftUI, process launching. The pattern to copy is `ReplyQueue`: the app tells it what happened and carries out the `Step` it returns.

A tool's config folder is a `ToolHome` (`.claude`, `.codex`, `.opencode`, `.orcaCodex`). `IntegrationFiles` connects, disconnects and reports status per home, and "waiting for the person's approval" is a status, not a separate flag. A new tool, or a second home for one, is a new case there.

## Contracts that cross process lines

These pieces run in different processes, and some in other people's tools. Nothing at compile time links them, so a change to one side means finding and changing every other side in the same pass.

- **The control server on 127.0.0.1:8908** (`READBACK_PORT` moves the app and the CLI, not the mod). The routes and bodies live in `ReadbackCore/ControlProtocol.swift`, which the app and the CLI both import. The app's `ControlServer.swift` only does sockets. Two clients can't import it: the Claude Code mod (`integrations/claude-code/readback/hooks/register.tsx`, which calls HTTP directly) and the OpenCode plugin (JavaScript generated in `Integrations.swift`, which runs the CLI). When you change a route or a body, update those two by hand and run `claude plugin test integrations/claude-code/readback`.
- **Settings the CLI reads directly.** The CLI reads the read-aloud switches from the app's UserDefaults through `ReadingSwitches`, so a hook never has to start the app just to ask. Keep those keys inside `ReadingSwitches`.
- **CLI output that other agents parse.** `AGENT-SETUP.md` lives at a public URL, and strangers' agents follow it. They match on the CLI's words: `connected`, `not installed`, `waiting for you to approve its hooks`, `installing: <step>`, `installed`, `failed: <reason>`, and `"ok" : true` from `status`. If you change that output, change AGENT-SETUP.md in the same change.
- **The bundle layout.** `scripts/build-app.sh` builds it, and `ReadbackCore/AppBundle.swift` is how the code finds things in it: `Contents/Helpers/readback`, `Contents/Helpers/uv`, `Resources/ClaudeCodePlugin`, `Resources/CodexPluginAssets`. Change both together.
- **The Codex plugin.** Bump `CodexPlugin.version` whenever a file in `CodexPlugin.files` changes, because Codex caches one copy per version. Any change to the hooks makes every user approve them again in Codex. So the plugin's files depend on the CLI path and nothing else. Keep them that way.
- **The Claude Code mod.** It's copied to Application Support only when its bytes differ, because every open Claude Code session reloads the mod, and says so, whenever its files change.
- **Three version numbers, each bumped on its own:** the app (`VERSION` in `build-app.sh`), the Claude Code mod (`.claude-plugin/plugin.json`) and the Codex plugin (`CodexPlugin.version`).

## Safety rules

These are the code side of PRODUCT.md's hard lines.

- Readback edits a tool's config the same way every time. It keeps the old file beside it as `<name>.before-readback`, recognises its own entries by the CLI path they run, and Disconnect removes only those entries.
- Approving hooks in Codex belongs to the person. Readback reads the approval from `config.toml` and never writes it: no `trusted_hash`, no `--dangerously-bypass-hook-trust`.
- The control server binds to 127.0.0.1 only. The only network traffic is downloads the person asked for (the voice engine and its models).
- Tests run against a temp home: `ReadbackPaths(home:)`, or `READBACK_HOME`. A passed-in home ignores `CODEX_HOME` and `CLAUDE_CONFIG_DIR` on purpose, so a test can never touch real `~/.claude` or `~/.codex` files.

## Checking a change

- `swift test` covers Core. `READBACK_ROUNDTRIP_FILES="a.json:b.json" swift test --filter RoundTrip` is opt-in and checks real config files read-only. It shows as skipped otherwise.
- The CLI only works from inside a `.app`: `connect`, `integrations` and starting the app all find things through the bundle path. To try hooks end to end, run `./scripts/build-app.sh` (it needs `uv` on PATH) and use `build/Readback.app`.
- Connecting from a dev build rewrites your real Claude Code, Codex and OpenCode config to point at `build/Readback.app`, and the installed copy then shows as "connected to another copy". Reconnect from the copy you actually use when you're done.

## Repo

- The `.backup-*`, `.migration-backup-*` and `.verify-*` folders at the root are old local snapshots and gitignored. Leave them out of searches and edits.
- When you settle a product or tuning choice, record it in a comment where it lives, with who chose it and when. There's an example on `AppDelegate.idleStopAfter`: "Chosen by the owner on 2026-11-23: an hour keeps it warm…".

## Words

The docs, the UI copy and the code share these names. A **reply** is one finished agent message. A **session** is one Claude Code session or Codex chat. A **tool** is Claude Code, Codex or OpenCode. A **reading** is one reply being voiced. A reply in the history is **waiting** (queued to play), **played**, or **kept** (stored, nobody asked to read it). **Session on** is `/speak on`. **Read every reply** (`autoRead`) is a tool's always-on switch. The **engine** is the on-device mlx-audio server on 127.0.0.1:8909. A **voice** is a speaker within an engine.

## Docs and who reads them

If behaviour changes, update the doc whose reader would notice:

- `README.md`: anyone landing on GitHub.
- `docs/README-for-friends.md`: end users. It ships inside the zip as its README.
- `AGENT-SETUP.md`: other people's agents installing Readback.
- `docs/DEVELOPMENT.md`: people building Readback.

UI copy and user docs say "the person", use plain sentences, and name buttons exactly as they appear.
