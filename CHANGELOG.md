# Changelog

All notable changes to this project are documented in this file.

## 2026-08-29

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
