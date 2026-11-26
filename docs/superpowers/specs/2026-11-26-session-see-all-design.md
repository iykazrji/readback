# A session's replies: three on Home, the rest in History

Owner's ask, 2026-11-26: an open session on Home "can get really long" (one session had 23 replies and showed 10 one-line rows), and there was no way to see the rest. They wanted to see more, listed separately. They picked option A from two and approved the clickable mockup (`.superpowers/brainstorm/83460-1795673738/content/session-see-all.html`, git-ignored) with "build it out".

Who and when: someone back at the Mac who opens Home to find what one agent said earlier, and to hear it or read it. Home stays short; the full list lives where there's room to read.

## What gets built

- An open session on Home shows its 3 newest replies. Under them, "See all N replies →" (a quiet small button on the replies' left edge) shows only when the session has more than 3.
- "See all N replies" opens History showing only that session. History's header shows a chip in place of the "All tools" menu: the tool mark, the project name, the tool's name in secondary text, and an ✕ that goes back to every session.
- While History shows one session, Clear is hidden, so it can't read as "clear this session" when it would wipe everything.
- Search works inside the session. Cards are History's usual ones.
- The ✕, or going to any page from the sidebar, drops the session. The Sessions header's own "See all" opens History whole. So History is never left half-empty for the next visit.
- If nothing matches, the empty card says so ("No replies from readback" or "No replies match …") and "Show all replies" clears both the search and the session.

## Approaches

- A, picked: History filtered to the session. Reuses History's cards (2-line preview, full reply, copy, remove), search and day headers. The cost is a filter state that has to be dropped at the right moments.
- B, not picked: a session page inside Home with a back arrow. Reads as the session's own space, but it's a drill-in the app has nowhere else and mostly repeats History.
- Scrolling the open list in place was dropped early: it doesn't fix the length.

## Where the code goes

- Core: the session key becomes public (`SessionSummary.key(of:)`), and History's matching moves into a small `ReplyFilter` (session, tool, search words) with tests. With a session set, the tool menu doesn't apply.
- App: `Navigation` carries the session History should show; leaving History clears it. Home's sessions take an `openSession` callback. History reads the filter and draws the chip.

## Left to the builder

The chip's exact spacing follows `SetupChip` (34 pt, 7 pt before a 20 pt mark). The ✕ is a 24 pt quiet button inside the chip.
