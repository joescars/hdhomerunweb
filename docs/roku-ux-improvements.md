# Roku App UX Improvements

Prioritized suggestions for the Roku client, focused on keeping it **simple,
clean, and fast** for users. Derived from review of the recent Roku commits
(`a38d7dd` guide UX/filters, `2b42e6b` section 4, `4fac634` settings UI) plus
the current `GuideScreen`, `PlayerScreen`, `StreamStartTask`, and `MainScene`.

## What's already solid

- Filter (All / Favorites) via ◀ ▶, favorite star per row, empty-filter
  message, and a persistent filter label.
- Settings has a clean card UI with status feedback.
- Streaming handshake is correct (start → poll → play) with friendly error
  headlines instead of raw ffmpeg output.
- Guide refresh diffs/patch rows instead of rebuilding the content tree, so it
  stays smooth.

## 1) Make the filter discoverable (trivial, high value)

**Problem:** ◀ ▶ switches All/Favorites, but nothing tells the user that.

**Fix:** Add a small persistent footer legend (`◀ ▶ Filter · ⚙ Options`) or a
one-time hint toast on first launch.

**Why:** Keeps the fast left/right model, just removes the guesswork. No server
work.

## 2) Resume last channel on launch (small, high value)

**Problem:** Every launch starts cold at the top of the guide.

**Fix:** Persist the last-watched channel in the registry (you already do this
for `serverUrl`). On guide open, restore focus to that channel and show a subtle
"Last: <name>" hint — or offer OK-to-resume.

**Why:** Biggest "fast" win for daily use; no new screen or server support.

## 3) Channel surfing while watching (medium, high value)

**Problem:** `PlayerScreen` ignores the Rewind/FF keys; users must back out to
the grid to change channels.

**Fix:** Map ◀◀ = previous channel, ▶▶ = next channel (in guide order, passed
from the guide). Re-run the existing handshake behind the "Tuning…" overlay.

**Why:** Keeps users in the fast lane without leaving playback. State already
exists to drive the overlay.

## 4) Inline Retry on stream failure (small, high value)

**Problem:** A failed tune (e.g. tuner busy) forces a Back-and-navigate-again.

**Fix:** On failure, show "Press OK to retry" and let OK re-run `startTuning()`
instead of only offering Back.

**Why:** Tiny change, large friction reducer during the most frustrating moment.

## 5) Guide time paging (medium, optional / phase 2)

**Problem:** The grid only shows the current + next two half-hours (a 1.5h
window). No way to look further ahead.

**Fix:** If `/api/guide` can take a time offset, let Replay/⭾ jump back to "now"
and a forward key page ahead.

**Why:** The natural next step for a "real" guide, but needs server support and
new client state — defer until 1–4 land.

## 6) Quick-scroll for large lineups (small, optional)

**Problem:** Holding ↓ is slow on big channel lists.

**Fix:** Use the Replay key to jump ~10 rows, or accelerate on key-repeat.

**Why:** Low effort; helps on heavy lineups without changing the mental model.

## 7) Settings: validate on save (small, optional)

**Problem:** After saving the URL, the user only sees "Saved" — no idea if the
server is reachable.

**Fix:** After save, fire a lightweight GET to confirm reachability and reflect
"Connected / Can't reach server" instead of just "Saved".

**Why:** Cheap confidence boost; no new screen.

## Recommended order

Do first (small, no server work, directly faster/less confusing):

1. #1 Filter legend
2. #2 Resume last channel
3. #4 Inline retry

Then, if desired:

4. #3 Channel surfing (needs channel order passed to player)
5. #6 Quick-scroll
6. #7 Settings validation

Phase 2 (needs server support):

7. #5 Guide time paging
