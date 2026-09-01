# AGENTS.md

## Commands

- Install/run locally: `npm install && HDHOMERUN_HOST=<device-ip> npm start`.
- Run the production-like stack: `docker compose up -d --build`.
- There are no automated tests, lint, typecheck, formatter, or build scripts; verify targeted changes manually. Live playback additionally needs QSV-capable `ffmpeg` (the container provides Jellyfin ffmpeg and maps `/dev/dri`).
- Docker reads `.env`; use LAN IPs for `HDHOMERUN_HOST` and `RECORD_ENGINE_HOST`, never `localhost` or `hdhomerun.local` from inside the container.

## Architecture

- `server.js` is the Express entrypoint. Browser pages are server-rendered EJS/htmx; the separate BrightScript/SceneGraph Roku client is in `roku/`.
- Admin routers are mounted under `/admin`; route paths inside `src/routes/{index,channels,scan,status}.js` intentionally omit that prefix. Client guide/watch/recordings and `/api/*` stay at root.
- Browser and Roku share `/api/guide` and `/stream/*`; update `roku/components/` when changing either API or the stream handshake. Keep `POST /start` → poll `/ready` → fetch `.m3u8`; the playlist does not exist immediately.
- Fetch a fresh `DeviceAuth` in `src/guide.js` for each guide request; it rotates and must not be cached.
- Stream sessions are keyed by channel, codec, and quality profile. Browser playback must use H.264; HEVC/direct are Roku-only options.

## UI and device API gotchas

- Top-level client views use `_client_header.ejs`; admin views use `_header.ejs`; both close through `_footer.ejs`. `_` view files can also be htmx response fragments.
- In htmx URLs, percent-encode every dynamic query value. In particular, unencoded `+` becomes a space and breaks channel favorite updates.
- Always request device `lineup.json` via the existing `getLineup()` path (`?show=all`); the bare endpoint omits channels. Favorite modes are mutually exclusive: `+`, `-`, or `x`.
- The optional RECORD engine is external. Recording the current airing requires a POST rule add followed by `POST recording_events.post?sync`; do not replace the rule-add POST with GET.

## Roku

- All network I/O belongs in SceneGraph `Task` nodes, never the render thread.
- Use `roku/deploy.sh` to package/sideload; it places `manifest` at zip root. Bump `roku/manifest` `build_version` before uploading an otherwise identical build.
