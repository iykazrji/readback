# Polish, new Home, resume and the Kokoro step: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Readback's window translucent and polished (custom controls, motion, better spacing), replace Home with a now-playing stack, sessions and setup chips, let replies resume where they stopped, and recommend Kokoro in setup.

**Architecture:** Logic that can be tested goes in `ReadbackCore` (menu navigation, session grouping, resume and unheard in `ReplyQueue`/`ReplyHistory`), each behind a small interface the app calls, as `ReplyQueue` does today. The app gets a `Window/Components/` folder for the custom controls and a glass background, and the pages switch to them. Five pieces, each shippable alone, in order.

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftUI inside AppKit (`NSWindow`, `NSVisualEffectView`), Swift Testing for new Core tests, `scripts/build-app.sh`.

**Spec:** `docs/superpowers/specs/2026-11-25-polish-and-dashboard-design.md`

## Global Constraints

- macOS 15 minimum (`Package.swift` `.macOS(.v15)`), `swiftLanguageModes: [.v5]`.
- Branch `fix/steady-download-numbers`; commit after every task (owner allows commits without asking); no push or PR without the owner's yes. No Co-Authored-By or Claude footers.
- No shadows on buttons, the play button included; no coloured glows. Focus rings are fine.
- Every animation has a Reduce Motion version that is a plain short fade (`@Environment(\.accessibilityReduceMotion)`).
- Secondary text keeps at least 4.5:1 contrast against its background, over a white and a black desktop.
- Copy: "the person", plain sentences, buttons named exactly as shown (AGENTS.md). Product choices get a comment with who chose and when.
- Bundle layout changes go in both `scripts/build-app.sh` and `ReadbackCore/AppBundle.swift` (AGENTS.md).
- Every UI task ends with `ui-done-check` on an isolated test copy (memory `readback-ui-check-tooling`; launcher `scratchpad/uitest/launch.sh` from this session, or rebuild it: copy `build/Readback.app`, set `CFBundleIdentifier` to `local.readback.uitest`, re-sign ad hoc, run with `READBACK_PORT=8918 READBACK_HOME=<scratch>`). Never toggle the owner's real settings; the CLI writes `local.readback` directly.
- `swift test` and `swift build` stay green with 0 warnings after every task.

## Review Focus

1. A bright, busy wallpaper behind the translucent window, in light and dark mode: text must stay readable. Pinned by Task 1's contrast check.
2. Keyboard-only and VoiceOver use of every custom dropdown: open, move, type to jump, choose, Esc. Pinned by Task 4's tests and Task 5's manual check.
3. A `history.json` written by the current release (no new fields) must load, with nothing marked unheard or resumable. Pinned by Task 11's test.
4. Switching replies while the current one is still preparing (position 0), or while a voice sample plays (no reply id): nothing bogus goes back on the stack. Pinned by Task 12's tests.
5. Pressing play on a session with unheard replies while another reply is reading: the reading one goes back on the stack with its position, the session's unheard ones play in order. Pinned by Task 12's test.

---

## Piece 1: window and spacing

### Task 1: Glass window

**Files:**
- Create: `Sources/Readback/Window/Components/Glass.swift`
- Modify: `Sources/Readback/Window/MainWindow.swift` (window setup ~line 62–85, `MainView.body`, `Sidebar.body` background)
- Modify: `Sources/Readback/Window/Surfaces.swift` (`WindowColors`, the "opaque window" comment)

**Interfaces:**
- Produces: `struct GlassBackground: NSViewRepresentable` with `init(_ material: NSVisualEffectView.Material, tint: Color)`, drawing an `NSVisualEffectView` (`.behindWindow` blending, `.active` state) under a tint fill. `WindowColors.sidebarTint`, `WindowColors.pageTint` (dynamic light/dark `Color`s with alpha).

- [ ] **Step 1:** Write `GlassBackground`. Window: `isOpaque = false`, `backgroundColor = .clear`; drop `.containerBackground(WindowColors.page, for: .window)`. Sidebar background: `GlassBackground(.sidebar, tint: WindowColors.sidebarTint).ignoresSafeArea()`; detail background: `GlassBackground(.underWindowBackground, tint: WindowColors.pageTint)`. Starting tints from the mockup: dark sidebar `rgb(24,25,29)` at 0.62, dark page `rgb(32,33,38)` at 0.84; light sidebar `#EAEAEC` at 0.62, light page `#F4F4F5` at 0.84. Rewrite the 2026-11-24 "opaque" comments to say the owner chose glass A on 2026-11-25.
- [ ] **Step 2:** Contrast check. A scratch script composites each tint over pure white and pure black and computes the ratio of secondary text (`NSColor.secondaryLabelColor` in that appearance, or the 0.62-white the components use) against the result. Expected: every pair ≥ 4.5:1. Raise the tint alpha until it passes and record the final values in the comment.
- [ ] **Step 3:** `./scripts/build-app.sh`; test copy over a busy wallpaper and a plain one, dark and light; screenshot Home, Voices, History. Expected: desktop blurred through the sidebar, faintly through the page; title bar row and the window drag (macOS 27.2) still work.
- [ ] **Step 4:** Commit `feat: translucent window with a glassy sidebar (owner's pick A)`.

### Task 2: Sidebar gap, title spacing, one spacing scale

**Files:**
- Modify: `Sources/Readback/Window/Surfaces.swift` (add `Spacing`), `Sources/Readback/Window/MainWindow.swift` (`Sidebar.groups` spacer, `PageMetrics`, `PageTitle`, `PageHeader`), every page file that sets its own paddings: `HistoryPages.swift`, `VoicesPage.swift`, `ReadingSettings.swift`, `ConnectionSettings.swift`, `AboutSettings.swift`, `SetupSheet.swift`, `Surfaces.swift` (`CardFormStyle`)

**Interfaces:**
- Produces: `enum Spacing { static let xs: CGFloat = 4; s = 8; m = 12; l = 16; xl = 24; xxl = 32 }`; `PageMetrics.titleTop: CGFloat` (title's distance from the window top).

- [ ] **Step 1:** Remove the 14 pt group spacer in `Sidebar.body` (the `if index > 0 { Color.clear.frame(height: 14) }`); keep the row spacing.
- [ ] **Step 2:** Lower page titles: `PageTitle` sits `PageMetrics.titleTop` (start at 30) below the window top instead of centred on the 38 pt button row; keep the frosting header working and the title row draggable.
- [ ] **Step 3:** Replace literal paddings in the listed files with `Spacing` values so sections, cards and card padding follow one scale (section gap `xl`, card gap `m`, card padding `l`, inset `PageMetrics.inset` = `xl`).
- [ ] **Step 4:** Build, test copy, `ui-done-check` on every page and the setup sheet at 760 × 500 and a large window. Expected: titles clearly clear of the top, no gap between History and Voices, equal rhythm across pages.
- [ ] **Step 5:** Commit `feat: even spacing, lower page titles, no gap in the sidebar`.

## Piece 2: controls and motion

### Task 3: Buttons and motion helpers

**Files:**
- Create: `Sources/Readback/Window/Components/Buttons.swift`, `Sources/Readback/Window/Components/Motion.swift`
- Modify: every `Button` with a default or bordered style in `Sources/Readback/Window/*.swift` and `Sources/Readback/PlayerView.swift`

**Interfaces:**
- Produces: `struct ReadbackButtonStyle: ButtonStyle` with `enum Kind { case primary, secondary, quiet, destructive }`, used as `.buttonStyle(.readback(.primary))`. `enum Motion { static func spring(_ reduce: Bool) -> Animation? }` (spring ~0.35 s, small overshoot; a 0.15 s ease-out when `reduce`), `static let press: CGFloat = 0.96`.

- [ ] **Step 1:** Write the style: primary accent fill, secondary translucent fill with a 0.5 pt hairline, quiet accent text with a hover fill, destructive red tint; no shadows; press scales to `Motion.press` with `Motion.spring`; hover brightens; disabled at 40% opacity; keyboard focus ring kept.
- [ ] **Step 2:** Apply it everywhere a stock button shows (Download, Retry, Install, Remove…, Play a sample, Open Connections, Connect/Disconnect/Reconnect, Set up/Not now, Clear, Undo, See all, Move back to the bottom, the player's text buttons). Default action keeps `.keyboardShortcut(.defaultAction)`.
- [ ] **Step 3:** Build, `ui-done-check` (every page, setup sheet, player, Reduce Motion on and off). Commit `feat: Readback's own buttons, with press motion`.

### Task 4: Menu navigation model (Core)

**Files:**
- Create: `Sources/ReadbackCore/MenuNavigation.swift`, `Tests/ReadbackCoreTests/MenuNavigationTests.swift`

**Interfaces:**
- Produces: `public struct MenuNavigation: Equatable { public init(titles: [String], selected: Int?); public private(set) var highlighted: Int?; public mutating func moveDown(); public mutating func moveUp(); public mutating func type(_ character: Character, at time: TimeInterval); public mutating func highlightFirst() }`. Typed letters within 1 s build a prefix; a lone repeated letter cycles through items starting with it.

- [ ] **Step 1:** Tests: `opensOnTheSelectedItem` (init with selected 2 → highlighted 2); `downStopsAtTheLastItem` and `upStopsAtTheFirst` (no wrap, like macOS menus); `typingJumpsToTheFirstMatch` (["All tools","Claude Code","Codex","OpenCode"], type "c" → 1); `typingMoreNarrows` ("c","o" within 1 s → 2); `aPauseStartsANewSearch` ("c" at 0, "o" at 1.5 → 3, "OpenCode"); `repeatingOneLetterCycles` ("c","c" → 1 then 2); `matchingIgnoresCase`; `noMatchKeepsTheHighlight`.
- [ ] **Step 2:** Run `swift test --filter MenuNavigation`; expected FAIL (type missing).
- [ ] **Step 3:** Implement. **Step 4:** Tests pass. **Step 5:** Commit `feat: keyboard navigation for Readback's menus (Core)`.

### Task 5: Custom dropdown everywhere

**Files:**
- Create: `Sources/Readback/Window/Components/Dropdown.swift`
- Modify: every `Picker` in `HistoryPages.swift` (tool filter), `ReadingSettings.swift` (Sound before reading, When another reply arrives mid-reading, Speed, When a reply ends), `VoicesPage.swift` (voice and delivery pickers, any others), `SetupSheet.swift` and `PlayerView.swift` if they have pickers

**Interfaces:**
- Consumes: `MenuNavigation` (Task 4), `ReadbackButtonStyle.secondary` look, `Motion`.
- Produces: `struct Dropdown<Value: Hashable>: View { init(_ label: String, selection: Binding<Value>, options: [(title: String, value: Value)]) }`.

- [ ] **Step 1:** Build it as a secondary-style button with a chevron that rotates open, showing a menu panel (a borderless child `NSPanel`, or a SwiftUI overlay that isn't clipped by the form; builder's choice) that springs from the button's corner (scale 0.94 → 1, fade; Reduce Motion: fade only), stays on screen near window edges, shows a check on the selected item and closes on choose, Esc or outside click. Keys: Up/Down/Return/Space via `MenuNavigation`, typed letters to jump. VoiceOver: the button reads as a pop-up button with its label and current value; the open menu as a menu of items.
- [ ] **Step 2:** Replace each listed `Picker`, keeping its accessibility label and selection binding.
- [ ] **Step 3:** Build; `ui-done-check` with mouse, keyboard only, and VoiceOver (Cmd-F5) on History's filter and Reading's Speed; near the window's right edge; Reduce Motion on. Commit `feat: Readback's own dropdowns`.

### Task 6: Search field and switch

**Files:**
- Create: `Sources/Readback/Window/Components/SearchField.swift` (replaces the `NSSearchField` wrapper in `HistoryPages.swift`)
- Modify: `Sources/Readback/Window/Surfaces.swift` (`SpreadSwitchStyle`)

**Interfaces:**
- Produces: `struct SearchField: View { init(_ prompt: String, text: Binding<String>) }`; `SpreadSwitchStyle` keeps its name.

- [ ] **Step 1:** Search: magnifier, placeholder, clear button that springs in with text, Esc empties, accent focus ring, grows ~40 pt while focused (Reduce Motion: no grow). Switch: accent track, thumb stretches while pressed and springs across.
- [ ] **Step 2:** Build; `ui-done-check` on History (type, clear, Esc, Tab focus) and Reading's switches. Commit `feat: Readback's own search field and switch`.

### Task 7: Motion pass

**Files:** Modify `MainWindow.swift` (page changes), `HistoryPages.swift` (`ReplyCard` insert/remove, playing state), `VoicesPage.swift` (download control state changes), `ConnectionSettings.swift` (row state changes)

- [ ] **Step 1:** Animate with `Motion.spring`: switching pages (content cross-fades and settles 6 pt), cards appearing and leaving (scale 0.97 + fade), a card becoming the playing one, a Voices row moving Download → meter → Downloaded, a Connections row changing state. All guarded by Reduce Motion.
- [ ] **Step 2:** Build; `ui-done-check` with Reduce Motion on and off. Commit `feat: motion across the window`.

## Piece 3: the new Home

### Task 8: Sessions summary (Core)

**Files:**
- Create: `Sources/ReadbackCore/SessionSummary.swift`, `Tests/ReadbackCoreTests/SessionSummaryTests.swift`

**Interfaces:**
- Produces: `public struct SessionSummary: Identifiable, Equatable { public let id: String; public let tool: Tool?; public let project: String; public let count: Int; public let newest: Reply; public let unheard: [Reply] /* oldest first */ }` and `public static func sessions(from replies: [Reply], limit: Int = 8) -> [SessionSummary]`, newest session first. `id` is the reply's `session`, or `"cwd:<cwd>|<source>"` when it has none. `project` is the last path component of `cwd`, or the tool name. `unheard` is empty until Task 11 adds the flag; Task 11 fills it.

- [ ] **Step 1:** Tests: `groupsBySession`, `newestSessionFirst`, `repliesWithoutASessionGroupByFolderAndTool`, `projectIsTheFolderName` ("/Users/x/code/enterprise-dashboard" → "enterprise-dashboard"), `limitCaps`, `newestIsTheSessionsLatestReply`.
- [ ] **Step 2:** FAIL, then implement, then PASS. **Step 3:** Commit `feat: group replies by session (Core)`.

### Task 9: Home's Now card and the stack that unfolds

**Files:**
- Create: `Sources/Readback/Window/Home/NowCard.swift`, `Sources/Readback/Window/Home/UpNextStack.swift`
- Modify: `Sources/Readback/Window/HistoryPages.swift` (`HomePage`: remove `stats` and the `Stat` view; add the Now card at the top)

**Interfaces:**
- Consumes: `Reader` (phase, title, progress, replyID, togglePlay, restart, seek(to:)), `Replies.queue.history` waiting replies (oldest first), `AppDelegate.play(_:)`.
- Produces: `NowCard(app:reader:replies:)`; hidden entirely unless `reader.isSpeaking`.

- [ ] **Step 1:** Now card: flat play/pause (no shadow), project and tool, first line, a draggable progress bar (`reader.seek(to:)`), Start over (`reader.restart`), a small level animation while playing (static under Reduce Motion).
- [ ] **Step 2:** Stack: at rest, up to 3 cards peek under the Now card with "N waiting"; hover or click unfolds them into rows (tool mark, project, tool name); clicking a row calls `app.play(reply)`. Follow `upnext-live.html` option 3 (in `.superpowers/brainstorm/…/content/`). Leave a slot for the resume ring (Task 13).
- [ ] **Step 3:** Build; test copy: send replies to port 8918 with Python `urllib` (`/speak` with `source: "opencode"`, `/auto` on for opencode **on the test copy only**); check 0, 1, 3 and 6 waiting, finish, jump, nothing reading (card gone). `ui-done-check`. Commit `feat: Home shows what's reading and what's next`.

### Task 10: Read every reply row, Sessions, Setup chips

**Files:**
- Create: `Sources/Readback/Window/Home/SessionsList.swift`, `Sources/Readback/Window/Home/SetupChips.swift`, `Sources/Readback/Window/Home/EveryReplyRow.swift`
- Modify: `HistoryPages.swift` (`HomePage` body: Now card, every-reply row, Sessions, Setup; keep the empty state and See all)

**Interfaces:**
- Consumes: `SessionSummary.sessions(from:)`, `Preferences.readsEveryReply/setReadsEveryReply`, `Connections.rows` and the actions `ConnectionSettings` already calls, `Runtime.state`, `Preferences.engine`.
- Produces: `SetupChips(app:connections:runtime:prefs:openConnections:)`.

- [ ] **Step 1:** Every-reply row: a switch per tool, always shown, above Sessions.
- [ ] **Step 2:** Sessions: rows per `SessionSummary` (tool mark, project, tool, count, newest time, first line); play plays `newest`; clicking the row expands its replies in place (`ReplyCard`s). Leave slots for "N unheard" and the ring (Task 13).
- [ ] **Step 3:** Setup chips: the voice in use; "Using the macOS voice · Get Kokoro" on Apple silicon while Kokoro isn't installed (opens Voices; Task 15 points it at the setup step's flow); engine only when something's wrong; each tool's state with a Fix button doing what Connections does for that state.
- [ ] **Step 4:** Build; `ui-done-check` at 760 × 500 and large, with and without replies, with a tool needing approval (test copy's own home). Commit `feat: Home shows sessions, the read-every-reply switches and setup at a glance`.

## Piece 4: resume and unheard

### Task 11: Reply carries a position and an unheard mark (Core)

**Files:**
- Modify: `Sources/ReadbackCore/ReplyHistory.swift` (`Reply`), `Sources/ReadbackCore/SessionSummary.swift` (fill `unheard`)
- Test: `Tests/ReadbackCoreTests/ReplyHistoryTests.swift`, `SessionSummaryTests.swift`

**Interfaces:**
- Produces: on `Reply`: `public var resumeAt: Double?` (0…1 of the reading; nil means from the start) and `public var unheard: Bool` (default false), both decoded with `decodeIfPresent` so old files load.

- [ ] **Step 1:** Tests: `oldHistoryLoadsWithNothingUnheardOrResumable` (JSON without the keys → `unheard == false`, `resumeAt == nil`); `newFieldsRoundTrip`; `sessionSummaryListsUnheardOldestFirst`.
- [ ] **Step 2:** FAIL, implement (custom `init(from:)`), PASS. **Step 3:** Commit `feat: replies remember where they stopped and whether they were heard (Core)`.

### Task 12: The queue resumes, marks unheard and catches up (Core)

**Files:**
- Modify: `Sources/ReadbackCore/ReplyQueue.swift`
- Test: `Tests/ReadbackCoreTests/ControlAndQueueTests.swift` (or a new `ResumeTests.swift`)

**Interfaces:**
- Consumes: `Reply.resumeAt`, `Reply.unheard`.
- Produces (changes to `ReplyQueue`):
  - `public mutating func play(_ id: UUID, leaving reading: Reading?, at position: Double?) -> Step` (the old `play(_:)` becomes this with defaults nil).
  - `received(_:switchedOn:reading:cutIn:at:now:)` gains `at position: Double?` for the cut-in case.
  - `public mutating func stopAll(reading: Reading?, at position: Double?) -> Step`.
  - `public mutating func remember(_ id: UUID, at position: Double?)` (quit, Start over → nil).
  - `public mutating func finished(_ id: UUID)` (clears `resumeAt`).
  - `public mutating func catchUp(session id: String, leaving reading: Reading?, at position: Double?) -> Step`.
  - `history.nextWaiting` prefers a waiting reply with `resumeAt` over older ones.

- [ ] **Step 1:** Tests:
  - `jumpingAwayPutsTheReadingOneBackOnTopWithItsPosition` (play B while A at 0.4 → A `.waiting`, `resumeAt == 0.4`, next `playNext` returns A).
  - `aCutInDoesTheSame` (received with cutIn while A at 0.3).
  - `nothingGoesBackWhenItHadNotStarted` (position nil or 0 → A not requeued).
  - `aSampleIsNeverRequeued` (reading.replyID nil).
  - `stopAllKeepsThePlayingOnesPositionAndMarksTheRestUnheard` (A at 0.5 → A kept `resumeAt 0.5`, not unheard; waiting B, C → kept, unheard).
  - `quittingMarksWaitingRepliesUnheard` (`init(restoring:)` with waiting, never-started → kept + unheard; waiting with resumeAt → kept, not unheard).
  - `startingAReplyClearsUnheard` and `theStepCarriesTheResumePosition` (`.play(reply)` has `resumeAt`).
  - `finishingOrStartingOverClearsThePosition`.
  - `catchUpPlaysTheOldestUnheardAndQueuesTheRestInOrder`, `catchUpWhileReadingPutsTheReadingOneBackFirst` (Review Focus 5).
- [ ] **Step 2:** FAIL, implement, PASS; run the full `swift test`. **Step 3:** Commit `feat: the queue resumes replies, marks unheard ones and catches up a session (Core)`.

### Task 13: Wire resume into the app

**Files:**
- Modify: `Sources/Readback/Reader.swift` (`start(_:replyID:cueSound:from:)`), `Sources/Readback/AppDelegate.swift` (`carryOut(_: ReplyQueue.Step)`, `play(_:)`, `stopEverything()`, `readerMoved`, `applicationWillTerminate`, the stats count), `Sources/Readback/PlayerView.swift` ("Picked up at N%"), Home (`NowCard`, `UpNextStack`, `SessionsList`), `HistoryPages.swift` (`ReplyCard` ring)

**Interfaces:**
- Consumes: Task 12's queue API; `Reader.progress` as the position.
- Produces: `Reader.start(_ request: SpeakRequest, replyID: UUID?, cueSound: String?, from fraction: Double? = nil)`.

- [ ] **Step 1:** Reader starts at `fraction` once its chunks are ready (`seek(to:)`); the player shows "Picked up at N%" under the title for ~3 s when `fraction` is set; Start over calls `remember(id, at: nil)`.
- [ ] **Step 2:** AppDelegate passes `reader.progress` as `at:` when playing, cutting in or stopping; `.finished` calls `finished(id)`; quitting calls `remember(id, at: reader.progress)` before saving; a reading that started with `resumeAt` doesn't count again in the stats.
- [ ] **Step 3:** Home: ring on stack rows and session rows for part-heard replies; "N unheard" on sessions; the session's play button calls a new `AppDelegate.catchUp(session:)` when it has unheard replies. History's `ReplyCard` shows the ring.
- [ ] **Step 4:** Build; test copy: jump mid-reply, Esc mid-reply, quit mid-reply, relaunch, play from Home and History, Start over; catch up a session with 3 unheard. `ui-done-check`. Commit `feat: replies pick up where they stopped`.

## Piece 5: Kokoro in setup

### Task 14: A Kokoro sample in the bundle

**Files:**
- Create: `Resources/KokoroSample.m4a` (about 5 s)
- Modify: `scripts/build-app.sh` (copy to `Contents/Resources/`), `Sources/ReadbackCore/AppBundle.swift` (`kokoroSample: URL?`), `Resources/ThirdPartyNotices.txt` if Kokoro's licence needs a line, `Tests/ReadbackCoreTests/` (the existing AppBundle test, if there is one)

- [ ] **Step 1:** Render "Hi. This is Kokoro, the voice Readback recommends. It reads your agents' replies like a person would." with the engine's own Kokoro (default voice), with the installed runtime (`~/Library/Application Support/Readback/runtime/.venv/bin/python`, mlx-audio's generate entry point; check its flags with `--help` first). Convert to AAC m4a with `afconvert`.
- [ ] **Step 2:** Copy it in the build; add `AppBundle.kokoroSample`; a test that the path is `Contents/Resources/KokoroSample.m4a` if `AppBundle` has path tests. Build, check the file is in `build/Readback.app`. Commit `feat: bundle a short Kokoro sample`.

### Task 15: The Kokoro step

**Files:**
- Modify: `Sources/Readback/Window/SetupSheet.swift` (new screen between choices and progress; remove the "Natural voice" checkbox), Home's `SetupChips` ("Get Kokoro" starts the same install), `docs/README-for-friends.md`, `PRODUCT.md`, `docs/DEVELOPMENT.md`

- [ ] **Step 1:** Screen copy: title "Our recommended voice: Kokoro"; line "It sounds like a person reading, starts almost instantly and runs entirely on this Mac. About 1.86 GB to download with the engine."; buttons **Play sample** (plays `AppBundle.kokoroSample`), **Download** (primary), **Use the macOS voice for now** (quiet). Shown on Apple silicon whenever Kokoro isn't installed, including when no tools were found or all are connected. Download continues as the existing "Get the natural voice" progress step with the `DownloadAmount` meter. Skipping leaves `prefs.engine` as `.kokoro` (`start()` must not set `.system`).
- [ ] **Step 2:** Docs: README-for-friends (setup and the new Home), PRODUCT.md (Kokoro recommended in setup, not a gate; the glass reverses the 2026-11-24 opaque choice), DEVELOPMENT.md (the `Components/` folder and the Core models added here).
- [ ] **Step 3:** Build; test copy with an empty `READBACK_HOME` and onboarding reset (`defaults delete local.readback.uitest onboarded`): walk setup with Play sample, Download, and skip; then Home's chip. `ui-done-check`. Commit `feat: setup recommends Kokoro, with a sample`.
