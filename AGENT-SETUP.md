# Set up Readback (for a coding agent)

You're an agent setting up Readback on a person's Mac. Readback reads coding agents' replies out loud. Follow these steps in order. Run each command, read its output, and stop at the first step that fails: tell the person what failed and what you saw.

Some steps change the person's files or download a lot. Those say **Ask first**. Ask in one plain question, and wait for a yes.

## 1. Check the Mac

```sh
sw_vers -productVersion
uname -m
```

- Readback needs macOS 15 or newer. On an older macOS, stop and tell the person.
- `arm64` means Apple silicon: the natural voices work. `x86_64` (Intel) means only the macOS voices work. Tell the person, then go on.

## 2. Download and install the app

**Ask first:** "I'll download Readback (about 20 MB) from github.com/iykazrji/readback and put it in your Applications folder. OK?"

```sh
D=$(mktemp -d)
curl -fL -o "$D/Readback.zip" https://github.com/iykazrji/readback/releases/latest/download/Readback.zip
ditto -x -k "$D/Readback.zip" "$D"
ditto "$D/Readback/Readback.app" /Applications/Readback.app
xattr -dr com.apple.quarantine /Applications/Readback.app
rm -rf "$D"
```

- If Readback is already in Applications (an update), first quit it with `osascript -e 'quit app "Readback"'` and remove the old copy with `rm -rf /Applications/Readback.app`, so no old files are left inside the new one.
- If `/Applications` isn't writable, use `~/Applications` instead in these commands and in every later step.
- The `xattr` line is needed because the app isn't notarized by Apple. Without it, macOS refuses to open it and the hooks can't run its command-line tool. Tell the person you did this and why.

From here on, `R` is Readback's command-line tool:

```sh
R=/Applications/Readback.app/Contents/Helpers/readback
```

## 3. Start Readback

```sh
open -a /Applications/Readback.app
"$R" status
```

`status` prints JSON with `"ok" : true` when the app is running. If it says Readback isn't running, wait a few seconds and run it again. The first launch also opens a setup window; tell the person they can close it, because you're doing the same steps.

## 4. Connect the coding tools

See which tools are on this Mac:

```sh
"$R" integrations
```

Each line says `not installed`, `not connected`, `partly connected` or `connected`. Connect the tools that are installed and not `connected` (connecting a `partly connected` one puts back what's missing).

**Ask first:** "I'll connect Readback to <the tools>. That adds Readback's hooks to their settings (it keeps a backup of each file it changes, and Disconnect in Readback undoes it), and a tool that wasn't connected yet will have every reply read out loud, unless you'd switched that off for it before. OK?"

When `connect` switches on reading every reply, it prints a line saying so (`Readback reads every <tool> reply out loud. ...`). It does that only when both hold: the tool wasn't connected before this `connect`, and its "read every reply" switch was never set. Repairing or updating a connection, or a tool the person switched on or off before, leaves the switch as it was and prints nothing about it. If they'd rather not hear every reply, run `"$R" auto <claude|codex|opencode> off` after connecting.

```sh
"$R" connect claude     # Claude Code
"$R" connect codex      # Codex (the app and the terminal)
"$R" connect opencode   # OpenCode
```

- **Claude Code:** the person needs to start a new Claude Code session to get `/readback:speak` and `/readback:read`.
- **Claude Code with a second login** (`CLAUDE_CONFIG_DIR` set, often for work): run `CLAUDE_CONFIG_DIR=<that folder> "$R" connect claude` for it too.
- **Codex:** connecting installs Readback's Codex plugin with the `codex` command. If it says Codex is too old, tell the person to update Codex (`npm install -g @openai/codex@latest` or `brew upgrade codex`), then run the command again.
- **Codex in Orca** (if `~/Library/Application Support/orca/codex-runtime-home/home` exists): run `CODEX_HOME="$HOME/Library/Application Support/orca/codex-runtime-home/home" "$R" connect codex`.
- **OpenCode:** the person needs to restart OpenCode.

## 5. The one step only the person can do: approve the Codex hooks

Skip this if Codex wasn't connected.

Codex won't run a plugin's hooks until a person approves them. **Don't do this for them.** Don't edit `config.toml`, don't write any `trusted_hash`, and don't use `--dangerously-bypass-hook-trust`. Tell the person, in these words or close to them:

> Codex needs your OK once. In the Codex app: quit and reopen it, open Settings → Hooks, and approve both Readback hooks. In Codex in a terminal: type /hooks and approve them there. (In Orca, do the same in an Orca Codex pane.)

Check it afterwards: `"$R" integrations` says `Codex: connected` once both hooks are approved, and `connected, waiting for you to approve its hooks in Codex` until then.

## 6. Get the natural voice (Apple silicon only)

Skip this on an Intel Mac.

**Ask first:** "Readback can download a natural voice, Kokoro: about 1.9 GB, into ~/Library/Application Support/Readback and ~/.cache/huggingface. Until then it uses the macOS voice. Download it now?"

```sh
"$R" engine install
```

Then check every 15 seconds until it's done:

```sh
"$R" engine
```

It prints `installing: <step>` while it works, `installed` when it's done, or `failed: <reason>`. It usually takes one to three minutes. On `failed`, tell the person the reason; they can try again from Readback's Voices page.

## 7. Check it works

```sh
"$R" integrations
"$R" say "Readback is set up."
```

The person should hear that sentence. If they don't, check the Mac's volume, then look at `~/Library/Logs/Readback/readback.log`.

## 8. Tell the person how to use it

- A tool you just connected for the first time reads every reply out loud (one you'd switched off before stays off; `connect` said which). To stop that, switch the tool off in Readback's **Reading** page, or run `"$R" auto <claude|codex|opencode> off`.
- With it off, `/readback:speak on` in a Claude Code session reads that session's replies, `/readback:speak off` stops, and `/readback:read` reads the last reply again. In a Codex chat they're `/speak on`, `/speak off` and `/read`.
- The menu bar icon has **Read last reply**, and opening Readback from Applications shows its window: History, Voices, Reading and Connections.

## Removing it

If the person asks you to remove Readback:

```sh
"$R" disconnect claude; "$R" disconnect codex; "$R" disconnect opencode
"$R" engine remove &&
  osascript -e 'quit app "Readback"' &&
  rm -rf /Applications/Readback.app
```

`engine remove` waits until the engine is gone. If it prints anything other than `not installed` (or `unsupported` on an Intel Mac), it exits with an error and the app stays: stop and tell the person what it printed.

**Ask first** before also deleting its data: `~/Library/Application Support/Readback` (reply history and settings files), `~/Library/Logs/Readback`, and its preferences (`defaults delete local.readback`).
