# Readback

Readback reads your coding agent's replies out loud. When Claude Code, Codex or OpenCode finishes a reply, a small player pops up at the bottom of your screen and reads it to you. You can pause it, skip back or forward a sentence, drag along the line to jump anywhere, and speed it up. Everything runs on your Mac. There's no account and nothing is sent anywhere.

It needs macOS 15 or newer. The natural-sounding voices need a Mac with Apple silicon (M1 or later).

## Install

1. Unzip `Readback.zip` and drag **Readback** into your Applications folder.
2. Open it. macOS shows **"Readback.app" Not Opened** ("Apple could not verify…"), because the app isn't notarized by Apple. Click **Done** (not Move to Trash), then open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Readback. You only do this once.
3. Readback opens its window and adds a waveform icon to your menu bar. If you can't see the icon (a MacBook notch or a full-screen app can hide it), open Readback from Applications again and the window comes back.
4. The first time, Readback lists the coding tools it found on your Mac. Leave them ticked and click **Connect**. If you use Codex, there's one more step it walks you through: approving its hooks in Codex (see Connections below).

If macOS still refuses to open it, run this once in Terminal and try again:

```
xattr -dr com.apple.quarantine /Applications/Readback.app
```

## Set it up

**Voice.** Readback starts with the macOS voice so it works straight away. For a voice that sounds like a person, open **Voices** and click **Get it** next to "Want a more natural voice?". That downloads a private copy of Python and the voice engine (about 1.4 GB, into `~/Library/Application Support/Readback`) and the Kokoro voice (about 355 MB, into `~/.cache/huggingface`). It takes a minute or two. Then pick a voice and click **Play a sample**.

The voice engines:

- **macOS voice**: built in, no download. Add Premium voices in System Settings → Accessibility → Spoken Content and they show up here.
- **Kokoro**: natural and almost instant. 41 voices in English (US and UK), Spanish, French, Hindi, Italian and Portuguese.
- **MeloTTS**: the steadiest: every sentence comes out at the same pace and level. One voice in five English accents (American, British, Australian, Indian, neutral). About 650 MB to download.
- **Soprano**: steady and quick, one English voice. It reads a little fast, so you may like a slower speed in Reading. About 285 MB to download.
- **Qwen3-TTS**: more expressive, a second or two slower to start, about 3.1 GB more to download. Pick it in **Voices** and click **Download now** so your first reply doesn't wait for it; the player shows how far a download has got. Its **Delivery** setting picks how it reads: **Calm** (the default) keeps every sentence steady, **Natural** is Qwen3 as it comes, **Lively** has more energy.
- **Custom model**: any model the mlx-audio engine supports, by its Hugging Face id.

**Connections.** The first-run screen connects everything at once. To change it later, open **Connections** and click **Connect** or **Disconnect** next to a tool:

- **Claude Code**: adds two hooks to `~/.claude/settings.json` and the `/speak` and `/read` commands. Start a new Claude Code session afterwards. If you run a second Claude Code login with its own folder (`CLAUDE_CONFIG_DIR`, say for work), connect that one from Terminal: `CLAUDE_CONFIG_DIR=~/.claude-work /Applications/Readback.app/Contents/Helpers/readback connect claude`. Swap `connect` for `disconnect` to undo it.
- **Codex**: installs Readback's Codex plugin, which adds `/speak` and `/read` and two hooks. Codex won't run a plugin's hooks until you approve them, and only you can do that. In the Codex app: quit and reopen it, then open **Settings → Hooks** and approve both Readback hooks. In Codex in a terminal: type `/hooks` and approve them there. The Connections row says "One step left" until you've done it, then turns blue. It works the same in the Codex app and in the terminal, since both use `~/.codex`. If you only use Codex in a terminal, that's fine: Readback finds the `codex` command itself. It needs Codex 0.131.0 or newer (May 2026); Connect tells you if yours is older.
- **Codex in Orca**: shows up only if you use Orca, which keeps its own Codex settings. Connect it, then type `/hooks` in an Orca Codex pane and approve both Readback hooks.
- **OpenCode**: adds `~/.config/opencode/plugins/readback.js`. Restart OpenCode.

Before Readback changes one of those files it keeps the old version beside it, named `….before-readback`. **Disconnect** removes only what Readback added.

## Use it

Nothing is read out loud until you ask. Three ways to turn it on:

- In a Claude Code session or a Codex chat, type `/speak on`. Only that session is read. `/speak off` stops it, and `/read` reads the last reply right away. In Codex, Readback answers these itself, so they never cost you a model reply.
- In **Reading**, switch on "Read every reply out loud" for a tool.
- From the menu bar icon, **Read last reply** reads the most recent reply from any connected tool.

The player: **Close** or **Esc** stops it. Sending a new message in the same session stops it too. Drag the player anywhere; it remembers where you put it. A reply that starts reading by itself plays a short **Pop** first and the voice follows a second later, so it doesn't catch you off guard; pick another sound, or none, in Reading → "Sound before reading".

When several agents finish at once, the replies queue up instead of talking over each other: the player shows **+2** for two waiting, and the next one starts when the current one ends. Click the title in the player to see the list and jump to any of them. (Prefer being interrupted? Reading → "Switch to it".)

Open Readback from Applications to get its window: **Home** shows your recent replies and a few numbers, **History** keeps the last 50 replies (search them, filter by tool, click to hear one again, right-click to copy or remove), and **Voices**, **Reading** and **Connections** hold the settings.

There's also a command-line tool at `/Applications/Readback.app/Contents/Helpers/readback`. Run it with no arguments to see what it does, for example `readback voice kokoro bm_george` to switch voices, `readback engine install` to install the natural voice from the terminal, or `readback say "hello"`.

## Uninstall

1. In **Connections**, click **Disconnect** for each tool.
2. In **Voices**, click **Remove…** next to the on-device engine.
3. In **Reading**, switch off "Open Readback when you log in" if you turned it on.
4. Quit Readback from the menu bar and drag it to the Bin.
5. For a clean slate, also delete `~/Library/Application Support/Readback` (history, the Claude Code commands and the Codex plugin's source), `~/Library/Logs/Readback`, and its settings with `defaults delete local.readback`.

Downloaded voices stay in `~/.cache/huggingface` in case another app uses them; delete that folder's `models--mlx-community--…` entries if you want the space back.

## If something goes wrong

Readback keeps logs in `~/Library/Logs/Readback`. **About → Logs** opens the folder.

**Codex replies aren't read, or `/speak` goes to the model instead.** Codex is skipping Readback's hooks. Check that both are approved: **Settings → Hooks** in the Codex app, or `/hooks` in a terminal. Codex asks again whenever a hook changes, for example after you move Readback.app and click **Reconnect**.
