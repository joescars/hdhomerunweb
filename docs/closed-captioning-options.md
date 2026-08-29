# Closed Captioning Support Options

This document outlines practical ways to add closed captioning (CC) to this
project, based on the current streaming architecture (Node/Express + ffmpeg,
browser via hls.js, Roku via SceneGraph `Video`).

## Current state in this repo

- `src/stream.js` transcodes live MPEG-TS input to HLS with only video + audio
  mapped (`-map 0:v:0 -map 0:a:0`), so no explicit subtitle track is emitted.
- `src/routes/watch.js` only serves `stream.m3u8` and `segmentN.ts`, not
  subtitle playlists or `.vtt` files.
- `views/watch.ejs` uses hls.js for playback but does not currently expose any
  explicit caption pipeline/track setup.
- Roku always requests HEVC (`/stream/:channel/hevc/...`) via
  `roku/components/StreamStartTask.brs`.

Implication: CC is not intentionally preserved or surfaced today.

## Important technical constraint

For OTA ATSC channels, captions are usually CEA-608/708 data carried inside
the video bitstream/user data (not always as a standalone subtitle stream).

That means subtitle support can fail even when audio/video works, depending on
how decode/encode steps handle caption metadata.

## Option A: Preserve embedded CEA captions in HLS video (best first step)

Goal: keep captions embedded in the transcoded stream so players can render
them natively.

What to change:

1. Adjust ffmpeg pipeline in `src/stream.js` to preserve caption metadata in
   the output video where supported.
2. Verify browser behavior with hls.js text tracks and Roku behavior with
   system caption settings enabled.

Pros:

- Smallest API/UI change.
- Keeps live workflow simple (single playlist + segments).
- Most natural for Roku live TV behavior.

Cons / risks:

- Caption preservation can be encoder/decoder-path dependent (especially QSV).
- HEVC caption behavior is less predictable than H.264 in some clients.

When to pick this:

- First implementation attempt. It is the least invasive path.

## Option B: Add explicit HLS subtitle renditions (WebVTT)

Goal: generate a dedicated subtitle track and reference it from HLS manifests.

What to change:

1. Update streaming pipeline to extract captions and produce subtitle output
   (likely `.vtt` and/or subtitle playlists).
2. Expand file serving in `src/routes/watch.js` (`FILE_RE`, content type
   handling) to allow subtitle assets.
3. Ensure `views/watch.ejs`/hls.js surfaces the subtitle track correctly.

Pros:

- Explicit subtitle tracks are easier to debug and expose in UI.
- Better long-term flexibility (multi-language tracks, custom controls).

Cons:

- Highest implementation complexity for live rolling HLS.
- Caption extraction from ATSC 608/708 may require additional tooling or a
  more complex ffmpeg setup.
- Extra manifest/file serving complexity.

When to pick this:

- If embedded caption pass-through is unreliable across clients.

## Option C: Burn captions into video (fallback only)

Goal: make captions always visible by rendering text directly into frames.

Pros:

- Works even if players cannot parse caption metadata.

Cons:

- No user toggle (always on).
- Not accessibility-friendly for all users (size/style control lost).
- Harder to support multiple languages.

When to pick this:

- Last resort for specific channels/devices where no metadata path is stable.

## Option D: Hybrid strategy (recommended long-term)

- Roku: prioritize embedded captions in stream (closest to TV-native behavior).
- Web: prefer explicit text tracks where practical, with embedded fallback.

This balances reliability and UX while allowing incremental rollout.

## Recommended phased plan

### Phase 1 (fastest validation)

1. Attempt embedded caption preservation in `src/stream.js`.
2. Test Web (Chrome/Safari) and Roku with captions enabled in device settings.
3. Log whether caption tracks appear and render.

Success criteria:

- Browser shows a CC/subtitle track during live playback.
- Roku renders captions when Roku accessibility captions are enabled.

### Phase 2 (if Phase 1 is inconsistent)

1. Add explicit subtitle rendition support (WebVTT path).
2. Extend route file whitelist/content types in `src/routes/watch.js`.
3. Add minimal watch-page UI hints if needed.

### Phase 3 (polish)

- Per-client strategy (e.g., keep Roku path simple; improve web controls).
- Add diagnostics endpoint fields indicating caption mode per session.

## Where code changes will likely land

- `src/stream.js`: ffmpeg mapping/flags and output assets.
- `src/routes/watch.js`: subtitle file serving and content types.
- `views/watch.ejs`: web playback/caption track UX.
- `roku/components/PlayerScreen.*`: usually minimal if embedded captions work,
  but may need UX messaging/testing hooks.

## Validation checklist

1. Confirm source captions exist on representative channels (news + primetime).
2. Verify captions after transcode for both codecs (`h264`, `hevc`).
3. Test browser matrix: Chrome, Safari, Firefox (where supported).
4. Test Roku with captions off/on in Roku system accessibility settings.
5. Measure startup latency impact and CPU/GPU load after caption changes.

## Practical recommendation

Start with **Option A (embedded caption preservation)**, because it is the
lowest-risk architecture change and best aligned with current live pipeline.
If reliability is uneven (especially across HEVC/QSV paths), add **Option B**
for web as a targeted follow-up.
