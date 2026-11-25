# Readback polish, new Home, resume and the Kokoro step

Decided with the owner on 2026-11-25. Mockups the owner reacted to are in `.superpowers/brainstorm/37559-1795635937/content/` (gitignored): `window-material.html` (pick A), `home-layout.html` (pick A), `components-v2.html`, `upnext-live.html` (pick: the stack that unfolds).

## Why

The owner finds the window plain and the stock macOS controls ugly. They want Readback to feel like a polished Mac app: a translucent window, its own buttons, dropdowns and search, motion that responds when things change, and a Home page you open to see what's happening rather than a scoreboard. Separately, new people drift onto the macOS voice without ever hearing the recommended one, Kokoro; setup should recommend it properly.

Success is the owner opening the window and it looking and moving like something they're proud of, with nothing a person relies on today (keyboard, VoiceOver, Reduce Motion, readability) getting worse.

## Goals

1. The window: translucent with the desktop blurred behind it, sidebar and page in different tints.
2. Spacing: no gap in the sidebar list, page titles lower, one spacing scale across pages.
3. Controls: custom buttons, dropdowns, search field and switch everywhere in the main window, setup sheet and player, with motion.
4. A new Home: what's reading now as a stack that unfolds, replies grouped by session, setup at a glance.
5. Resume: a reply left mid-reading goes back on the stack and resumes where it stopped.
6. Unheard: replies dropped by Close/Esc/Stop are marked on their session in Home.
7. Setup recommends Kokoro in its own step, with a sample you can hear before downloading.

## Non-goals

- Charts or activity over time on Home (offered, not picked).
- The Home totals (replies read, listening time, words heard). They leave Home; the numbers stay stored.
- Changing how replies get to Readback, the hooks, or anything in the tools' configs.
- Intel Macs getting Kokoro (the engine can't run there).

## Anti-goals (it fails even if it works)

- Text that's hard to read over a busy wallpaper.
- Controls that look custom but lose keyboard use, type-to-select or VoiceOver.
- Motion that's slow, bouncy for the sake of it, or ignores Reduce Motion.
- Shadows on buttons, the play button included, or coloured glows. The owner rejected both.
- Kokoro becoming a gate: Readback must read the moment it's installed (PRODUCT.md, "Works the moment it's installed"; "asks before any big download").

## Constraints

- macOS 15 minimum, Swift 5 language mode, SwiftUI in an AppKit `NSWindow` (`MainWindowController`).
- New behaviour goes in `ReadbackCore` with tests; the app stays a thin adapter (AGENTS.md).
- The main window moves itself on macOS 27.2+ (`SelfDraggingWindow`); any new view in the title bar row must keep that working.
- Existing tokens live in `Sources/Readback/Window/Surfaces.swift` (`WindowColors`, `Radius`, `.surface()`); extend them rather than scatter literals.
- Copy follows AGENTS.md: "the person", plain sentences, buttons named exactly as shown.
- Product choices get a comment where they live, with who chose and when.

## Approaches considered

**The glass.** Three looks were mocked over a colourful desktop: A, a glassy darker sidebar with a mostly solid page; B, both panes clearly see-through; C, just a hint. The owner picked A. Building it needs macOS's behind-window blur (an `NSVisualEffectView` with `.behindWindow` blending, or SwiftUI's window container background material); SwiftUI's in-window materials can't see the desktop.

**Up next.** Three were built as a live prototype: chips by name, a stack, and a stack that unfolds into named rows on hover or click. The owner picked the stack that unfolds.

**Dropdowns.** (A) a custom button that opens the native macOS menu: free keyboard, type-to-select and VoiceOver, but the menu opens the macOS way. (B) a fully custom popover: exactly the mockup's spring, with keyboard, type-to-select, VoiceOver and dismissal rebuilt. (C) a mix: B for History's filter, A for settings. I recommended C; **the owner picked B for every dropdown.**

**Home layout.** One column (now, sessions, setup chips) or two columns (sessions left, switches and setup right). The owner picked one column; two columns is cramped at the window's 760 pt minimum.

## What was decided

### 1. Window and spacing

- Glass A: sidebar the most see-through and a touch darker (mockup: about 62% of `rgb(24,25,29)` over a 30 px blur, saturation up); page mostly solid with a hint of blur (about 80–86% of `rgb(32,33,38)`). Light mode gets the matching light tints. This reverses the 2026-11-24 "opaque window" choice; update the comments in `MainWindow.swift` and `Surfaces.swift` that record it.
- Text must stay readable over any wallpaper: tune the tints until secondary text holds at least 4.5:1 against the tint over a white and a black desktop.
- Sidebar: no gap between the History group and the Voices group (`Sidebar.groups` adds a 14 pt spacer today).
- Page titles sit lower: about 30 pt from the window top to the title in the mockup, still level with the window buttons' row or clearly below it, whichever reads better on screen. `PageMetrics.headerHeight` (38) and `PageTitle` own this.
- One spacing scale for every page (sections, cards, card padding), applied to Home, History, Voices, Reading, Connections, About and the setup sheet.

### 2. Controls and motion

- Buttons, no shadows: primary (accent fill), secondary (light translucent fill and hairline), quiet (accent text, fill on hover), destructive (red tint). Press sinks to about 0.96 and springs back; hover brightens.
- Dropdowns: fully custom popover for every picker (History's tool filter; Reading's speed, cue sound, reply end, several agents; Voices' voice and delivery pickers; any others). Each must: open from its button's corner with a short spring and a fade; close on Esc, outside click, or choosing; take Up/Down/Return/Space; jump by typed letters; show the chosen item with a check; read as a pop-up button with a menu to VoiceOver, announcing the selected value; stay on screen near window edges.
- Search field: magnifier, placeholder, clear button that springs in when there's text, Esc empties it, focus ring in the accent colour, a little wider while focused.
- Switch: track fills with the accent, the thumb stretches while held and springs across.
- Motion everywhere: page changes, cards appearing and leaving, the stack folding and unfolding, playing state changes. Springs that settle fast (the mockups use about 0.35 s with a slight overshoot). With Reduce Motion on, every one of these becomes a plain short fade.
- The player panel gets the same buttons and switch where it has them.

### 3. The new Home

One column, top to bottom:

- **Now** (only while something is reading or paused; nothing at all otherwise, no "Nothing reading" placeholder): a card with the play/pause button (flat, no shadow), the session's project and tool, the reply's first line, a progress bar, and a small level animation while it speaks. Below it, the waiting replies as a stack: at rest they peek out under the card with "N waiting"; hovering or clicking unfolds them into rows (tool mark, project, tool name). Clicking a row plays it now. A resumable reply (below) shows a small ring with how far it got.
- **Sessions**: recent replies grouped by session, newest first. Each row: tool mark, project folder (the last part of `cwd`), tool name, how many replies, the time of the newest, and its first line. A play control plays the session's newest reply; clicking the row opens its replies in place (or in History filtered to it; builder's call). A session with unheard replies shows "N unheard", and playing from it starts with the oldest unheard.
- **Setup**: a row of chips: the voice in use (and "Using the macOS voice · Get Kokoro" until Kokoro is installed, on Apple silicon), the engine if something's wrong with it, and each tool's state from `IntegrationFiles` (connected, needs approval, needs reconnecting), with a Fix button that does the same as the matching action in Connections.
- "See all" goes to History, as now.

### 4. Resume

- When the person jumps to another reply, or a new one cuts in, while a reply is playing or paused, that reply goes back to the front of the waiting stack with where it stopped (chunk and offset, or a fraction), and plays from there when its turn comes. It must not count twice in the played stats.
- Close, Esc and Stop are unchanged: quiet, nothing resumes by itself.
- This belongs in `ReadbackCore` (`ReplyQueue`, `ReplyHistory`) with tests; the reader already starts at an offset (`Reader.play(_:from:)`, `seek(to:)`).

### 5. Unheard

- "Unheard" means a reply that was queued to play and then dropped by Close/Esc/Stop without being heard. It does **not** include replies nobody asked to read (read-aloud off), which are "kept" today. So the history needs to tell those apart (a new state or a flag on the reply); persist it, and migrate existing history as not unheard.
- Playing an unheard reply clears it. Clearing history clears it.

### 6. The Kokoro step in setup

- On Apple silicon, the first-run setup sheet gets its own step after connecting tools: "Our recommended voice: Kokoro", one line on why, a **Play sample** button that plays about 5 s of pre-rendered Kokoro audio shipped in the app (no download needed), and a Download button with the existing meter (now `DownloadAmount`).
- Skipping it is fine: replies read with the macOS voice, and Home's setup chip keeps offering Kokoro until it's installed. No popup later.
- The existing "Natural voice" checkbox among the tools goes away in favour of this step.
- The sample: render once with Kokoro (default voice), commit it under `Resources/`, copy it into the bundle in `scripts/build-app.sh` and find it through `AppBundle`, per AGENTS.md's bundle-layout rule. Kokoro is Apache-2.0; note it in `Resources/ThirdPartyNotices.txt` if needed.

## Order

Each piece ships on its own, in this order: 1 window and spacing, 2 controls and motion, 3 new Home, 4 resume (with 5 unheard), 6 the Kokoro step. Home's stack needs resume for its ring; build the stack first without the ring if 4 isn't in yet.

## Checking it

- `swift test` for every Core change; new tests for resume and unheard.
- `ui-done-check` on each piece, on an isolated test copy (memory: `readback-ui-check-tooling`), in dark and light, over a busy and a plain wallpaper, at the 760 × 500 minimum and a large window, with Reduce Motion on and off, and VoiceOver on the dropdowns.
- The owner tries each piece by hand before the next starts.

## Left to the builder

- Exact tint values, spacing numbers and spring parameters, within the mockups' look.
- Whether a session row opens in place or in History.
- How the custom dropdown is built (SwiftUI popover, an overlay, or a child `NSPanel`), as long as it meets the list in section 2.
- How resume stores its position and how unheard is represented, as long as both persist and are tested.
- Component file layout (a `Components/` folder next to `Surfaces.swift` is fine).
- Docs: README-for-friends (setup, Home), DEVELOPMENT.md (components), PRODUCT.md (Kokoro recommendation and the reversed opaque-window choice).
