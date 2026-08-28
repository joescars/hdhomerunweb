Reviewed. Here are the highest-impact recommendations for this project, prioritized for **faster stream start, lower buffering, and better UX**.

## 1) Streaming path (highest impact)

1. **Tune HLS for low-latency startup**
   - Reduce initial segment duration and playlist depth for live mode.
   - Use shorter GOP/keyframe interval aligned to segment length.
   - Outcome: faster first frame and channel changes.

2. **Pre-warm transcode sessions**
   - On guide/watch click, trigger stream start immediately (you already do handshake logic; keep it).
   - Optionally keep one “last channel” session warm for a brief window.
   - Outcome: reduces wait after user action.

3. **Adaptive quality profiles**
   - Add 2–3 ffmpeg profiles (e.g., low/medium/high bitrate) for browser HLS.
   - Select profile based on client/network hints.
   - Outcome: fewer rebuffers on weak Wi‑Fi.

4. **Session lifecycle hardening**
   - Keep current auto-release, but add explicit heartbeat and stale cleanup metrics.
   - Outcome: fewer orphan sessions, better tuner availability.

## 2) Node/Express server performance

1. **Add HTTP caching headers**
   - Strong cache for `public/*` assets (CSS, icons).
   - ETag/Last-Modified on guide endpoints where safe.
   - Outcome: quicker repeat loads, lower server work.

2. **Enable compression for HTML/JSON**
   - Add gzip/brotli middleware for non-video responses.
   - Outcome: faster page and API responses on LAN/WAN.

3. **Connection reuse + timeouts**
   - Ensure keep-alive for upstream HTTP requests to HDHomeRun/cloud guide.
   - Keep strict request timeouts (you already have 5s in API helper).
   - Outcome: lower latency and better resilience.

4. **Basic observability**
   - Add request timing + stream startup timing logs.
   - Outcome: you can optimize with data, not guesswork.

## 3) Guide and UI responsiveness

1. **Cache guide data briefly (server-side)**
   - Cache per-channel guide payload for short TTL (e.g., 30–60s), but keep fresh `DeviceAuth` fetch behavior.
   - Outcome: faster guide rendering, fewer cloud calls.

2. **Incremental rendering with htmx**
   - Render shell first, hydrate rows/grid chunks after.
   - Outcome: perceived speed improves significantly.

3. **Virtualize large channel lists (web)**
   - For heavy lineups, render visible rows first, lazy-load rest.
   - Outcome: smoother scrolling and quicker first paint.

4. **User feedback states**
   - Add explicit “Starting stream… / Retrying… / Tuner busy” states in watch and Roku flows.
   - Outcome: better UX during unavoidable waits.

## 4) Roku-specific improvements

1. **Keep Task-based I/O only** (already correct)
   - Continue enforcing no network calls on render thread.

2. **Guide refresh diffing**
   - Instead of rebuilding full `ContentNode` tree every refresh, patch changed rows.
   - Outcome: less UI jank, lower memory churn.

3. **Playback retry strategy**
   - Add bounded retry/backoff for `/ready` polling and clearer on-screen failure reasons.
   - Outcome: fewer dead-end failures for users.

## 5) Docker/runtime tuning

1. **Pin CPU/memory guidance in docs**
   - Recommend minimum host specs and iGPU validation steps.
   - Outcome: fewer performance support issues.

2. **Health/readiness checks**
   - Add container health endpoint and check ffmpeg availability/device access at startup.
   - Outcome: faster troubleshooting.

3. **Optional host networking note**
   - For some setups, host networking can reduce local latency/mDNS issues (document as optional).
   - Outcome: simpler network path in specific environments.

## 6) Quick wins you can do first (1–2 days)

- Add compression + static caching headers.
- Add startup timing logs (`click/start` → `first playable`).
- Tune ffmpeg GOP/segment settings for faster startup.
- Add watch-page loading/error states.
- Add short-lived guide cache.

---

If you want, I can next provide a **concrete implementation plan** with exact file-level changes in:
- `stream.js`
- `watch.js`
- `watch.ejs`
- `server.js`
- `guide.js`
- Roku `GuideScreen.brs` / `PlayerScreen.brs`