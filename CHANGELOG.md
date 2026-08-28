# Changelog

All notable changes to this project are documented in this file.

## 2026-08-28

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

### Added / changed: Node/Express performance and observability

- Added response compression and static asset caching behavior in server middleware.
- Added upstream connection reuse and timeout hardening for HDHomeRun/cloud calls.
- Added request timing and stream startup observability improvements.
- Fixed runtime compatibility by avoiding a hard Undici runtime dependency path in container execution.

### Added / changed: Streaming path and Roku diagnostics baseline

- Improved stream startup behavior and low-latency-oriented streaming configuration.
- Added/expanded Roku playback diagnostics overlay and stream stats visibility for troubleshooting.
- Preserved browser/Roku codec split and stream handshake semantics across clients.
