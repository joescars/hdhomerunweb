# Changelog

All notable changes to this project are documented in this file.

## 2026-08-30

### Fixed: iOS Safari watch overlay - invisible on tap, then required a manual play tap

Two separate bugs found while chasing a "Watch button does nothing on iOS
Safari" report (desktop Chrome testing never caught either, since neither
is Chrome-specific).

**Bug 1 - overlay rendered with no size on iOS.** The tap *was* reaching
the handler (confirmed via a temporary on-screen "tap registered: X.X"
diagnostic, and a `window.onerror` banner that never fired, ruling out a
JS exception) - the `#watch-overlay` `<div>` (`position: fixed`, meant to
cover the whole viewport) just never became visible. Root cause: it was
nested inside `<main class="container">`, and `position: fixed` positions
relative to the nearest ancestor that establishes a new "containing
block" (any ancestor with a `transform`/`filter`/`will-change`/etc. -
plausible given Bootstrap's container/theme stack) rather than the
viewport itself if one exists, which can leave a fixed element sized to
nothing or off-screen. Fixed in `views/guide.ejs` by re-parenting the
overlay to be a direct child of `<body>` at script-load time
(`document.body.appendChild(watchOverlay)`), sidestepping the entire bug
class regardless of which ancestor was actually responsible. Also
replaced the CSS `inset: 0` shorthand (Safari 14.5+ only) with explicit
`top/right/bottom/left: 0` on `.watch-overlay`/`.watch-fullbleed` as a
defensive compatibility fix found during the same investigation.

**Bug 2 - video needed a manual play tap even once visible.** Classic
autoplay restriction: by the time `video.play()` actually runs (after the
async tune/`/ready`-poll sequence), the original tap's "user gesture"
window has closed, and iOS Safari blocks autoplay of *unmuted* video
without one. Also relevant: iOS Safari doesn't support the MediaSource
API `hls.js` needs, so iPhone playback was already going through the
native-HLS fallback branch (`video.canPlayType('application/vnd.apple.mpegurl')`),
not `hls.js` at all. Fixed in `views/watch.ejs` with a new
`attemptAutoplay()`: try `video.play()` normally first, and if the
returned promise rejects, fall back to `video.muted = true; video.play()`
(always allowed) so the video starts immediately either way - unmuting is
then one tap on the existing native player controls instead of the video
sitting frozen on frame one.

**Also fixed while investigating**: `server.js` serves `/public` with
`maxAge: '7d'` + `immutable: true` - great for performance, but means a
browser won't even revalidate a CSS file for a week without a version
bump in the URL. Added `?v=<%= assetVersion %>` (already used for the
`hls.js` CDN script) to the CSS/logo/favicon/apple-touch-icon links in
both `_client_header.ejs` and `_header.ejs` - `assetVersion` changes on
every server restart, making this a real per-deploy cache-buster, not
just cosmetic. (Turned out not to be the actual cause here, since Private
Browsing - which bypasses the HTTP cache entirely - showed the identical
bug, but it's a real gap worth having fixed regardless.)

Temporary diagnostics added during this investigation (on-screen JS error
banner, "tap registered" status text) were removed once both bugs were
confirmed fixed.

### Added: full-screen in-page video overlay for the mobile guide (no page navigation)

Tapping a channel's Watch button previously did a full `window.location`
navigation to `/watch/:channel` - a real page load, leaving the guide (and
its scroll position/filter state) behind. Now opens a full-screen overlay
in-page instead, closer to how a native app modal behaves.

- `views/guide.ejs`: new `#watch-overlay` (fixed full-screen `<div>` with a
  close button and an `<iframe>`) sits in the page, hidden until
  `watchChannel()` sets the iframe's `src` to `/watch/:channel?...&embedded=1`
  and shows it. Chose an iframe loading the *existing* `/watch` page over
  reimplementing the player inline, to avoid duplicating/risking the
  already-working HLS.js/captions/heartbeat logic there. Closing (X button,
  Escape key, or the device Back gesture via a `history.pushState`/`popstate`
  pair) hides the overlay and resets the iframe to `about:blank` - the
  latter matters, it's what actually stops playback and releases the
  tuner promptly rather than leaving a background stream running.
- `src/routes/watch.js` / `views/watch.ejs`: new `?embedded=1` query flag
  renders `/watch/:channel` full-bleed (`views/_client_header.ejs` gets a
  new `bare` option - no navbar, no page padding) instead of the normal
  page-with-header layout, so the video genuinely fills the screen rather
  than just being the normal page shown in a smaller frame. The player
  script itself (HLS.js setup, captions, heartbeat) is completely
  unchanged - only the surrounding markup differs between embedded and
  standalone.
- Desktop grid view (`guide-grid.ejs`) intentionally left as full
  navigation - this was scoped to the mobile guide specifically.
- Found and fixed a real bug while building this: `_client_header.ejs`'s
  new `bare`-mode `if/else` block was left unclosed across the file
  (`views/*.ejs` `include()` calls each compile as an independent
  function - an unclosed JS control block can't span across separate
  included templates, even though the *HTML* `<main>` tag it wraps
  legitimately can, matching the existing `_header.ejs`/`_footer.ejs`
  pattern already used elsewhere).
- Verified end-to-end with a scripted headless-Chrome test (Puppeteer,
  390×844 mobile viewport): clicking Watch opens the overlay with the
  correct iframe URL, video actually plays (screenshot showed live
  content + captions status), and closing returns to the exact same
  guide state with no reload - confirmed via `history.back()` correctly
  restoring the URL rather than a fresh navigation.

### Fixed: Live Preview "Off" setting didn't persist across app restarts

User report: turning Live Preview off in Settings, then fully exiting and
relaunching the app, always came back with previews active again -
Settings itself correctly showed "Off", but the guide behaved as if it
were on. Toggling it off again (a real change) fixed it for that session,
until the next relaunch.

Root cause: a classic Roku SceneGraph gotcha. `GuideScreen.xml`'s
`livePreviewEnabled` field had an `onChange` handler but no
`alwaysNotify="true"`. A boolean field's *implicit* default (before
anything sets it) is `false`. On a fresh launch with the setting off,
`MainScene.brs` sets the newly-created `GuideScreen`'s field to `false` -
the same as its already-default value - so SceneGraph treats it as a
no-op and never fires `onChange`. `GuideScreen.brs`'s own `m.livePreviewEnabled`
(set to `true` in `init()`, a value that lives on `m`, not `m.top`) never
gets corrected to `false`, so the screen behaves as if it's on. Turning it
off *again* mid-session works because that's an actual value change on an
already-initialized field, which does fire normally.

- `roku/components/GuideScreen.xml`: added `alwaysNotify="true"` to the
  `livePreviewEnabled` field, matching the pattern already used correctly
  elsewhere in this codebase (`openSettings`, `finished`, `closed`,
  `livePreviewSaved` all already have it) - this was the one field that
  was missed. Checked all other boolean fields across the Roku app for the
  same gap; none found (`SettingsScreen.xml`'s own `livePreviewEnabled` has
  no `onChange` at all - it's read directly, not reactively, so it was
  never affected by this bug, which is why Settings always showed the
  correct value even while the guide's behavior was wrong).
- Bumped Roku `build_version` to 51. Verified on-device: fresh launch with
  the setting off produced zero new sessions in
  `/stream/metrics` (previously would auto-tune a preview within ~1s of
  guide focus), and Settings still correctly showed "Off".

### Fixed: Direct mode now produces output for ATSC 3.0 ("NextGen TV") channels

A user report ("this channel doesn't stream, but the native HDHomeRun app
plays it fine") led to discovering this app has no ATSC 3.0 support at all.
Confirmed via direct ffprobe against the raw tuner source (channel 146.1,
WJZY): ATSC 3.0 channels broadcast **HEVC Main10** video and **AC-4** audio
- a completely different codec stack from the MPEG2/AC3 this app's entire
  pipeline assumes. The HDHomeRun FLEX 4K (this device) tunes ATSC 3.0
  fine at the RF level; the app's ffmpeg pipeline is what breaks.

**What's fixed**: `src/stream.js`'s Direct mode (`-c copy`, no
decode/encode) now uses a much larger probe budget (`-probesize 8M
-analyzeduration 8000000`, up from `500k`/`1s`) for that path only. Without
it, ffmpeg can't determine AC-4's sample rate/channel count in time and
`-c copy` fails outright ("Could not write header: Invalid argument") -
confirmed by direct manual ffmpeg testing against the real channel, both
before (fails) and after (produces valid HLS output with `hevc` video
confirmed via ffprobe on the actual output segments) this change. This
adds a few seconds of startup latency for Direct-mode sessions generally
(worth revisiting if it's noticeable on ordinary MPEG2/AC3 channels).

**What's still broken**: the H.264/HEVC transcode modes (`getDecodeConfig()`
in `src/stream.js`) still hardcode an MPEG2 decoder regardless of actual
source codec, so they fail outright for ATSC 3.0 channels (confirmed:
session never produces a playlist). Manually testing the fix path further
turned up a second, separate blocker: even with the correct `hevc_qsv`
decoder selected, `h264_qsv` encoding then fails ("Current pixel format is
unsupported") because ATSC 3.0's HEVC Main10 is 10-bit and needs an
explicit pixel-format conversion step before 8-bit H.264 encoding, which
the pipeline doesn't have. Out of scope for this pass - Direct mode is the
practical workaround for ATSC 3.0 channels in the meantime (switch to it
in Roku Settings, or `codec=direct` on web).

**Unverified**: whether AC-4 **audio** actually plays back correctly even
in Direct mode. ffmpeg's own remux warned `Stream 1, codec ac4, is muxed
as a private data stream and may not be recognized upon reading` - the
audio bytes are copied through, but ffmpeg couldn't fully classify the
AC-4 bitstream during remux and tagged it generically in the output
container instead of properly as AC-4. Whether a real player (browser/
Roku) still recognizes and decodes that track is unconfirmed - needs a
real on-device playback test with audio, not just an ffprobe/HLS-structure
check from the server side.

### Added: OK button shows the now/next info bar during playback

Follow-up to the now/next info overlay - it was only reachable via the `*`
(Options) button, which is less discoverable than OK for "what am I
watching" during normal playback (OK previously did nothing during active
playback; it was only bound for retry-after-failure).

- `roku/components/PlayerScreen.brs`: factored the show/hide toggle into a
  new `toggleChannelInfo()`, now bound to both OK and `*` during normal
  playback. OK still retries tuning when in the failed state (`m.failed =
  true`), same as before - the new behavior only applies otherwise.
- Bumped Roku `build_version` to 50. Verified on-device: tuned a channel,
  waited past the 5s auto-hide, pressed OK - info bar reappeared
  (`3.5 Oxygen`, `Now: The Real Murders of Atlanta - Lost & Found`, `Next:
  Dateline: Secrets Uncovered`) with playback and captions uninterrupted.

## 2026-08-29

### Added: LunaTV mobile client, admin pages moved to /admin

The web app was one undifferentiated set of pages - TV Guide sitting in the
same nav bar as Channel Lineup/Scan/Status, all in plain Bootstrap dark
theme. Split into two experiences: a new LunaTV-branded mobile-first client
(Guide + Watch, now the default landing page) and an admin area for
device setup/management, moved under `/admin` but otherwise functionally
unchanged.

**Routing** (`server.js`, `src/routes/guide.js`):
- `index.js`/`channels.js`/`scan.js`/`status.js` now mounted at `/admin`
  (`app.use('/admin', ...)`) instead of the root - internal route paths
  inside those files didn't need to change, Express prefixes them
  automatically. `/channels`, `/scan`, `/status` (old paths) now 404 by
  design; everything lives under `/admin/*`.
- `guide.js`'s handler is now registered on both `/` and `/guide` (same
  function, `renderGuideHome`) - the guide is the new front door, `/guide`
  kept as an alias.
- All internal `hx-get`/`hx-post`/`href` references in admin views
  (`_channel_row.ejs`, `_channel_rows.ejs`, `_scan_status.ejs`,
  `_tuner_status.ejs`, `channels.ejs`) updated to the new `/admin/*` paths.
- `index.ejs` (now the `/admin` landing page): dropped the "TV Guide" tile
  (that's the whole app now, not an admin function) and added a "← Back to
  TV Guide" link back to `/`.

**New LunaTV branding for web** (reusing the same source art as the Roku
app's icons/splash, for a consistent identity across both clients):
- `public/images/logo.png` - transparent horizontal logo lockup, used in
  the new client header.
- `public/apple-touch-icon.png` + `public/images/favicon-*.png` (16/32/48/
  192/512) - iOS "Add to Home Screen" now gets a real icon instead of the
  generic default, which matters since the mobile web app is a legitimate
  no-App-Store way to get LunaTV on an iPhone home screen today.
- New `views/_client_header.ejs`: a separate page shell from the existing
  `_header.ejs` (kept for admin pages) - dark-only (no light/dark toggle,
  matching the Roku app's design - a lot of streaming apps are dark-only
  and it simplified the palette work), LunaTV logo instead of a nav bar,
  small gear icon linking to `/admin` instead of a full nav (the client
  experience shouldn't expose admin concerns at all).
- New `public/css/client.css`: LunaTV's dark navy/blue palette
  (`#0a1428`/`#38bdf8`, matching the Roku app's `0x0A1428`/`0x38BDF8`)
  as CSS custom-property overrides scoped to `body.client-theme`, so admin
  pages keep plain Bootstrap dark/light untouched.

**Mobile guide redesign** (`views/guide.ejs`, `views/_guide_accordion.ejs`):
- Found and fixed a real gap: the mobile accordion guide had **no way to
  actually start watching a channel** - only the desktop grid view
  (`guide-grid.ejs`) linked to `/watch/:channel`. Tapping a channel in the
  mobile guide just expanded/collapsed program details with no path to
  playback at all.
- Redesigned each channel row as a card: channel number, name, and a
  "NOW: <title>" line (tap to expand for full upcoming-program details,
  same data as before) alongside a dedicated large circular Watch button
  (`.btn-watch`) that's always present and one tap away - no expand step
  required to start watching.
- The Watch button reuses the same prewarm-then-navigate pattern already
  used by the desktop grid (`chooseQualityProfile()` from
  `navigator.connection`, fire `/stream/.../start` immediately, navigate to
  `/watch/:channel` ~140ms later regardless) so the transcode is already
  spinning up server-side by the time the watch page loads.
- Filter pills (Favorites/Show Hidden) and channel-count text restyled to
  match the new theme; favoriting itself intentionally stays on the admin
  Channels page only (per discussion - starring is a setup-time action, not
  an everyday one for this use case).
- `guide-grid.ejs` (desktop grid) and `watch.ejs` also switched to the new
  `_client_header.ejs` for consistent branding, otherwise functionally
  unchanged - the desktop grid's own layout/interaction wasn't in scope for
  this mobile-focused pass.

Verified via headless Chrome at a 390×844 (iPhone-sized) viewport: guide,
watch, admin, and admin/channels all render correctly with the new theme
and working navigation.

### Added: show thumbnail in the Roku live preview box (instead of black while loading)

Follow-up to the live-preview feature - the preview box showed solid black
for the entire debounce + tuning-handshake window (several seconds) before
any video appeared, and stayed black on any preview failure.

- `GuideScreen.xml`/`.brs`: new `previewThumbnail` `Poster` node, layered
  behind `previewVideo` at the same position/size. Updated instantly (no
  debounce - it's just a field read, not a network request) on every focus
  change via a new `updatePreviewThumbnail()`, independent of whether live
  preview is even enabled, so it's the *only* thing shown when the Settings
  toggle is off.
- Shows the **currently-airing program's own artwork**, not the channel
  logo - a new `CurrentImage` field threaded through `findProgramAt()` →
  `buildGuideRow()` → `patchGuideRowNode()`, sourced from the same
  per-program `image` URL (`p.ImageURL`) the web guide already displays in
  its list view (`src/routes/api.js`). No fallback to the channel logo if a
  program has no artwork of its own - explicitly requested to be the show
  thumbnail specifically, not a logo substitute.
- Found and fixed a real bug along the way: `previewVideo` had no explicit
  `visible` state and defaulted to `true`, so it painted solid black
  (Roku's `Video` node does this even with no content/not playing - same
  reason `PlayerScreen.xml`'s video starts `visible="false"`) permanently
  over the thumbnail regardless of playback state. Now `visible="false"`
  until `onPreviewStreamResult` actually has a ready stream, and set back
  to `false` in `stopPreview()`.
- Verified the image genuinely loads (`loadStatus=ready` via temporary
  debug logging, since screenshots can't show anything in the video-plane
  region - the same blind spot established earlier this session for full
  playback) and confirmed visually on-device.

### Added: Settings toggle to disable Roku live preview

Follow-up to the live-preview feature below - each preview holds a tuner
while it plays, which is a real constraint for anyone with only 2-4 tuners,
so it needed to be an escape hatch rather than an always-on behavior.

- New "Live Preview" row in Settings (`SettingsScreen.xml`/`.brs`),
  Up/Down toggles On/Off (previously-unbound keys on this screen; Left/Right
  was already codec, OK was already edit-URL). Grew the settings panel
  (820px → 930px tall) to fit it without cramming.
- Persisted to registry (`livePreviewEnabled`, "on"/"off", default on -
  most users benefit from it and it's already debounced/best-effort-silent).
  Threaded through `MainScene.brs` the same way as `streamCodec`:
  read at launch, passed to both `GuideScreen` (to gate the actual preview
  logic) and `SettingsScreen` (to show/edit it), written back via a new
  `livePreviewSaved` out-field.
- `GuideScreen.xml`/`.brs`: new `livePreviewEnabled` in-field with
  `onChange` - flipping it off immediately calls `stopPreview()` even if a
  preview is actively playing, not just on the next focus change.
  `restartPreviewDebounce()` is now the single gate-check point for every
  call site (channel focus, returning from Player/Settings).
- Verified on-device (`.34`, since `.39`'s ECP is still in Limited mode -
  see below): toggled off in Settings, returned to the guide, scrolled
  through several rows - `/stream/metrics` confirmed zero new sessions
  (previously one per settled focus), and the preview box stayed empty.
  Toggled back on and it resumed normally.

**Test device note**: per user request, `.39` is now the default
`ROKU_IP` in `roku/.env` for future sessions. It currently has ECP
("Control by mobile apps") set to Limited mode, which blocks the
keypress/launch/query-apps remote-driving this session has relied on for
on-device verification (screenshots still work, since that's a separate
HTTP mechanism, not ECP) - loosen that under Settings → System → Advanced
system settings on the device if full remote verification is wanted there
too.

### Added: Roku guide UX - live preview, recently-watched pinning, now/next overlay

Three related UX features, built on `feature/roku-ux-preview-favorites-epg`:

**Live channel preview while browsing the guide** (`GuideScreen.xml`/`.brs`):
plays the currently-focused channel in a small 280x157 box in the detail
panel. Debounced via a new one-shot `previewDebounceTimer` (0.9s) so
scrolling through rows doesn't spawn a transcode/tuner session per row -
only the row the user actually pauses on gets previewed, confirmed
on-device (`/stream/metrics` showed exactly one new session after 5 rapid
`Down` presses, not five). Always requests `h264` regardless of the user's
main playback codec preference - same reasoning as the caption work,
lowest-risk path, and a background preview is not the place to test
Direct/HEVC. Entirely best-effort: any failure is silent (box just stays
black), since a background preview must never interrupt guide browsing.
Explicitly stopped (`stopPreview()`) before handing off to the real player
or opening Settings, so it doesn't hold a second session on a potentially
scarce tuner pool - restarted automatically via `onScreenFocus()` when
returning to the guide. Removed the detail panel's static legend label to
make room; folded its hint text into the header's filter label instead.

**Recently-watched channels pinned to the top of the guide** (`MainScene.brs`,
`GuideScreen.brs`/`.xml`, `GuideRow.brs`/`.xml`): local-only (registry key
`recentChannels`, most-recent-first, capped at 6 - not synced with the web
app's server-side favorites), recorded whenever a channel is selected from
the guide. Applied within both the All and Favorites filters via a new
`pinRecentChannels()` reorder step. Recent rows get a thin left-edge accent
bar (`GuideRow`'s new `IsRecent` field) so they're visually distinguishable
from the rest of the list, not just reordered. Confirmed on-device: a
watched channel moved from its normal alphabetical position to the top of
the list on return to the guide.

**Now/next mini info overlay during playback** (`PlayerScreen.xml`/`.brs`):
a bottom bar showing channel name plus current/next program title, shown
automatically for 5s (new `infoHideTimer`) whenever you tune or channel-surf,
and re-summonable on demand via the `*`/Options button (previously unbound
in the player). Program data flows from `GuideScreen.buildGuideRow()`
(extended with a new `findNextProgramAt()` - programs are contiguous per
`src/routes/api.js`, so "next" is just the soonest program starting after
now) through `tuneToChannelIndex()`'s per-channel array and
`MainScene.onLaunchPlayer`/`PlayerScreen.changeChannelBy()`. This is a
snapshot from guide-fetch time, not live-updated during long viewing
sessions - accurate whenever you tune/surf, which covers the primary
"what is this" use case without adding a periodic re-fetch loop.

Bumped Roku `build_version` to 42. Direct channel-number entry (the fourth
UX idea originally discussed) was explicitly excluded from this pass.

### Added: Roku branded splash screen (LunaTV artwork) and new app icons

New custom-branded ("LunaTV") artwork replaces the placeholder Roku channel
icons and splash images, plus a new animated-timing splash screen shown for
a fixed 2s on launch with a status message, instead of just the static
manifest-level splash.

- `roku/images/icon_focus_{fhd,hd,sd}.png` and `splash_{fhd,hd}.png`
  regenerated from supplied source art (center-cropped to each file's
  existing aspect ratio/pixel dimensions, so no manifest changes were
  needed - `mm_icon_focus_*`/`splash_screen_*` already pointed at these
  filenames).
- New `roku/components/SplashScreen.xml`/`.brs`: a full-screen custom
  screen (not the manifest's static `splash_screen_*`, which can't have
  dynamic content) showing a new `splash_bg_screen.png` (full 1920x1080,
  cropped from the same source art) with a bottom-right status label
  ("Loading Mittens' favorite channels...") for a fixed 2 seconds via a
  `Timer` node, then fires a `finished` field.
- `roku/components/MainScene.brs`: `init()` now pushes `GuideScreen`
  *before* `SplashScreen` (rather than instead of it) - pushing a screen
  hides whatever's beneath it, so the guide's data fetch starts
  immediately in the background while the splash is visible on top,
  instead of only starting after the splash's 2s elapses. `onSplashFinished`
  just pops the splash, revealing the (by then likely already-loaded)
  guide underneath - verified on-device via screenshot immediately after
  the 2s mark showing a fully populated guide, not a loading state.
- Bumped Roku `build_version` to 40.

### Added: real resolution/framerate/bitrate in Roku stream diagnostics

The stats panel only ever showed *configured targets* (`Video target: 3200k
(h264_qsv)`), which is meaningless in Direct mode since there's no encoder
to target anything - and never showed resolution, frame rate, or audio
format at all for any mode. Requested after Direct mode landed, since
that's exactly when "what is this actually broadcasting?" becomes an
interesting question ffprobe can answer but the app wasn't surfacing.

- `src/stream.js`: the existing periodic output-probe (already running
  every 15s for caption detection, in `maybeProbeCaptionTarget`) now also
  extracts video (`codec`, `profile`, `width`/`height`, a friendly
  `resolutionLabel` like `720p`/`1080i`, `frameRate` decoded from ffprobe's
  fraction format, `pixelFormat`) and audio (`codec`, `sampleRateHz`,
  `channels`, `channelLayout`) info via a new `parseMediaInfo()` — same
  ffprobe call, no added cost. Stored in a new `session.mediaInfo`, exposed
  on `/stream/:channel/:codec/:profile/stats`.
- ffprobe's per-stream `bit_rate` field turned out to be unpopulated for
  MPEG-TS/HLS content (it's metadata more commonly carried in containers
  like MP4) - `formatBitrateBps` from `-show_format` was null too. Added a
  separate `computeMeasuredBitrate()` that reads the actual segment files
  referenced by the live `.m3u8` (`#EXTINF` duration × file size on disk)
  and computes real bytes-per-second - cheap local FS reads, no extra
  ffprobe/ffmpeg process, refreshed on every `/stats` request rather than
  throttled to the 15s probe interval. This is the only reliable bitrate
  number for Direct mode, where there's no configured target to fall back
  on, and is more honest than a target/max rate for transcoded modes too
  (shows what's actually being delivered, not what was asked for).
- `roku/components/PlayerScreen.brs`: stats panel now shows "Actual video:
  720p • 59.94 fps • MPEG2VIDEO Main" / "Actual audio: AC3 • 48kHz •
  stereo" / "Measured bitrate: 6.48 Mbps (last N segments)" lines. Also
  removed the Captions/Caption probe error/Input captions/Input probe
  error/WebVTT sidecar/WebVTT error lines per request, now that captions
  work reliably via the `eia608/1` `SubtitleTracks` fix and that whole
  diagnostic cluster (built when captions were still broken) was just
  noise going forward.
- Bumped Roku `build_version` to 39. Verified on-device: channel 3.5
  (Direct mode) correctly showed 480p/29.97fps/MPEG2VIDEO Main, AC3/48kHz/
  stereo, and 0.94 Mbps measured - all independently plausible for an SD
  ATSC subchannel.

### Fixed: Roku Settings screen showed stale values on first open

`roku/components/SettingsScreen.brs`'s `init()` called `updateUrlLabel()`/
`updateCodecLabel()` immediately, but `init()` runs the instant
`CreateObject("roSGNode", "SettingsScreen")` executes in
`MainScene.brs`'s `onOpenSettings` — *before* the very next lines in that
same function assign `screen.serverUrl`/`screen.streamCodec`. So the first
time Settings opened after an app launch, both labels rendered from unset
field values instead of the actual persisted registry values, only
becoming correct after the user pressed Left/Right once (which calls
`updateCodecLabel()` again, this time with fields actually populated).

- Moved the label-refresh calls (and `m.top.streamCodec =
  normalizeCodec(...)`) out of `init()` and into `onScreenFocus()`, which
  `MainScene.brs`'s `pushScreen()` explicitly calls *after* the caller has
  set the screen's fields — this is exactly what that function's own
  doc comment already says it's for ("callable from MainScene when this
  screen becomes top-of-stack"), it just wasn't being used for this.
- Bumped Roku `build_version` to 38. Initially verified via a fresh app
  launch → immediate Settings open → screenshot, showing correct Server URL
  and Streaming Mode values on first render. A later re-check produced a
  confusing mismatch (Settings briefly showed a stale codec again), but
  that session had remote-control input arriving from two sources at once
  (automated ECP keypresses plus the physical remote) on the same live
  device, which is enough on its own to explain inconsistent screen state
  without implicating this fix - not conclusively re-confirmed clean. If
  this resurfaces, retest with only one input source active at a time.

### Added: Roku "Direct" streaming mode (experimental, no server transcoding)

New third option in Roku's Settings → Streaming Mode, alongside H.264/HEVC:
`Direct / no transcoding`, which remuxes the tuner's raw MPEG2/AC3 straight
into HLS segments (`-c copy`, no QSV decode or encode at all) instead of
transcoding. CLAUDE.md previously stated raw MPEG-TS isn't a supported Roku
stream format - that's still true for the *raw, unsegmented* transport
stream, but it turns out wrapping the same untouched MPEG2/AC3 bytes into
HLS segments (which Roku already knows how to pull apart) **does** play on
this hardware. Confirmed working end-to-end on a real device, video +
audio + captions, using the same remote-debugging technique documented in
the entry below (ECP keypresses, telnet console, server-side stream stats).

- `src/stream.js`: added a `DIRECT_CODEC = 'direct'` path in `spawnFfmpeg()`
  that builds a minimal `-c copy` ffmpeg invocation (no `-hwaccel`, no
  decode/encode args, no bitrate targets - there's no encoder to target)
  instead of the QSV transcode path. Session/stats metadata reports
  `decodeMode: 'none'`, `videoDecoder`/`videoEncoder`/`audioEncoder: 'copy'`.
  Reuses the exact same session lifecycle (idle timeout, heartbeat, tuner
  busy detection, HLS serving) as the transcoded paths - `codec` was already
  a first-class dimension of the session key and URL path
  (`/stream/:channel/:codec/:profile/...`), so `direct` slots in without
  touching that plumbing.
- `src/routes/watch.js`: `CODEC_RE` now allows `direct`.
- Roku: `direct` is a third value alongside `h264`/`hevc` in the *same*
  codec preference (not a separate setting) - `normalizeCodec`/
  `normalizeStreamCodec` in `MainScene.brs`, `SettingsScreen.brs`,
  `PlayerScreen.brs`, and `StreamStartTask.brs` all now accept it, and
  `SettingsScreen.brs`'s `toggleCodec()` cycles all three
  (H.264 → HEVC → Direct → H.264 …) rather than just two. This reuses 100%
  of the existing stream-start handshake and Video node setup - Roku's
  `content.streamFormat` stays `"hls"` either way, since direct mode still
  delivers HLS, just with unmodified segment payloads.
- `roku/components/PlayerScreen.brs`: the `eia608/1` `SubtitleTracks` fix
  from the entry below is now applied for `direct` as well as `h264` -
  since stream copy touches no bytes, any embedded CC in the source MPEG2
  user_data survives unchanged, and it turns out Roku's Video node can
  extract it the same way it does from h264 SEI. Confirmed on-device:
  captions render in Direct mode too.
- `roku/components/PlayerScreen.brs`: added a Direct-mode-specific hint
  ("Direct mode may be unsupported - try H.264/HEVC in Settings") to the
  playback-error overlay, since a decode failure is the most likely failure
  mode for this path on hardware that doesn't support it (the stream itself
  will start fine either way, since ffmpeg is just remuxing).
- Bumped Roku `build_version` to 37 (36 shipped the codec-cycle/settings UI,
  37 added captions for direct mode).

Caveat: this was tested on one Roku device/model. MPEG2 decode support is
known to vary across Roku hardware generations (the CLAUDE.md note this
entry partially revises was itself based on prior testing), so "works here"
is not "works on all Roku models" - the whole point of making this an
easily-revertible Settings toggle rather than a default.

### Fixed: Roku Video node now actually renders embedded captions

Follow-up to the codec-default fix below. Even after Roku was defaulted to
`h264` (verified server-side: a real Roku-initiated session showed
`captionActive: true`, `captionStrategy: a53cc_h264_qsv`, same working
pipeline as web), captions still didn't render on-device — Roku's system
Settings → Accessibility → Captioning track reported "Not available" even
with "Closed captioning: On always" set.

Root cause: unlike a TV or a browser (hls.js), **Roku's SceneGraph Video
node does not auto-detect embedded EIA-608 captions from H.264 SEI data at
all** — confirmed via Roku's own developer docs
([developer.roku.com/dev/docs/closed-caption](https://developer.roku.com/dev/docs/closed-caption)).
It only looks for a caption track if the `ContentNode` explicitly names one
via `SubtitleTracks`, with `TrackName` set to the literal string `"eia608/n"`
(n = caption channel). This is a Roku-specific requirement with no
equivalent on the web side, which is why it wasn't caught by the earlier
(correct) web fix.

- `roku/components/PlayerScreen.brs` (`playStream`): the `ContentNode` now
  sets `content.SubtitleTracks = [{TrackName: "eia608/1", Language: "eng",
  Description: "English"}]` whenever the active codec is `h264` (the only
  codec path that embeds caption data — see the fix above). Confirmed
  working end-to-end on-device: system Settings → Accessibility →
  Captioning track now lists the track, and captions render live.
- Verification method used for this whole Roku pass, worth keeping in mind
  for future Roku debugging: sideloaded via `roku/deploy.sh`, drove the app
  remotely via Roku's ECP (`POST http://<roku-ip>:8060/keypress/<Key>`,
  `POST .../launch/dev`), captured the telnet debug console
  (`nc <roku-ip> 8085`), and cross-checked the server's own
  `/stream/:channel/:codec/:profile/stats` for the Roku-initiated session to
  confirm codec/caption-strategy without needing to be in front of the TV.
  Screenshots via `POST --digest -u rokudev:<password>
  http://<roku-ip>/plugin_inspect` (form field `mysubmit=Screenshot`) then
  fetching `http://<roku-ip>/pkgs/dev.jpg` only capture the UI/graphics
  layer, **not** the hardware video overlay plane — a black background
  behind UI elements in such a screenshot does not mean video isn't playing.

### Fixed: Roku now defaults to a codec that supports closed captions

Follow-up to the web caption fix below. Checked `hevc_qsv`'s full ffmpeg
option list directly (`ffmpeg -h encoder=hevc_qsv`) and confirmed it has no
caption-related option at all — no `-a53cc` equivalent exists for this
encoder. (Software `libx265` does support `-a53cc`, but full software HEVC
encoding is far more CPU-expensive than hardware QSV and isn't a viable
default for a live multi-stream server.) Since Roku defaulted to HEVC
(`hevc_qsv`), it had no caption path at all regardless of source content,
even after the web fixes below — `roku/components/SettingsScreen.xml`
already advised "Use H.264 if you need closed captions support" but that was
advisory text only, with nothing in code defaulting to or enforcing it.

- Flipped the default codec from `hevc` to `h264` in all four places it's
  independently resolved (BrightScript components can't easily share code,
  so each has its own `normalizeCodec`/`normalizeStreamCodec` fallback):
  `roku/components/MainScene.brs` (`normalizeStreamCodec`, `readStreamCodec`),
  `roku/components/SettingsScreen.brs`, `roku/components/PlayerScreen.brs`,
  `roku/components/StreamStartTask.brs`. `h264` still maps to `h264_qsv`
  (hardware encode) via `CODECS` in `src/stream.js` — this is not a
  software-encoding fallback, just a different hardware codec choice, using
  the same pipeline validated for web (requires `STREAM_DECODE_MODE=sw`,
  already the global default as of the fix below).
- Updated `SettingsScreen.brs` caption-availability label text from
  hedged ("captions may be unavailable") to definite ("closed captions
  unavailable" / "closed captions supported") now that this has been
  confirmed rather than assumed.
- Bumped Roku `build_version` to 34 in `roku/manifest`.

Users who don't need captions and want HEVC's bitrate/quality edge can still
switch to HEVC in Settings — the registry-persisted preference and manual
toggle are unchanged, only the default changed.

### Fixed: Web closed captions actually working end-to-end (root cause found and resolved)

Phase 1 (2026-08-28) shipped two caption mechanisms — embedded `-a53cc`
passthrough and an experimental WebVTT sidecar — but neither had been
validated against a real device/channel, and web captions did not work.
This entry documents the diagnosis and the two real fixes; see
`docs/closed-captioning-options.md` for the full narrative and rationale.

**Diagnosis process** (channel WSOC-TV 9.1, confirmed CC-carrying via VLC on
the raw tuner URL as ground truth):

- Server's own `output_ffprobe` caption diagnostics (`session.captions.detected`)
  reported `false` even once captions were confirmed working end-to-end in the
  browser — ffprobe's `closed_captions` stream field is an unreliable
  detector for this content and should not be trusted at face value in
  `/stream/:channel/:codec/:profile/stats`.
- With the sidecar off and default (`qsv`) decode mode, VLC showed **no**
  caption track on our own transcoded `stream.m3u8` output, despite
  `captionActive: true` (i.e. `-a53cc 1` was applied). Root cause: full
  hardware QSV decode (`mpeg2_qsv`) does not propagate A/53 CC user-data as
  frame side-data to the encoder, so there is nothing for `-a53cc` to embed.
  Switching to `STREAM_DECODE_MODE=sw` (software `mpeg2video` decode, still
  QSV-encoded) fixed this — confirmed via VLC showing captions on the
  transcoded output.
- The WebVTT sidecar (`startWebVttSidecar` in `src/stream.js`) was
  separately found to be a dead end: ffmpeg's own `subcc`/EIA-608 decoder
  *does* detect and start decoding this channel's caption data (visible in
  its stderr: `[Closed Captions Decoder] Data ignored due to columns
  exceeding screen width`), but drops every cue before writing any, due to
  an unfixed upstream ffmpeg bug —
  [ffmpeg trac #11101](https://www.mail-archive.com/ffmpeg-trac@avcodec.org/msg67927.html) —
  confirmed still present in the container's ffmpeg 7.1.4 build. `captions.vtt`
  stayed at just the `WEBVTT` header for the life of the session regardless of
  source content.
- With `sw` decode confirmed via VLC, the browser's own hls.js still failed
  to *render* the now-present embedded CEA-608 track: hls.js added the
  in-band text track in `hidden` mode by default (cues populated correctly —
  confirmed real caption text and correct timing via a temporary
  `Hls.Events.CUES_PARSED`/`cuechange` debug overlay added to
  `views/watch.ejs`), and attempting to enable it via iOS Safari's native
  video CC menu flipped it to `disabled` rather than `showing`. This appears
  to be a Safari-specific rough edge with JS-added (`hls.js` in-band, as
  opposed to `<track src="...">`) text tracks, not a data problem.

**Fixes shipped:**

- `src/stream.js`: `STREAM_DECODE_MODE` now defaults to `sw` instead of
  `qsv` (software decode, still QSV-encoded) — required for embedded
  captions to survive transcoding at all. Trades CPU headroom per
  concurrent stream for working captions; set `STREAM_DECODE_MODE=qsv` to
  opt back into full hardware decode if captions aren't needed.
- `src/stream.js`: `WEBVTT_SIDECAR_MODE` now defaults to `off` instead of
  `on` — the sidecar is blocked by the ffmpeg bug above and was only adding
  a second, unsynchronized connection to the tuner per session for no
  benefit. Left in code as an opt-in fallback (`WEBVTT_SIDECAR_MODE=on`) in
  case the upstream bug is fixed or a future channel needs it.
- `src/stream.js`: fixed a resource-waste bug found along the way —
  `startWebVttSidecar()` was respawning ffmpeg roughly once per second for
  the entire session on any channel without CC data, because
  `ensureSession()` is invoked on every stream file request (~1/s given
  `hls_time 1`) and failure state wasn't sticky. `no_subtitle_stream` is now
  a sticky terminal state per session so it only tries once.
- `views/watch.ejs`: the embedded CEA-608 text track is now forced into
  `mode = 'showing'` as soon as hls.js adds it (in the `addtrack` handler),
  instead of relying on the browser's native CC control — works around the
  iOS Safari issue described above and means captions render by default
  with no user interaction required. Also: caption status messaging now
  distinguishes an embedded (`hls.js` in-band) track from a sidecar
  (`data-sidecar="webvtt"`, label `English CC`) track instead of lumping
  both into a generic "track attached" message; removed a dead
  `Hls.Events.SUBTITLE_TRACKS_UPDATED` listener that could never fire since
  this pipeline has no `#EXT-X-MEDIA:TYPE=SUBTITLES` renditions.
- `.env.example`, `docker-compose.yml`: defaults updated to match
  (`STREAM_DECODE_MODE=sw`, `WEBVTT_SIDECAR_MODE=off`) with comments
  explaining why.

**Not done / left for later:** Roku was explicitly out of scope for this
pass. It still defaults to HEVC (`roku/components/MainScene.brs`), and
`getCaptionConfig()` in `src/stream.js` has no `-a53cc` equivalent for
`hevc_qsv`, so Roku playback currently has no caption path at all
regardless of source content. `roku/components/SettingsScreen.xml` already
advises "Use H.264 if you need closed captions support" but this is
advisory text only — nothing in code enforces or defaults to it.

## 2026-08-28

### Added / changed: Roku codec preference setting (HEVC/H.264)

- Added a new Roku Settings option to choose preferred stream codec (`HEVC` or `H.264`) and persist it in registry (`hdhrweb` / `streamCodec`).
- Wired player startup and channel-surfing paths to honor the selected codec for `/stream/<channel>/<codec>/...` URLs.
- Updated the stream-start handshake task (`StreamStartTask`) to start/poll the selected codec path rather than always forcing HEVC.
- Added user-facing guidance in Settings that H.264 is the preferred path when testing closed captions.
- Bumped Roku `build_version` to 29 in `roku/manifest`.

### Added / changed: Caption detection in live stream diagnostics

- Added caption probe telemetry to stream session stats (`session.captions`) by running periodic ffprobe checks on the active HLS playlist in `src/stream.js`.
- Updated `/stream/:channel/:codec/:profile/stats` to return session data with caption detection fields populated.
- Added caption diagnostics lines to the Roku in-player stats overlay (`roku/components/PlayerScreen.brs`): detected/not detected, caption mode/strategy, and probe errors.
- Bumped Roku `build_version` to 30 in `roku/manifest`.
- Added side-by-side input vs output caption probe telemetry (`session.sourceCaptions` + `session.captions`) so diagnostics can show whether captions exist in raw tuner input but disappear after transcode.
- Updated Roku diagnostics overlay to show both `Input captions` and output `Captions` lines.
- Bumped Roku `build_version` to 31 in `roku/manifest`.

### Added / changed: Stream decode-mode toggle (QSV vs software decode)

- Added a server-side decode toggle in `src/stream.js`: `STREAM_DECODE_MODE=qsv|sw` (also accepts legacy alias `CAPTION_DECODE_MODE`).
- `qsv` keeps `mpeg2_qsv` decode (previous behavior); `sw` uses software `mpeg2video` decode while still keeping QSV encode (`h264_qsv` / `hevc_qsv`).
- Added `decodeMode` + active `videoDecoder` in session diagnostics for easier A/B validation.
- Wired `STREAM_DECODE_MODE` into `docker-compose.yml` environment with default `qsv`.

### Added / changed: WebVTT sidecar test implementation

- Added an experimental WebVTT sidecar extractor in `src/stream.js` (`WEBVTT_SIDECAR_MODE=on|off`, default `on`) that attempts to write `captions.vtt` per stream session from subtitle stream `0:s:0`.
- Extended stream file serving in `src/routes/watch.js` to allow `captions.vtt` with `text/vtt` content type.
- Updated browser watch page (`views/watch.ejs`) to attach a test captions track pointing to the sidecar `captions.vtt`.
- Added `session.webvtt` diagnostics metadata (state, reason, errors, active) to help determine whether the sidecar extraction is producing usable VTT data.
- Added a `WebVTT sidecar` status line in Roku diagnostics overlay and bumped Roku `build_version` to 32.
- Added placeholder VTT creation (`WEBVTT` header) at session start so browser track plumbing can be verified independently from cue extraction.
- Added `SOURCE_CAPTION_PROBE` toggle (default `off`) to keep diagnostics less noisy unless raw-input probing is explicitly enabled.
- Cleaned browser caption status messaging to distinguish track attachment from actual cue availability.
- Reduced Roku diagnostics noise when input probe is disabled and bumped Roku `build_version` to 33.
- Stabilized sidecar extraction by streaming WebVTT cues from ffmpeg stdout into the session `captions.vtt` file, avoiding overwrite prompts/races from direct file output.

### Added / changed: Closed captioning Phase 1 (embedded, hardware path preserved)

- Added a Phase 1 caption mode in `src/stream.js` to explicitly request embedded A/53 caption passthrough on the browser `h264_qsv` path (`-a53cc 1`) while keeping QSV decode/encode active.
- Added stream-session diagnostics fields (`videoDecoder`, `captionMode`, `captionActive`, `captionStrategy`) so `/stream/:channel/:codec/:profile/stats` can confirm caption strategy and hardware codec path in use.
- Added startup logging that includes caption strategy per stream session.

### Added / changed: Roku UX improvements (filter legend, channel surfing, retry, settings check)

- Added a persistent on-screen legend (`LEFT/RIGHT: Filter  *: Options`) to the guide detail bar in `roku/components/GuideScreen.xml` so the filter and settings shortcuts are discoverable. (Uses ASCII text only — Roku system fonts lack the arrow/gear glyphs.)
- Added channel surfing during playback: `rewind` / `forward` step to the previous/next channel (wrapping) using the guide's visible channel order, in `roku/components/PlayerScreen.brs` and `roku/components/GuideScreen.brs` (passes the channel list via `MainScene`).
- Added inline retry: when a stream fails or ends, `OK` re-runs the tuning handshake instead of forcing the user back to the guide (`roku/components/PlayerScreen.brs`).
- Added a post-save connectivity check in Settings: the URL is probed in `roku/components/UrlCheckTask.brs` and the status line reports `Saved — connected` or `Saved — can't reach server`.
- Bumped Roku `build_version` to 26 in `roku/manifest`.

### Added / changed: Persist guide filter preference

- The All/Favorites guide filter now persists across app launches via the Roku registry (`hdhrweb` / `guideFilter`) in `roku/components/GuideScreen.brs`, so returning to the app restores the filter the user last selected.
- Bumped Roku `build_version` to 28 in `roku/manifest`.

### Added / changed: Roku reliability and refresh efficiency (section 4)

- Added incremental guide refresh patching in `roku/components/GuideScreen.brs` so periodic refreshes update changed rows instead of rebuilding the full `ContentNode` tree each time.
- Added bounded `/ready` polling backoff and repeated-network-failure handling in `roku/components/StreamStartTask.brs`.
- Added structured stream-start failure reasons (`tuner_busy`, `network`, `timeout`, `access_denied`, `signal`) in stream-start task results.
- Improved Roku startup failure messaging in `roku/components/PlayerScreen.brs` with reason-specific user-facing errors.

### Added / changed: Guide and web UI responsiveness (section 3)

- Added incremental guide rendering on web: `GET /guide` now serves a fast shell and lazily hydrates guide content from `GET /guide/fragment`.
- Added partial template reuse for guide content with `views/_guide_accordion.ejs`.
- Added progressive channel list loading for large lineups using `GET /channels/rows` and `views/_channel_rows.ejs`.
- Improved browser watch-page startup feedback with clearer retry/timeout/tuner-busy states in `views/watch.ejs`.
- Added TV Guide grid filtering controls for **Favorites** and **Show Hidden**, with hidden channels excluded by default on `/guide/grid`.
- Extended guide/lineup merge data to include hidden-channel state so web guide filters can distinguish hidden channels reliably.

### Added / changed: Node/Express performance and observability

- Added response compression and static asset caching behavior in server middleware.
- Added upstream connection reuse and timeout hardening for HDHomeRun/cloud calls.
- Added request timing and stream startup observability improvements.
- Fixed runtime compatibility by avoiding a hard Undici runtime dependency path in container execution.

### Added / changed: Streaming path and Roku diagnostics baseline

- Improved stream startup behavior and low-latency-oriented streaming configuration.
- Added/expanded Roku playback diagnostics overlay and stream stats visibility for troubleshooting.
- Preserved browser/Roku codec split and stream handshake semantics across clients.
