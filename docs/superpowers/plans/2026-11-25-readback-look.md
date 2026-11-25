# Readback's own look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild every control in the window, the setup sheet and the player as black-and-white plates with a hairline edge at 34/28 pt, with no accent colour anywhere, plus a moving waveform for "playing".

**Architecture:** All sizes and tints live in `ControlMetrics`; every control reads them. Four new SwiftUI components (segmented control, checkbox, meter, waveform) replace the last stock controls and the SF Symbol playing mark. The only logic (waveform motion, segment stepping) goes in `ReadbackCore` with tests; the views stay thin.

**Tech Stack:** Swift 5 mode, SwiftUI in an AppKit window, macOS 15+, Swift Testing for Core.

**Spec:** `docs/superpowers/specs/2026-11-25-readback-look-design.md` (approved 2026-11-25). Approved mockup: `.superpowers/brainstorm/19958-1795640505/content/look-plates.html`.

## Global Constraints

- No `Color.accentColor` anywhere in `Sources/Readback` when done (`grep -rn accentColor Sources/Readback` returns nothing).
- Colour only in: the sidebar's section tiles (`IconTile`), the setup steps' green done / red failed icons, red error text.
- Regular controls 34 pt tall, small 28 pt; radius 10 / 8; text 13.5 / 12.5 pt; side padding 16 / 12; quiet padding 10 / 8.
- Edge 0.5 pt drawn inside the shape. Dark: fill white 8/12/16%, edge white 13/20%. Light: fill black 4.5/7.5/10%, edge black 11/18%.
- Primary plate: dark #F5F5F7 with #111113 text; light #111113 with #FFFFFF text.
- Flat: no shadow on any button or the play button. Menus keep their window shadow.
- Every motion has a Reduce Motion fallback (a plain fade, or still).
- Product choices get a comment where they live: who chose, and when (e.g. "Chosen by the owner on 2026-11-25: …").
- Sidebar section rows and their coloured tiles don't change.
- Checks: `swift test` passes; `./scripts/build-app.sh` builds with 0 warnings.

## Review Focus

1. Light mode over a white desktop: the hairline edge and the 4.5% fill must still show a control's outline. Checked by screenshot in Task 6.
2. Glyphs on the primary plate: anything white-on-colour today (tool tiles, voice tile, checkbox check) must flip to the contrasting colour, or it vanishes on a white plate in dark mode. Checked by screenshot in Task 6, all tiles connected and not.
3. Keyboard focus: the new segmented control and checkbox must show the neutral focus ring and work from the keyboard (arrows / Space). Checked in Task 6.
4. Idle cost: the waveform must not redraw while paused or when nothing plays. Pinned by Core tests (paused gives a constant frame) in Task 1, and by the view only running its timeline while playing (Task 5).
5. Disabled controls (Downloaded, Set up with nothing picked, the player's buttons while failed) stay readable at 40% and keep their size. Checked in Task 6.

---

### Task 1: Core: waveform motion and segment stepping

**Files:**
- Create: `Sources/ReadbackCore/WaveformMotion.swift`, `Sources/ReadbackCore/SegmentStep.swift`
- Test: `Tests/ReadbackCoreTests/WaveformMotionTests.swift`, `Tests/ReadbackCoreTests/SegmentStepTests.swift`

**Interfaces:**
- Produces:
  - `public enum WaveformMotion { public static let heights: [Double]; public struct Bar: Equatable { public let height: Double; public let scale: Double; public let opacity: Double }; public static func frame(at time: TimeInterval, playing: Bool, reduceMotion: Bool) -> [Bar] }`
  - `public enum SegmentStep { public static func step(from index: Int, by delta: Int, count: Int) -> Int }`

- [ ] **Step 1: Write the failing tests**

`WaveformMotionTests` (Swift Testing):
- `heightsAreTheWaveformShape`: `WaveformMotion.heights == [3, 6, 10, 13, 8, 5, 2.5]` (in 13 pt units; tallest is 13).
- `stillWhenNotPlaying`: for t in [0, 0.4, 3.7], every bar of `frame(at: t, playing: false, reduceMotion: false)` has `scale == 1` and `opacity == 1`, and the frames are equal.
- `barsMoveWhilePlaying`: frames at t = 0.0 and t = 0.3 differ in at least one bar's `scale`; every scale in many samples (t from 0 to 5 in 0.05 steps) is within 0.45...1.15.
- `sweepLightsOneRegionAtATime`: over samples while playing, every opacity is within 0.3...1, and at each sample at least one bar has opacity 1 and at least one has opacity < 0.5.
- `sweepPeriod`: `frame(at: t)` and `frame(at: t + 1.25)` have the same opacities (to 1e-9) for t in [0.1, 0.7].
- `reduceMotionKeepsBarsStill`: while playing with `reduceMotion: true`, every scale is 1, and opacities still vary across samples.

`SegmentStepTests`:
- `rightMovesOne`: `step(from: 0, by: 1, count: 3) == 1`.
- `wrapsAtTheEnd`: `step(from: 2, by: 1, count: 3) == 0`, `step(from: 0, by: -1, count: 3) == 2`.
- `emptyStaysPut`: `step(from: 0, by: 1, count: 0) == 0`.

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "WaveformMotionTests|SegmentStepTests"`
Expected: compile errors, `WaveformMotion` and `SegmentStep` not found.

- [ ] **Step 3: Implement**

`WaveformMotion.frame`: sweep opacity per bar is a function of `(time / 1.25 + Double(i) * 0.14 / 1.25)` mod 1, using the mockup's keyframes: 0.3 at phase 0, rising to 1 by 0.08, held to 0.30, back to 0.3 by 0.42, 0.3 to 1.0 (linear between). Bar `i`'s scale follows its own period `[0.62, 0.9, 0.74, 1.05, 0.68, 0.96, 0.58][i] * 2` (the mockup runs each loop there and back) with offset `-i * 0.37`, through the keyframes 1 → 0.45 at 35% → 1.15 at 70% → 0.7 at 100% and back, eased with smoothstep. Not playing: scale 1, opacity 1. Reduce Motion: scale 1, sweep as normal. `SegmentStep.step`: `count > 0 ? ((index + delta) % count + count) % count : index`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "WaveformMotionTests|SegmentStepTests"`, then `swift test`.
Expected: all pass.

- [ ] **Step 5: Commit**

`git commit -m "feat: waveform motion and segment stepping (Core)"`

### Task 2: Tokens, buttons, search and dropdowns

**Files:**
- Modify: `Sources/Readback/Window/Components/Buttons.swift` (ControlMetrics, ReadbackButtonStyle), `Sources/Readback/Window/Components/SearchField.swift`, `Sources/Readback/Window/Components/Dropdown.swift`

**Interfaces:**
- Produces, on `ControlMetrics` (all `static`): `height = 34`, `smallHeight = 28`, `radius = 10`, `smallRadius = 8`, `fontSize = 13.5`, `smallFontSize = 12.5`, `padding = 16`, `smallPadding = 12`, `quietPadding = 10`, `smallQuietPadding = 8`, `edgeWidth = 0.5`; colour functions taking `ColorScheme`: `fill`, `hoverFill`, `pressFill`, `edge`, `hoverEdge`, `primaryFill`, `primaryText`, `focusRing`, `menuHighlight`. Later tasks use these names only.

- [ ] **Step 1: ControlMetrics**: set the values above and the spec's colour table. Comment the owner's choice (2026-11-25: black-and-white plates, 34 pt, hairline edge).
- [ ] **Step 2: ReadbackButtonStyle**: primary uses `primaryFill`/`primaryText`, semibold, hover opacity 0.9, no edge; secondary fill + `edge` (hover: `hoverFill` + `hoverEdge`; pressed: `pressFill`); quiet uses `.primary` text and `hoverFill` under the pointer; destructive draws like secondary with `.secondary` text that turns `.primary` on hover. Press scale 0.97 (`Motion.press`). Every kind keeps the fixed height. A focus ring for keyboard focus: `focusRing`, 2 pt, 2 pt outside.
- [ ] **Step 3: SearchField**: edge via `edge`/`hoverEdge`, focus ring 2 pt at 2 pt outside using `focusRing`; clear button stays the 20 pt round button (fill `pressFill`, `xmark` 8 pt), not an icon plate.
- [ ] **Step 4: Dropdown**: chevron becomes `chevron.up.chevron.down` at 9 pt semibold, `.secondary`, no rotation. Menu: corner 12, padding 6, rows `ControlMetrics.height - 4` (30) with 7 pt corners, 13.5 pt text, highlight `menuHighlight` with `.primary` text (no white-on-accent), chosen row medium weight with its check. Panel fill: dark #222327 at 97%, light #FCFCFD at 98%; edge white 13% / black 10%. Update `MenuPanel.size(for:)` for the new font, padding and row height.
- [ ] **Step 5: Build and look**: `swift build` with no warnings; `./scripts/build-app.sh`, run the isolated test copy, screenshot History (header: search, dropdown, Clear) and Reading with a menu open, dark and light. Measure the History header controls: all 34 px tall, same top and bottom row.
- [ ] **Step 6: Commit**: `git commit -m "feat: black-and-white plates for buttons, search and dropdowns"`

### Task 3: Switch, rows, and the last of the accent colour

**Files:**
- Modify: `Sources/Readback/Window/Components/Switch.swift`, `Sources/Readback/Window/Surfaces.swift`, `Sources/Readback/Window/VoicesPage.swift:360`, `Sources/Readback/Window/SetupSheet.swift:346-349, 397, 417`, `Sources/Readback/Window/ConnectionSettings.swift:165`, `Sources/Readback/Window/MainWindow.swift` (root view), `Sources/Readback/PlayerPanel.swift` (root view)

**Interfaces:**
- Consumes: `ControlMetrics` (Task 2).
- Produces: `WindowColors.cardActive` as neutral overlay (light black 7%, dark white 12%).

- [ ] **Step 1: ReadbackSwitch**: 35 × 20, thumb 16, inset 2, press stretch 5. Off: track `fill`-like white 12% / black 9% with `edge`; on: track `primaryFill`, thumb #1C1C1F in dark, white in light. Comment: owner, 2026-11-25, "a bit too high" at 24, picked 20.
- [ ] **Step 2: Rows**: `CardFormStyle` rows come to 54 pt with a 34 pt control: keep `minHeight: ControlMetrics.height` and set vertical padding to 10.
- [ ] **Step 3: cardActive** neutral, as above.
- [ ] **Step 4: Accent removals**: chosen voice check `.primary`; "Your turn" badge `.primary` text on `ControlMetrics.fill`; the `.yourTurn` step icon `.primary`; `ToolTile` and `VoiceTile` connected/ready: `primaryFill` background with `primaryText` glyph (not white), otherwise grey 60% with white glyph.
- [ ] **Step 5: Root tint**: `.tint(.primary)` on the main window's root view, the setup sheet's content and the player panel's root, so stock leftovers (Connections' small spinner) draw neutral.
- [ ] **Step 6: Verify**: `grep -rn accentColor Sources/Readback` prints nothing; `swift build` clean; screenshot Reading and Connections, dark and light; settings rows measure 54 px, switches 35 × 20.
- [ ] **Step 7: Commit**: `git commit -m "feat: shorter black-and-white switch, and no accent colour left"`

### Task 4: Segmented control, checkbox, meter, icon plate

**Files:**
- Create: `Sources/Readback/Window/Components/Segmented.swift`, `Checkbox.swift`, `Meter.swift`, `IconPlate.swift`
- Modify: `Sources/Readback/Window/VoicesPage.swift` (Delivery picker at :87-93; meters at :155-157, :230, :465-467; cancel at :483), `Sources/Readback/Window/SetupSheet.swift` (checkboxes at :103, :111; meter at :359)

**Interfaces:**
- Consumes: `ControlMetrics` (Task 2), `SegmentStep.step(from:by:count:)` (Task 1).
- Produces:
  - `struct Segmented<Value: Hashable>: View` with `init(_ label: String, selection: Binding<Value>, options: [(title: String, value: Value)])`
  - `struct ReadbackCheckboxStyle: ToggleStyle` and `extension ToggleStyle where Self == ReadbackCheckboxStyle { static var readbackCheckbox: Self }`
  - `struct Meter: View` with `init(fraction: Double?)` (nil = indeterminate)
  - `struct IconPlate: View` with `init(_ symbol: String, help: String, small: Bool = true, action: @escaping () -> Void)`

- [ ] **Step 1: Segmented**: a plate (`fill` + `edge`, radius by size) with 3 pt padding; the chosen segment a lighter plate (dark white 17% with white 16% edge; light white with black 12% edge) at radius − 3, moved with `matchedGeometryEffect` and `Motion.spring`; segments 16 pt side padding, unchosen text `.secondary`. Left/Right arrows step with `SegmentStep.step` when focused; focus ring `focusRing`. Accessibility: container labelled with `label`, each segment a button with `.isSelected` on the chosen one. Replace the Delivery `Picker`.
- [ ] **Step 2: Checkbox style**: 20 × 20 box, corner 6; off `fill` with `hoverEdge`; on `primaryFill` with a `checkmark` 11 pt bold in `primaryText` that pops in (`Motion.pop`, scale 0.4 → 1). Label to the right, spacing 12, whole row tappable; Space toggles when focused; `.accessibilityElement(children: .combine)` with the checkbox's value. Disabled at 40%. Replace both `.toggleStyle(.checkbox)` in SetupSheet.
- [ ] **Step 3: Meter**: 4 pt capsule, track `fill`, fill `primaryFill` at the fraction (animated with `Motion.spring`); nil fraction shows a 30%-wide segment sliding across over 1.2 s, or a still half-opacity track with Reduce Motion. Accessibility value: the percent. Replace the linear `ProgressView`s listed above (not the small spinners).
- [ ] **Step 4: IconPlate**: a square secondary plate (28 or 34 pt) with a 14 pt semibold glyph, same hover, press and edge as `ReadbackButtonStyle(.secondary)`, `.help` and `.accessibilityLabel` from `help`. Replace the Voices download cancel with `IconPlate("xmark", help: "Cancel the download and delete what it fetched")`, keeping its accessibility label `Cancel downloading \(name)`.
- [ ] **Step 5: Verify**: `swift build` clean; on the test copy, screenshot Voices with Qwen3 picked (segmented) in dark and light; open the setup sheet (Connections → Set up again, or `onboarded` false) and screenshot the checkboxes; start and cancel a small download to see the meter and the cancel plate. Arrow keys move the segment; Space toggles a checkbox.
- [ ] **Step 6: Commit**: `git commit -m "feat: Readback's own segmented control, checkbox, meter and icon plate"`

### Task 5: The waveform and the player's buttons

**Files:**
- Create: `Sources/Readback/Window/Components/Waveform.swift`
- Modify: `Sources/Readback/PlayerView.swift` (:305-308 icon buttons, :433 title chip mark, :572 list row mark, `IconButton`), `Sources/Readback/Window/MainWindow.swift:407`

**Interfaces:**
- Consumes: `WaveformMotion.frame(at:playing:reduceMotion:)`, `WaveformMotion.heights` (Task 1); `ControlMetrics` (Task 2).
- Produces: `struct Waveform: View` with `init(playing: Bool, height: CGFloat = 13)`; width follows from 7 bars of `height * 0.123` with gaps of `height * 0.06` (17 × 13 at the default).

- [ ] **Step 1: Waveform view**: bars as rounded rectangles in `.primary` (or the inherited foreground style), sized from `heights`, centred vertically. While `playing`, a `TimelineView(.animation)` drives `WaveformMotion.frame`; while not playing, no `TimelineView` at all (draw the still frame), so nothing redraws when idle. Reads `accessibilityReduceMotion`. `accessibilityHidden(true)`.
- [ ] **Step 2: Replace the marks**: `PlayerView.swift:433` → `Waveform(playing: reader.phase == .playing, height: 12)` in `Theme.label`; `:572` → `Waveform(playing: true, height: 10)` in `Theme.textActive`; `MainWindow.swift:407` → `Waveform(playing: reader.phase == .playing, height: 12)`.
- [ ] **Step 3: Player buttons**: the four `IconButton`s become 28 × 28 plates in the player's own tints: fill white 8%, hover 12%, press 16%, 0.5 pt edge white 13% (hover 20%), radius 8, glyph as today. Keep their symbols, sizes, help text and actions. The speed and Close chips don't change. Comment: owner approved plates for the player's buttons, 2026-11-25.
- [ ] **Step 4: Verify**: build clean; on the test copy, post a reply to the control server (`/speak` on port 8918 with Python `urllib`, macOS voice) and capture the player and the sidebar Reading card in several frames: bars move and sweep while playing, still on pause. Measure the player's buttons at 28 px.
- [ ] **Step 5: Commit**: `git commit -m "feat: a moving waveform for playing, and plate buttons in the player"`

### Task 6: Polish and the done check

**Files:**
- Modify: whatever the checks find; `.superpowers/sdd/2026-11-25-polish-and-dashboard/progress.md` (ledger, git-ignored)

- [ ] **Step 1: Run `design-eng-ui-polish`** over the changed views and fix what it finds.
- [ ] **Step 2: Run `ui-done-check`** on the test copy: every page (Home, History, Voices, Reading, Connections, About), the setup sheet and the player; dark and light; over a white and a busy desktop; at 760 × 500 and a large window; Reduce Motion on and off. Measure: controls 34/28 px, rows 54 px, switches 35 × 20, History header in one row.
- [ ] **Step 3: No blue**: for each screenshot, count pixels with HSB saturation > 0.35 outside the sidebar tiles and status icons; expect none.
- [ ] **Step 4: Checks**: `swift test` all pass; `./scripts/build-app.sh` 0 warnings.
- [ ] **Step 5: Ledger and commit**: add a line per task to the ledger (rulings, what was seen and not seen); commit any fixes: `git commit -m "fix: polish pass on the new controls"`.
