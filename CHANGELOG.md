# Changelog

All notable changes to this project are documented in this file.

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
