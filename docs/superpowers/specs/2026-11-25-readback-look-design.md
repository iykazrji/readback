# Readback's own look: black-and-white plates

Approved look: the clickable mockup the owner signed off on 2026-11-25, kept at `.superpowers/brainstorm/19958-1795640505/content/look-plates.html` (git-ignored; open it through the brainstorm server or straight in a browser). Where this doc and the mockup disagree, ask; the numbers below were measured from it.

This replaces the look of "2. Controls and motion" in `2026-11-25-polish-and-dashboard-design.md`. The behaviour that section asks for (keyboard, type-to-jump, VoiceOver, menus that stay on screen, Reduce Motion) still stands. Only the look changes: no accent colour, bigger controls, a thin edge.

## Why

The owner opened the window after Piece 2 and found it generic: "They look generic because they are generic. The product doesn't have a distinct, refined look." The controls were stock macOS shapes with the bezel removed and system blue for anything that's on. The owner wants something elegant and their own, in black and white, with controls that feel substantial.

Success is the owner opening the window and every control looking like part of one set: same height, same plate, same edge, no blue anywhere, and the playing state matching the floating player.

## What the owner decided

- Monochrome. White and black tints only. No brass, no blue, no system accent anywhere in the window, the setup sheet or the player. (They looked at a brass-and-graphite direction taken from the app icon and turned it down.)
- Plates: a control is a flat plate of tint with a very thin outline. Picked over capsules and outline-only controls.
- Bigger controls: 34 pt tall instead of 28. "They're still too short… make them seem a lot more substantial."
- Switches shorter than the first mockup's 24 pt: 20 pt tall.
- The sidebar stays exactly as it is today: coloured icon tiles (`IconTile`, `MainSection.tint`), 22 pt tiles, the same row style. It's the one place colour stays.
- The playing mark is the player's waveform, and it moves: the sweep it has today plus bars that grow and shrink out of step, like a voice. The same mark everywhere something is playing.
- Still in force from before: flat, no shadows or glows on any button including the play button; the glass window (option A); every dropdown a custom popover; springs on press and open, a plain fade with Reduce Motion; every control in a row the same height to the pixel.

## Goals, non-goals, anti-goals

Goals: one set of controls (button, dropdown, search field, switch, segmented control, checkbox, icon button, meter, waveform) built from one set of measurements, used everywhere in the main window, the setup sheet and the floating player.

Not in this change: Home's new layout (Piece 3), resume and unheard (Pieces 4–5), the Kokoro step (Piece 6). Those come after, on top of these controls. Also not here: making the waveform follow the actual loudness of the voice (queued below).

Anti-goals, the ways this could technically work and still fail:
- Blue sneaking back in through a stock control (a `ProgressView`, a focus ring, a `.segmented` picker) because nothing overrode the system accent.
- A row of controls that doesn't line up because one of them still sizes from padding around text.
- Losing what Piece 2 built: keyboard use, type-to-jump, VoiceOver names and values, Reduce Motion.
- Colour coming back as decoration. The sidebar tiles are the only colour that isn't a status.

## The measurements

All of these go in `ControlMetrics` (`Sources/Readback/Window/Components/Buttons.swift`, or a new `Controls.swift` beside it), and nothing else hard-codes them.

Sizes:

| | Regular | Small |
|---|---|---|
| Height (buttons, dropdowns, search, segmented, icon buttons) | 34 | 28 |
| Corner radius (0.29 × height, rounded) | 10 | 8 |
| Text | 13.5 pt medium (primary: semibold) | 12.5 pt medium |
| Side padding | 16 | 12 |
| Quiet button side padding | 10 | 8 |
| Icon button | 34 × 34, 14 pt glyph | 28 × 28, 14 pt glyph |

Small is what the Voices rows and the floating player use. Settings rows grow from 52 to 54 pt (control height + 20) so a 34 pt control keeps the same breathing room; that means trimming each row's vertical padding, not just raising a minimum height. The focus ring token applies to every focusable control, not only search.

Colours, dark then light. Everything is white or black at an opacity, except the two solid plates.

| Token | Dark | Light |
|---|---|---|
| Plate fill, rest / hover / pressed | white 8% / 12% / 16% | black 4.5% / 7.5% / 10% |
| Edge, rest / hover | white 13% / 20% | black 11% / 18% |
| Primary plate | #F5F5F7, text #111113 | #111113, text #FFFFFF |
| Switch off track | white 12% + edge | black 9% + edge |
| Switch on track / thumb | #F5F5F7 / #1C1C1F | #111113 / #FFFFFF |
| Segmented chosen plate | white 17%, edge white 16% | #FFFFFF, edge black 12% |
| Menu panel | #222327 at 97%, edge white 13% | #FCFCFD at 98%, edge black 10% |
| Menu row highlight | white 8% | black 5% |
| Focus ring | white 55% | black 45% |

The edge is a 0.5 pt line drawn inside the shape (a hairline on Retina). The mockup also offered a 1 pt edge; the owner didn't choose, so hairline is my call. Text colours stay the system's `.primary` and `.secondary`, which are already black and white.

## Each control

**Button** (`ReadbackButtonStyle`). Four kinds, as now:
- primary: the solid plate above, no edge. Hover dims to 90%.
- secondary: plate fill plus edge. Hover and press step the fill and brighten the edge.
- quiet: text only (primary text colour, not accent), a plate fill under the pointer. "See all" gets a trailing `→` that nudges 2 pt right on hover.
- destructive: looks like secondary with secondary-coloured text that turns primary on hover. No red (my call; the confirmation it opens says what goes).

All of them sink to 0.97 when pressed and spring back. Disabled is 40% opacity.

**Dropdown** (`Dropdown.swift`). The button is a secondary plate with the value and an up-down chevron (`chevron.up.chevron.down`-style, secondary colour). The menu is the panel above: 12 pt corners, 6 pt padding, rows 30 pt tall (control height − 4) with 7 pt corners. The highlighted row gets the neutral highlight, not the accent fill it has today (`Dropdown.swift:284`). The chosen row has a check and medium weight. The menu keeps a soft drop shadow so it reads as floating; the owner was told and didn't object. Everything else about the menu (child window, keyboard, type-to-jump, flipping near screen edges) stays as built.

**Search field** (`SearchField.swift`). Same plate, edge and height as a button. Magnifier, prompt, a clear button that springs in, Esc empties it. Focus: the fill steps to hover and a 2 pt neutral ring appears 2 pt outside the edge. The width never changes.

**Switch** (`ReadbackSwitch`). 35 × 20, thumb 16, 2 pt inset. Off: tint track with the edge. On: solid track, contrasting thumb (table above). The thumb stretches 5 pt while held and springs across. Space toggles it; the row stays one VoiceOver switch (`SpreadSwitchStyle`).

**Segmented control** (new; replaces Qwen3's Delivery `Picker(.segmented)` at `VoicesPage.swift:91`). A plate with the edge, 3 pt padding, the chosen segment a lighter plate that slides to the new segment with the spring. Segments are text, 16 pt side padding; the unchosen ones in secondary colour. Left and right arrows move the choice. VoiceOver reads it as a radio group with the chosen value.

**Checkbox** (new; replaces `.toggleStyle(.checkbox)` at `SetupSheet.swift:103` and `:111`). 20 × 20, 6 pt corners. Off: plate fill with the hover-strength edge. On: the primary plate with a contrasting check that pops in with a spring. The whole row is the hit target, Space toggles it, VoiceOver reads it as a checkbox.

**Icon button** (new). A square plate with the edge. Where it goes (my calls, after the builder check found the mockup's player row used stand-in buttons):
- The floating player's four `IconButton`s, as they are in `PlayerView.swift` today: Start over, Back a sentence, Play/Pause, Next sentence. Small size, 28 × 28, in the 36 pt bar. Same buttons, same actions; only the look changes. The mockup's "Back 15 seconds", "Skip to the next reply" and ✕ were placeholders, not a behaviour change.
- The Voices download cancel (`VoicesPage.swift:483`): a small 28 × 28 icon plate with an `xmark`.
- Not the search field's clear button: it stays a 20 pt round button inside the field, as in the mockup.

The player's two `ChipButton`s, the speed chip ("1×") and the Close chip with its `esc` keycap, stay chips: a fill under the pointer, no edge, the keycap kept.

**Meter** (new; replaces the download `ProgressView`s in `VoicesPage.swift:155–157, 230, 465–467` and `SetupSheet.swift:359`). A 4 pt capsule: track in the plate fill, fill in the primary colour. When the total isn't known yet, a short segment slides across. My call; the owner hasn't seen a meter mockup.

**Waveform** (new, `Waveform.swift`). Seven bars in the shape of SF Symbols' `waveform`, about 17 × 13 pt. While playing: a highlight sweeps across them (dim bars at 30%, the lit bar at full, one pass about 1.25 s, like `.variableColor.iterative`), and each bar scales between about 45% and 115% of its height on its own loop (0.6–1.05 s, out of step). Paused or idle: still and at full strength. With Reduce Motion on: the bars stay still and only the sweep runs. It replaces every playing mark: `PlayerView.swift:433` (title chip), `PlayerView.swift:572` (the list row's mark, which today doesn't animate at all), `MainWindow.swift:407` (the sidebar's Reading card), and Home's Now card when Piece 3 builds it. The SF Symbol effect can't move bar heights, which is why it's a custom view.

**Play button** (Home's Now card, Piece 3). 38 pt circle in the primary plate, contrasting glyph, no shadow. Recorded here so Piece 3 uses it.

## Colour that stays, and colour that goes

Goes: every `Color.accentColor` in the app. Today that's `Buttons.swift:92, 101, 105`, `Switch.swift:22`, `Dropdown.swift:284`, `Surfaces.swift:48` (`cardActive`), `VoicesPage.swift:360` (the chosen voice's check), `SetupSheet.swift:346, 349, 397` ("Your turn" badge and its step icon) and the tool tiles at `SetupSheet.swift:417` and `ConnectionSettings.swift:165`.

My calls for the ones that carried meaning:
- Tool tiles (setup and Connections): connected is the primary plate with a contrasting glyph; not connected stays the grey tile it is today.
- `cardActive` (`Surfaces.swift:48`): a neutral tint, white 12% in dark and black 7% in light, not a solid plate, so the cards that use it keep their text and waveform as they are. It's used by the playing card in History (`HistoryPages.swift:338`), the sidebar's Reading card (`MainWindow.swift:423`) and the sidebar's Voice tile while pressed or selected (`MainWindow.swift:479`). The Voice tile is in the sidebar, but it's a pressed state, not one of the coloured section tiles the owner kept, so it goes neutral too.
- The chosen voice's check (`VoicesPage.swift:360`): primary colour (white in dark, black in light).
- "Your turn" badge: primary text on a plate fill.

Stays: the sidebar's coloured tiles (owner). The setup steps' green done check and red failed triangle, and any red error text, because they're status rather than decoration (my call; the owner said black and white, and this is the one place I'm reading that as "for the controls". Flag it if they disagree).

To stop stock pieces bringing blue back, the window, the setup sheet and the player panel set `.tint(.primary)` at their roots. That covers anything left stock (the small spinner in Connections, text selection in the search field). Checking for it is part of the done check below.

## Approaches

There's one sensible way to build this, so this records what was ruled out rather than a pick.

- Rebuild the existing components on new tokens (chosen). Piece 2 already put every control behind `ControlMetrics` and Readback's own views, so this is mostly changing numbers and colours in one place, plus four new components: segmented control, checkbox, meter and waveform.
- Only override the accent colour (set the app's accent to grey or `.tint(.primary)` everywhere) and leave the components alone. Ruled out: it can't change sizes, the edge or the plate, and the owner's complaint was that the controls look generic, not just blue.
- Restyle the remaining stock controls (`Picker(.segmented)`, `.toggleStyle(.checkbox)`, `ProgressView`) instead of replacing them. Ruled out: on macOS, SwiftUI draws those through AppKit and doesn't let you change their shape or fill, which is why Piece 2 replaced the switch and dropdown too.

## Constraints

- macOS 15 minimum, Swift 5 mode, SwiftUI in the AppKit window (`MainWindowController`). Nothing here needs a newer SDK; the waveform is plain SwiftUI shapes and a `TimelineView` or animations.
- The app has no tests (AGENTS.md). The only logic worth testing here is the segmented control's arrow-key movement; if it grows beyond a couple of lines, put it in `ReadbackCore` beside `MenuNavigation` with tests.
- Every product choice gets a comment where it lives, saying who chose it and when (AGENTS.md), e.g. on `ControlMetrics`: "Chosen by the owner on 2026-11-25: 34 pt plates in black and white with a hairline edge."
- `PageMetrics.headerHeight` and the page title row hold 34 pt controls without the header growing unevenly; the History header's search, dropdown and buttons must still share one baseline row.
- The window moves itself on macOS 27.2+ (`SelfDraggingWindow`); nothing new goes in the title bar row.

## Checking it

- Before calling it done: `design-eng-ui-polish`, then `ui-done-check`, on an isolated test copy (memory: `readback-ui-check-tooling`), dark and light, at the 760 × 500 minimum and a large window.
- Measure, don't eyeball: every control 34 or 28 pt in pixels; settings rows 54; the History header's controls share a top and bottom row; switches 35 × 20.
- Search the window's pixels for blue: screenshot every page and the setup sheet in both modes and confirm no pixel outside the sidebar tiles and status icons has noticeable saturation.
- Keyboard: Tab reaches every control; dropdowns, the segmented control, checkboxes and switches work from the keyboard; VoiceOver names and values read right (AX tree at least).
- Reduce Motion on: nothing slides or bounces; the waveform's bars stay still.
- `swift test` and `./scripts/build-app.sh` with no new warnings.

## Left to the builder

- File layout inside `Components/`.
- How the waveform animates (a `TimelineView` driving phases, or per-bar repeating animations), as long as it's cheap while idle: no timer or redraw when nothing is playing (PRODUCT.md, resource-efficient).
- Exact spring values, starting from `Motion.spring` / `Motion.pop`.

## Queued, not in this change

- The waveform following the real voice: Readback has the audio file before it plays, so it can compute loudness up front and drive the bars from playback time. The owner heard the idea on 2026-11-25 and didn't ask for it now.
