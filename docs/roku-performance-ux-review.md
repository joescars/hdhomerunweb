# Roku App Performance & UX Review — Action Plan

Review of the `roku/` client plus its server-side contract (`/api/guide`, `/stream/*`,
`deploy.sh`). The app is architecturally solid: all network I/O is confined to `Task`
nodes, the `POST /start` → poll `/ready` → `.m3u8` handshake is intact, guide refreshes
patch rows instead of rebuilding the content tree, and error text is kept screen-safe.
This plan targets the remaining performance gaps and UX gaps that the earlier
`docs/roku-ux-improvements.md` had yet to cover.

Levels: `[P]` = performance, `[U]` = UX/UI.

---

## Priority-one (biggest impact)

### P1. [P] Guide payload is 4–10× larger than the Roku uses

**Problem.** `/api/guide` returns **4 hours** of programs per channel, with
`title` / `episodeTitle` / `synopsis` / `image` for every program
(`src/routes/api.js:16, 44–51`). The Roku only renders three 30-minute slots, the
current program's details, and the next program's title
(`roku/components/GuideScreen.brs:286–318`). The client still:

- downloads and `ParseJson`s the whole payload every 5-minute refresh
  (`roku/components/GuideTask.brs:17–18`, `roku/components/GuideScreen.xml:26`), and
- re-scans every channel's full program array **5× on the render thread**
  (`findProgramAt` ×4 + `findNextProgramAt`, `GuideScreen.brs:342–369`) on first load,
  refresh, and filter switch (`applyGuideContent`, `GuideScreen.brs:244–273`). On
  100+ channel lineups that's 500+ linear scans and signature-string builds per
  refresh — a real hitch risk when it lands mid-scroll.

**Plan.**

1. Add a slim variant of the guide endpoint (server change, ~30 lines):
   - `GET /api/guide?slim=1` (or a separate `/api/guide/roku`) returning only what the
     Roku renders, with slot math precomputed server-side:
     `{ number, name, logo, favorite, slots: [{title, episodeTitle, synopsis, image}, ×3], nextTitle }`.
   - Give it its own cache key (`guide:duration:4` is taken by the full payload,
     `src/routes/api.js:13`); the server already caches upstream guide data, so this
     is a new key, not new upstream work.
2. Point `GuideTask.brs` at the slim endpoint when available.
3. **Client-only fallback** if the server can't change: keep the raw payload but do the
   flat row-field munging **once in `GuideTask`** (task thread) so the render thread
   only does cheap ContentNode field assignment.

**Done when:** guide refresh no longer blocks smooth scrolling on large lineups;
payload bytes per refresh drop by ~75%+.

---

### P2. [P] Live-preview tuner churn — "all tuners busy" during browsing

**Problem.** Every preview runs the full transcode handshake
(`startPreviewForFocusedChannel`, `GuideScreen.brs:514–538`): POST `/start` → poll
`/ready` → HLS session. The server keeps each session alive **20s after the last
request** (`IDLE_TIMEOUT_MS = 20_000`, `src/stream.js:9`, cleanup loop `953–962`), and
`stopPreview()` (`GuideScreen.brs:564–577`) only stops the Video node — nothing tells
the server to release. With the 0.9s debounce (`GuideScreen.xml:99`), brisk browsing
can briefly hold many tuners; on a 2-tuner device surf trips "All tuners are busy."

**Plan.**

1. **A. Add `POST /stream/:channel/:codec/stop` server-side** (highest-value item in
   this plan):
   - `stopSession()` is already exported (`src/stream.js:964–977`); wire a route next
     to `heartbeat` (`src/routes/watch.js:196–197`).
   - Call it from `stopPreview()` and `closePlayer()` (`PlayerScreen.brs:544–558`) so
     tuners/transcodes free immediately instead of after 20s.
   - Guard against stomping a *newer* session with the same key: skip stop if the
     session was started within the last ~2s, or require an idle grace period.
2. **B. Preview at `low` quality**, not default `medium` — the preview box is
   280×157px (`GuideScreen.xml:84–86`); `low` (1.8 Mbps vs 3.2 Mbps,
   `src/stream.js:31–50`) halves transcode CPU/bandwidth. Bonus: sessions are keyed
   by channel+codec+profile, so `h264/low` won't collide with an active
   `hevc`/`h264` playback session of the same channel. Client URL change only.
3. **C. Debounce → 1.5–2s**, or lengthen adaptively while `itemFocused` keeps firing
   (`GuideScreen.xml:99`).
4. **D. Cap the preview's poll budget** (~10s, not the full 30s cap in
   `StreamStartTask.brs:46`) and reuse one persistent `StreamStartTask` instance
   instead of creating one per preview.

**Done when:** rapid channel-flipping never exhausts a 2-tuner lineup; preview CPU
cost is roughly halved.
---

## Performance backlog

### P3. [P] Splash assets are ~5.9 MB of PNG

`images/splash_bg_screen.png` is 1920×1080 RGB **2.7 MB**; `splash_fhd.png` 1.5 MB;
`splash_hd.png` 1.35 MB. Loaded and decoded every cold start. Re-export with
quantization / lossy compression (Poster surfaces accept JPEG too) — target well under
500 KB each, or consolidate to one asset. `icon_focus_fhd.png` (540×405) at 300 KB is
also heavy.

### P4. [P] Guide refresh fires on focus *loss* too

`roku/source/main.brs:41–45` treats **any** `roDeviceInfoEvent` as a resume signal,
and `MainScene.brs:299–304` then triggers a full guide fetch + render-thread rebuild.
App-focus events also fire when focus is *lost* (backgrounding), so each app-exit can
waste a fetch/rebuild. Filter on `msg.GetMessageParam()` (focus-gain only — verify the
exact string on the target firmware before merging).

### P5. [P] Streaming stats task churn (minor)

`PlayerScreen.brs:336–353` creates a new `StreamStatsTask` node every 2.5s while
diagnostics are open. Reuse one task by re-setting
`serverUrl/channelNumber/codec/profile` and re-`RUN`-ing it; slow the tick to ~3s.
(Server side also does `statSync` segment scans + a device `status.json` call per
poll — minor, noted only.)

### P6. [P] First-load timeout and staleness on return

- `GuideTask.brs:18` uses a 15s timeout; right after a server restart the cold
  `/api/guide` (cloud guide + lineup) can exceed it. Raise it / retry once.
- `onPlayerClosed` (`MainScene.brs:235–245`) only re-renders the *cached* guide —
  after a long watch, slot titles are stale even if a half-hour rolled. Trigger a
  background `refreshGuide()` (server-cached, so cheap) when the player closes.

---

## UX / UI

### U1. [U] Cable-box tune banner while channel surfing (high value)

`Rewind`/`Forward` surfing (`PlayerScreen.brs:108–137, 521–528`) shows only the small
"Tuning <name>…" status line — it doesn't feel fast without a big channel identity on
screen. Add a full-width transient OSD: large channel number + name + logo + now/next.
Data is already in `m.channels`; just also pass `logo` / `currentImage` through
`tuneToChannelIndex` (`GuideScreen.brs:414–426` — logos already live in the content
nodes).

### U2. [U] Resume where you left off (from `roku-ux-improvements.md` #2)

Recent channels are recorded (`MainScene.brs:134–151`) and pinned to the top, but on
launch focus always starts at row 0. After the first guide load, set grid focus to the
first recent channel so a single **OK** resumes last night's show. The cheapest daily
"fast" win available.

### U3. [U] Favorite/unfavorite from the couch

Favorites require the admin web page today. The server plumbing exists
(`hdhr.setChannelFlag`, `src/hdhomerun.js:46–48`) but only as an HTML
`POST /admin/channels/flag` route (`src/routes/channels.js:54–65`). Add a small JSON
endpoint the Roku can hit, and surface a star toggle in the player OSD (or guide detail
panel) with an optimistic row update. Makes the Favorites filter (a flagship nav
feature) actually usable from the TV.

### U4. [U] Quality profile is invisible on Roku

The server supports `low|medium|high` (`src/stream.js:31–50`), but the Roku always
uses default `medium`, and `refreshStatsContext` hardcodes `"medium"`
(`PlayerScreen.brs:79–91`). Add a Settings quality selector (and/or per-session
profile in the player's Options OSD that restarts the stream). Meaningful for
Wi-Fi-connected Rokus and multi-tuner homes.

Side note while here: `src/routes/api.js:63` sends a hardcoded `hevc` `streamPath`
that the Roku ignores (`MainScene.brs:227` rebuilds it from the user's codec
preference). That field is dead weight in the payload — drop it in the slim endpoint
(P1) or fix it.

### U5. [U] First-run discoverability

Cold start with no configured URL shows "Failed to load guide: No server URL
configured" with the only path to Settings being an undocumented `*` press
(`GuideScreen.brs:85–97`, `onKeyEvent:581–597`). Add a first-run state: a hint line
("Press * to connect to your server") or auto-open Settings once when no URL has ever
been saved.

### U6. [U] Guide error state has no retry

The player got inline retry; the guide didn't. When the initial load fails, OK does
nothing. Give the guide an error state where **OK → `refreshGuide()`** — mirror the
player's `m.failed` pattern.

### U7. [U] Guide time paging — feasible client-only now

The guide only ever shows now + 60 min. A **Forward** key on the guide could shift the
three slots by 30-min increments (purely a render-time offset from already-downloaded
data), **Back**/Up returns to live. Even with a slim endpoint, a 1.5–2h window gives
several pages before any new fetch is needed.

### U8. [U] Navigation ergonomics

- Big-lineup scrolling: hold Down is slow. Map the **Replay** key to jump ~10 rows
  (from `roku-ux-improvements.md` #6).
- Set `ellipsizeOnBoundary=true` on the row title labels (`GuideRow.xml`) so long
  titles end in a tidy "…" instead of a hard clip.

### U9. [U] Settings polish

- Swap `KeyboardDialog` for `StandardKeyboardDialog`
  (`SettingsScreen.brs:136–151`) when willing to drop the oldest firmware.
- Validate the URL (scheme + host, no spaces/quotes) **before** saving; today only a
  trailing slash is trimmed (`SettingsScreen.brs:177–182`), so `foo` gets saved
  silently and only the async connectivity check catches it.
- The connectivity check already reports "Saved — connected/can't reach" — keep it.

### U10. [U] Small copy/visual fixes

- `SplashScreen.xml:32` hardcodes **"Loading Mittens' favorite channels..."** — a
  personal name shipped in the binary. Make it generic.
- Now/Next overlay shows titles but no "ends at" time; passing current program
  `start/duration` through the launch data (U1 already touches this array) allows
  "ends 8:30" — a big "what am I watching" improvement.
- `ChannelInfo.xml` / `ChannelInfo.brs` look like dead code: a leftover TimeGrid row
  renderer (the guide now uses `MarkupGrid` + `GuideRow`). Verify and delete.
---

## Suggested execution order

**Weekend-level, client-only:**

1. U2 (resume last channel) + U6 (guide retry) + U4's stats hardcode fix — all small,
   no server work.
2. P2-B/C/D (preview → low quality, longer/adaptive debounce, recycled task).
3. P3 (compress art), P4 (focus-loss filter), U10 copy fixes.

**Requires a small server change (one sitting):**

4. P1 slim guide endpoint (biggest perf win) + P2-A explicit `/stop` route (biggest
   reliability win).
5. U1 tune banner + U3 favorites endpoint + U7 time paging.

**Backlog:** U4 quality selector, U8 quick-scroll, U9 keyboard/validation.

> If implementing P1/P2-A, update both sides of the contract together and follow
> `AGENTS.md`: keep `POST /start` → poll `/ready` → `.m3u8` intact, keep the device
> `lineup.json` access on `getLineup()` with `?show=all`, and bump `build_version` in
> `roku/manifest` before every sideload.