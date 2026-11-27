<p align="center"><img src="design/icon/readme-icon.png" width="128" alt=""></p>

# Readback

Readback reads your coding agent's replies out loud. When Claude Code, Codex or OpenCode finishes a reply, a small player pops up at the bottom of your screen and reads it to you. Pause it, skip a sentence back or forward, drag to any point, speed it up. The voices run on your Mac: no account, and nothing is sent anywhere.

It's for keeping up with long agent runs while you're away from the screen.

It needs macOS 15 or newer. The natural-sounding voices need Apple silicon (M1 or later); on an Intel Mac it uses the macOS voices.

## Get it

**Have your coding agent do it.** Paste this into Claude Code, Codex or another agent:

> Set up Readback for me by following https://github.com/iykazrji/readback/blob/main/AGENT-SETUP.md

It downloads the app, connects the tools it finds, and tells you the one step only you can do (approving Readback's hooks in Codex).

**Or do it yourself.** Download `Readback.zip` from the [latest release](https://github.com/iykazrji/readback/releases/latest), drag Readback into Applications and open it. The first time, it lists the coding tools it found; click **Set up**. The [full guide](docs/README-for-friends.md) covers macOS's "Open Anyway" step (the app isn't notarized), the voices, and uninstalling.

## Use it

- Connecting a tool switches on reading every reply from it out loud. Switch that off for a tool in Readback's **Reading** page.
- To quiet one noisy session, mute it: the speaker button in the player while it reads, the one on its row on Home, or `/readback:speak off` in a Claude Code session (`/speak off` in a Codex chat; OpenCode has no command, so use the buttons). `/readback:speak on` brings it back, and `/readback:read` reads the last reply again.
- To quiet everything, use **Turn reading off** at the bottom of the sidebar or in the menu bar icon's menu: for an hour, until 8 AM, or until you turn it back on. The icon shows a slash while it's off, and the sidebar says it's off, and until when if you picked a time.
- The menu bar icon's **Read last reply** works from anywhere, even with reading off.

## Building it

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): the layout, how a reply gets from a tool to the speaker, and how to build and test.
