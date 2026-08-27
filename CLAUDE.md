# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A mobile-responsive web UI for an HDHomeRun network tuner — a friendlier alternative to the device's own built-in web interface. Server-rendered Node/Express app, no SPA build step, packaged as a Docker container. See README.md for the full feature list and end-user setup instructions.

**There are two clients against one server.** The Node/Express app in the repo root serves both the browser UI (EJS/htmx/Bootstrap) and a Roku app (`roku/`, BrightScript/SceneGraph). They share the streaming backend and the `/api/*` JSON, but nothing else — Roku has no browser, so none of the web frontend is reusable there. When changing `/api/guide` or the `/stream/*` handshake, check `roku/components/` for consumers.

## Commands

```bash
npm install              # install dependencies
npm start                # run locally (node server.js)
docker compose up -d --build   # build and run the container
```

There is no test suite, lint config, or build step in this repo.

### Local dev without Docker

```bash
HDHOMERUN_HOST=<device-ip> npm start
```

Config is normally supplied via `.env` (read automatically by `docker compose`), copied from `.env.example`. Key variables: `HDHOMERUN_HOST`, `HDHOMERUN_PORT` (default 80), `PORT` (app's own listen port, default 8080).

**Important:** `hdhomerun.local` (mDNS) does not resolve from inside a Docker container on the default bridge network — always use the device's LAN IP for `HDHOMERUN_HOST`.

## Architecture

Express + EJS, server-rendered, with [htmx](https://htmx.org/) for partial-page updates (no client-side framework) and Bootstrap 5 (CDN) for styling, including a light/dark toggle.

**Two upstream APIs, one API-client module each:**
- `src/hdhomerun.js` — talks directly to the local HDHomeRun device's HTTP API (`discover.json`, `lineup.json`, `lineup.post`, `lineup_status.json`, `status.json`). Exports one function per device operation; all requests go through a shared `request()` helper with a 5s timeout.
- `src/guide.js` — talks to Silicondust's *cloud* Guide API (`api.hdhomerun.com/api/guide`), authenticated with the device's own `DeviceAuth` token. That token rotates every 16–24h, so `getGuide()` fetches it fresh from `hdhomerun.getDeviceInfo()` on every call rather than caching it — don't "optimize" this into a cached value.

Some of the device endpoints used here are **not in Silicondust's official HTTP API docs** and were reverse-engineered from the device's own web UI JavaScript (view-source on `lineup.html`, `system.html`, etc. served by the device itself):
- `lineup.json` supports `?show=found` (device UI default) and `?show=all` (includes hidden/disabled channels); bare `lineup.json` with no query returns a narrower "favorites-relevant" set — this app always uses `?show=all` and filters client-side.
- `lineup.post?favorite=<mode><GuideNumber>` sets a channel's state: `+` favorite, `-` normal, `x` hidden. A channel can only be in one of these three states at a time (mirrors the device's own tri-state star icon).
- `lineup.post?scan=start&source=<name>` accepts an optional `source` param (e.g. Antenna/Cable) when the device supports multiple tuning sources (see `SourceList` in `lineup_status.json`).
- `/log.html` and `/tuners.html?page=tunerN` are plain server-rendered pages on the device itself (not JSON APIs) — currently only linked out to, not scraped.

**Routing:** each feature area is a separate router in `src/routes/` (`index`, `channels`, `scan`, `status`, `guide`), all mounted flat in `server.js` — routes aren't namespaced by prefix, so route paths live directly in each router file.

**Views:** `views/_header.ejs` / `_footer.ejs` are the shared layout shell (included manually in every top-level view — no layout engine). Partials prefixed with `_` (`_channel_row.ejs`, `_scan_status.ejs`, `_tuner_status.ejs`) are reused both for full-page renders and as htmx swap targets returned directly from POST/GET routes (e.g. `POST /channels/flag` re-renders and returns just `_channel_row.ejs` for the one changed row).

**Gotcha already hit once:** query-string values containing a literal `+` must be percent-encoded (`%2B`) in `hx-post`/`href` URLs — an unencoded `+` decodes to a space by the time it reaches `req.query`, silently corrupting values like the favorite mode. See `views/_channel_row.ejs` for the fixed pattern (`encodeURIComponent(...)` around every dynamic query value, not just the "obviously unsafe" ones).

## Roku client (`roku/`)

BrightScript + SceneGraph, sideloaded via Developer Mode (Roku killed private
channels in 2022, so there's no publish-free distribution path). `roku/README.md`
covers deployment; `roku/deploy.sh` zips and uploads.

Things that will bite:

- **All network I/O must happen inside `Task` nodes** (`GuideTask`,
  `StreamStartTask`), never the render thread. Blocking the render thread is the
  usual cause of an app that hangs on launch.
- **The zip's `manifest` must be at the archive root.** Zipping the `roku/` folder
  itself silently produces a package Roku rejects; `deploy.sh` asserts this.
- **Re-uploading an identical build is refused** — bump `build_version` in
  `roku/manifest`.
- **The guide is a custom `RowList` of `GuideRow` nodes, not a `TimeGrid`.**
  Roku's `TimeGrid` component was dropped in favor of hand-rolled rows because
  its `PLAYSTART`/`PLAYDURATION` semantics are ambiguous in Roku's own docs. All
  epoch-seconds → wall-clock conversion now lives in `buildGuideContent()` and
  `formatGuideTime()` in `roku/components/GuideScreen.brs` — if the guide
  renders with wrong/absent program blocks or times, change it there first.
  `GuideRow.brs`/`GuideRow.xml` render one channel's logo, name, and three
  half-hour program titles per row; `GuideScreen.brs` rebuilds the whole
  `ContentNode` tree on every refresh rather than patching individual rows.
- **Don't collapse the playback handshake** (POST `/start` → poll `/ready` →
  then set the Video node's URL). The `.m3u8` does not exist until ffmpeg spins
  up; pointing the player at it early fails.
- **Server error strings are not screen-safe.** `/stream/<ch>/ready` returns an
  ffmpeg stderr tail up to 4000 chars. `PlayerScreen.brs` logs it in full via
  `print` (visible on `telnet <roku-ip> 8085`) and shows a truncated line on TV.
- **Transcoding target is HEVC, not MPEG-2 passthrough.** `src/stream.js` uses
  QSV hardware decode (`mpeg2_qsv`) and HEVC encode (`hevc_qsv`, global quality
  21) because Roku's MPEG-2 support is inconsistent across the device fleet and
  raw MPEG-TS from the tuner isn't a supported Roku stream format at all. This
  is shared by both clients (`src/stream.js` has no Roku-specific branch) — if
  you change codec/quality here, check playback on both the browser player and
  `PlayerScreen.brs`.

## Screenshots

`docs/screenshot-*.png` are referenced by README.md. When UI changes are significant enough to warrant updating them, they were captured via headless Chrome + the DevTools Protocol (not manual review) — see git log around "Add light/dark theme toggle, screenshots" for the approach if this needs to be redone.
