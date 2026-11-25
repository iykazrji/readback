# Readback: what it is and where it's going

Use this to weigh a product choice: a feature, a setting, a default, some copy, a new tool to support. Check the hard lines first, then the principles, then the direction. When the owner decides something that changes any of this, update this file in the same change.

## The problem

Coding agents now work for minutes at a time, and people run several at once. While an agent works, the person does something else: reviews another branch, makes coffee, stands up. The agent's reply lands as text on a screen they aren't looking at. Either they keep glancing back, or the reply waits unread while the agent sits idle.

Readback reads the reply out loud when the agent finishes, so the person keeps up without being at the screen. When several agents finish at once, their replies queue instead of talking over each other.

## Who it's for

Anyone who runs a coding agent on a Mac. Today that means Claude Code, Codex and OpenCode, on macOS 15 or newer, with the natural voices on Apple silicon.

It's public and open source. So the person installing it is a stranger, often with no one to ask. Setup has to work on its own: first-run setup connects whatever it finds, and AGENT-SETUP.md lets the person's own agent do the install. Docs have to be honest about the rough edges. Right now the biggest one is that the app isn't notarized, so first launch needs System Settings → Privacy & Security → Open Anyway.

## Hard lines

No feature crosses these, however good it looks.

**On-device only.** Reply text and audio never leave the person's Mac. Voices run locally: the macOS voices, or Kokoro, MeloTTS, Soprano and Qwen3-TTS through mlx-audio. There are no cloud voices, no telemetry and no crash reporting to a server. The only network traffic is downloads the person asked for, meaning the voice engine and its models.

**No account.** No sign-in, ever, and no server of ours that Readback depends on.

**Safe, secure and resource-efficient.**

- *Safe* means Readback never surprises the person with changes to their tools. Before it edits a tool's config it says what it will do and keeps a backup beside the file (`<name>.before-readback`). Disconnect removes only what Readback added. It asks before any big download. And it never takes a step that belongs to the person: approving hooks in Codex is theirs, and Readback only tells them it's left.
- *Secure* means Readback doesn't widen what can reach the person's Mac or their agents. The control server listens on 127.0.0.1 only. Readback never weakens a tool's own trust checks.
- *Resource-efficient* means Readback is close to free while nothing is being read. A loaded voice engine takes 850 MB to 3.5 GB, depending on the model, so it stops after an hour with nothing read (chosen 2026-11-23). Anything that polls or stays loaded has to justify its cost while the app sits idle.

## Principles

These are today's defaults. A better experience can change them, but whoever changes one says why.

- **Quiet unless asked.** Nothing is read until the person switches it on: for one session (`/readback:speak on`), for a tool ("Read every reply"), or for one reply (`/readback:read`, Read last reply). The owner chose this as a default, not a hard line. Reading out loud uninvited is still the quickest way to annoy someone, so changing it needs a strong reason.
- **Respect the person's attention.** Replies wait their turn by default (Reading → "Switch to it" lets new ones cut in). A reply that starts on its own plays a short cue a second before the voice. A new message in a session stops that session's reading. Close or Esc means quiet: whatever was waiting stays in History, unplayed.
- **Ask before reaching further into the Mac.** "Lower other sounds while reading" is off by default because it needs macOS's System Audio Recording permission: a Core Audio tap of every other app, played back quieter. The sound never leaves the Mac and nothing is kept, which keeps it inside on-device only, but a recording prompt is still a surprise unless the person asked for it. So the switch explains the prompt, and macOS asks when it's switched on, not mid-reply. The owner chose this on 2026-11-25, with one known cost: macOS cuts the other apps' output the instant a tap takes over, which can tick; it's timed under the cue sound and happens once per run of replies.
- **Works the moment it's installed.** The macOS voice reads straight away. The natural voice is an offer, not a gate.
- **Feels native in each tool.** Each tool gets a speak and a read command the way that tool does commands: `/readback:speak` and `/readback:read` in Claude Code (the owner dropped the bare names on 2026-11-25), `/speak` and `/read` in Codex. Readback answers them itself, so they never cost a model reply.
- **Mac-native today.** It's a macOS menu bar app with a floating player. That's where it lives now, not a rule. "Away from the Mac" below may need more than one device.

## Where it's going

Four directions are live. Each one pushes on a hard line somewhere, and that's what to settle before building.

**More agent tools.** Cursor, Gemini CLI, Aider and whatever comes next. Every tool should come with the same things: connect, disconnect, a status that tells the truth (including "waiting for you"), a speak and a read command where the tool allows it, and edits it can undo. Adding a tool should mean writing one new integration, not touching every screen.

**Smarter listening.** Long replies are mostly diffs, logs and tables nobody wants read aloud. Readback already turns code blocks and tables into a short spoken note, and reads the rest for the ear: a path as its file name ("main dot py"), no commit hashes, `#478` as "number 478", symbols as words (rules only, chosen 2026-11-25). Next: say what matters first, offer a spoken summary of a long reply, and say clearly when the agent needs the person (a question, a failure, an approval). This pushes on on-device only. A summary needs a model. Either a local one does it, or the agent writes the spoken version itself, inside its own session. Sending reply text to an outside service is out.

**Away from the Mac.** The "away from the screen" case taken further: hearing replies on a phone or AirPods after walking away from the desk. This pushes on on-device only and no account at once. Whatever carries the audio has to go directly between devices the person owns, with no relay server of ours in between.

**Talk back.** Answer a question, say "go on", or stop an agent by voice, not just listen. Speech recognition has to run on the device. This also pushes on safe: a misheard word must never approve something destructive. The person's agents and their trust prompts stay in charge, and voice can't route around them.

## Open questions

These are for the owner to settle, and this file should record the answers:

- Notarization, so a stranger's first launch doesn't need Open Anyway.
- How smarter listening gets its summaries without breaking on-device only: a local model, or the agent's own words.
- How audio reaches the phone in "away from the Mac" with no account and no server.
- Any local process can call the control server today, because it has no token. Is that acceptable as long as it stays bound to 127.0.0.1, or does talk back change the answer once the server can do more than read and stop?
