# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A mobile-responsive web UI for an HDHomeRun network tuner — a friendlier alternative to the device's own built-in web interface. Server-rendered Node/Express app, no SPA build step, packaged as a Docker container. See README.md for the full feature list and end-user setup instructions.

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

**Two upstream APIs, two separate clients:**
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

## Screenshots

`docs/screenshot-*.png` are referenced by README.md. When UI changes are significant enough to warrant updating them, they were captured via headless Chrome + the DevTools Protocol (not manual review) — see git log around "Add light/dark theme toggle, screenshots" for the approach if this needs to be redone.
