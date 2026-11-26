# A session's replies: see all in History — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An open session on Home shows its 3 newest replies and a "See all N replies" that opens History showing only that session.

**Architecture:** History's matching moves into a Core `ReplyFilter` (session, tool, search words) with tests. The app's `Navigation` carries the session History should show; Home sets it, History reads it and draws a chip, and leaving History clears it.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-26-session-see-all-design.md`

## Global Constraints

- Home shows 3 replies per open session; "See all N replies" only when the session has more than 3.
- Copy: "See all \(n) replies", chip shows project then tool name in secondary text, ✕ help "Show every session", empty title "No replies from \(project)".
- Clear is hidden while a session is shown.
- Monochrome plates, 34 pt controls, 1 px edge, no accent colour (the look ledger's rules).

## Review Focus

- A session whose replies are all removed while History shows it: the empty card shows, and "Show all replies" brings everything back (Task 2, checked by hand).
- Search and session together: only replies in the session that match (Task 1 test `sessionAndSearchTogether`).
- A session with a tool picked earlier in the menu: the session wins, the tool menu doesn't narrow it further (Task 1 test `sessionIgnoresTool`).
- Replies with no session id (OpenCode) group by folder and tool; the filter must use the same key as Home (Task 1 test `sessionlessRepliesMatchTheirHomeKey`).
- Going Home and back to History: History is whole (Task 2, checked by hand).

---

### Task 1: Core `ReplyFilter`

**Files:**
- Modify: `Sources/ReadbackCore/SessionSummary.swift` (make `key(of:)` public, rename from `key(_:)`)
- Create: `Sources/ReadbackCore/ReplyFilter.swift`
- Test: `Tests/ReadbackCoreTests/ReplyFilterTests.swift`

**Interfaces:**
- Produces: `public static func SessionSummary.key(of reply: Reply) -> String`
- Produces: `public struct ReplyFilter: Equatable { public var session: String?; public var tool: Tool?; public var query: String; public init(session: String? = nil, tool: Tool? = nil, query: String = ""); public func matches(_ reply: Reply) -> Bool; public var isNarrowed: Bool }`. `query` is trimmed and case-insensitive, matched against `reply.text` and `reply.title`. With `session` set, `tool` is ignored.

- [ ] Step 1: tests `everythingWhenEmpty`, `sessionKeepsOnlyItsReplies`, `sessionIgnoresTool`, `sessionAndSearchTogether`, `searchIsTrimmedAndCaseless`, `toolNarrows`, `sessionlessRepliesMatchTheirHomeKey` (a reply with `session: nil` matches `ReplyFilter(session: SessionSummary.key(of: thatReply))` and the id Home's summary gives it).
- [ ] Step 2: `swift test --filter ReplyFilterTests` fails (no type).
- [ ] Step 3: implement; History's `filtered` will use it in Task 2.
- [ ] Step 4: `swift test` all green.
- [ ] Step 5: commit `feat: ReplyFilter: History's matching in Core, with a session`.

### Task 2: Home's three, History's chip

**Files:**
- Modify: `Sources/Readback/Window/MainWindow.swift` (`Navigation.historySession: SessionSummary?`; cleared whenever `section` changes away from `.history`; Home's `seeAll` clears it; new `openSession`)
- Modify: `Sources/Readback/Window/Home/SessionsList.swift` (`prefix(3)`, "See all N replies" quiet small button with `arrow.right`, `openSession: (SessionSummary) -> Void`)
- Modify: `Sources/Readback/Window/HistoryPages.swift` (HomePage passes `openSession`; HistoryPage takes `session: Binding<SessionSummary?>`, uses `ReplyFilter`, shows `SessionChip` in place of the Dropdown, hides Clear, empty-state copy)

**Interfaces:**
- Consumes: `ReplyFilter`, `SessionSummary.key(of:)` from Task 1.

- [ ] Step 1: build (`swift build`), 0 warnings.
- [ ] Step 2: `./scripts/build-app.sh`, launch the isolated test copy (memory `readback-ui-check-tooling`), seed a session with more than 3 replies, and screenshot: Home open session, History with the chip, search inside it, ✕, sidebar away and back, the empty state, light and dark.
- [ ] Step 3: `design-eng-ui-polish` and `ui-done-check`, fix what they find.
- [ ] Step 4: commit `feat: a session's replies: three on Home, see all in History`.
