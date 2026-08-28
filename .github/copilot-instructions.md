# Copilot instructions for `hdhomerun-web`

## Build, test, and lint commands

This repository has **no test suite, lint config, or build step**.

| Task | Command | Notes |
|---|---|---|
| Install dependencies | `npm install` | Required for local Node/Express runs |
| Run app locally | `HDHOMERUN_HOST=<device-ip> npm start` | Starts `node server.js` |
| Run with Docker | `docker compose up -d --build` | Main deployment/development path |
| Run a single test | N/A | No test runner is configured |
| Run lint | N/A | No lint tooling is configured |

## High-level architecture

- **One Express server, two clients:** the root Node app serves both the browser UI and the Roku client backend (`/api/*` + `/stream/*`), but browser and Roku frontends are separate implementations.
- **Server-rendered web app:** `server.js` mounts feature routers from `src/routes/*.js` directly at root paths (no route prefix namespace), renders EJS views from `views/`, and serves static assets from `public/`.
- **Two upstream API clients with clear boundaries:**
  - `src/hdhomerun.js` talks to the device on LAN (`discover.json`, `lineup.json`, `lineup.post`, `lineup_status.json`, `status.json`) through a shared timeout-wrapped `request()` helper.
  - `src/guide.js` talks to SiliconDust cloud guide API and fetches `DeviceAuth` fresh via `hdhomerun.getDeviceInfo()` on each guide request.
- **Streaming subsystem:** `src/stream.js` manages ffmpeg HLS sessions keyed by `channel:codec:profile`, with idle cleanup, startup readiness checks, and metrics. `src/routes/watch.js` exposes `/stream/*` start/ready/heartbeat/stats/file endpoints and browser watch pages.
- **Guide/channel/status/scan flow:** feature routes call `src/hdhomerun.js` and `src/guide.js`, render full pages plus htmx partials, and use `src/cache.js` for short in-memory guide caching.

## Key conventions in this codebase

- **Do not cache `DeviceAuth` yourself:** guide token rotation is handled by fetching device info each guide request (`src/guide.js`).
- **Flat route mounting:** routers are mounted directly in `server.js`; keep path definitions in each route file accurate because there is no parent prefix.
- **HTMX partial reuse pattern:** underscore-prefixed templates (`views/_*.ejs`) are rendered both inside full pages and as direct swap responses from POST/fragment routes.
- **Always URL-encode dynamic query values in channel actions:** especially favorite mode values containing `+` (`views/_channel_row.ejs` uses `encodeURIComponent(...)` for both `guide` and `mode`).
- **Preserve stream handshake semantics:** clients must `POST /start` then poll `/ready` before requesting `.m3u8`; do not collapse this flow.
- **Codec split is client-specific and intentional:** browser requests H.264 (`/stream/:channel/h264/...`), Roku requests HEVC (`/stream/:channel/hevc/...`).
- **When changing `/api/guide` or `/stream/*`, check Roku consumers:** especially `roku/components/GuideTask.*`, `roku/components/StreamStartTask.*`, and `roku/components/PlayerScreen.*`.
