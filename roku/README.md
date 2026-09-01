---
title: HDHomeRun Web Roku client
description: Deploy and configure the Roku client for an HDHomeRun Web server
---

A Roku app for the `hdhomerun-web` server: browse a now/next channel guide and
watch live TV on your TV. It's a thin client: the server does all the tuning
and transcoding, and the Roku just plays the resulting HLS stream.

> **This is meant to be sideloaded, not published.** Roku discontinued private
> (non-certified) channels in February 2022. The replacement, Beta Channels,
> expires after 120 days and caps at 20 installs — not useful for a personal
> app. Sideloading via Developer Mode needs no Roku review or approval, and is
> what these instructions cover.

## Requirements

- The `hdhomerun-web` server running and reachable from your Roku (same LAN)
- A Roku device you can put into Developer Mode
- `zip` and `curl` on the machine you deploy from

## 1. Enable Developer Mode on the Roku

On the Roku remote, from the home screen, press:

```
Home ×3, Up ×2, Right, Left, Right, Left, Right
```

A Developer Settings screen appears. Choose **Enable developer mode**, accept the
license, and set a password. **Write this password down** — it isn't recoverable
and it is *not* your Roku account password. The device reboots.

After it reboots, note the IP shown on that screen (also in
*Settings → Network → About*).

## 2. Point the app at your server

Set the server URL in `roku/.env`:

```bash
HDHOMERUN_WEB_URL=http://192.168.1.100:8080
```

`deploy.sh` embeds this URL into the packaged app. You can also change it at
runtime from the app (**Options / `*`** on the guide screen, then Settings).
The value saved to the Roku registry takes precedence over the packaged URL.

## 3. Deploy

```bash
cd roku
cp .env.example .env      # then edit it
./deploy.sh
```

`.env` holds your device details:

```bash
ROKU_IP=192.168.1.50
ROKU_DEV_PASSWORD=your-developer-mode-password
HDHOMERUN_WEB_URL=http://192.168.1.100:8080
```

Or pass them inline:

```bash
ROKU_IP=192.168.1.50 ROKU_DEV_PASSWORD=hunter2 ./deploy.sh
```

The app then appears on the Roku home screen as **LunaTV**.

To build the zip without uploading (e.g. to install by hand through the web UI
at `http://<roku-ip>`, user `rokudev`):

```bash
./deploy.sh --package-only
```

## 4. Debugging

BrightScript errors and any `print` output go to the debug console:

```bash
telnet <roku-ip> 8085
```

Worth knowing: playback and tuning failures are deliberately logged in full
there, while the on-screen message is kept short — the server's error field can
carry several KB of ffmpeg output that would be unreadable on a TV.

While watching live TV, press **Up** on the remote to toggle a diagnostics
overlay. It shows stream codec/profile/target bitrate plus live ffmpeg metrics
(fps/speed/bitrate) and tuner signal telemetry when available.

On the guide, press **Play** to open DVR recordings. Press **OK** to play a
recording, **Options** to delete a completed recording or stop an active one,
and **Back** to return. Active entries are labeled `RECORDING NOW` and the list
refreshes every 15 seconds. Stopping discards the partial recording. While
watching live TV, press **Down** to schedule the current airing. DVR requires
the server's `RECORD_ENGINE_HOST` configuration.

## Things to know

- **Only one sideloaded app can exist on a Roku at a time.** Installing this
  replaces any other dev channel on the device.
- **Re-uploading an identical build is rejected** with "Identical to previous
  version". Bump `build_version` in [`manifest`](manifest) to force it.
- **Sideloaded apps and Developer Mode are widely reported to survive reboots,
  but Roku doesn't actually document that guarantee.** Some users report needing
  to re-sideload after firmware updates. If the app disappears, re-running
  `./deploy.sh` takes a few seconds.
- **Tuner limits still apply.** Each channel you open starts an ffmpeg session on
  the server and occupies a physical tuner. The server releases it ~20 seconds
  after you stop watching, so rapid channel-flipping can briefly hold several.

## How it works

```
Roku app                     hdhomerun-web server              HDHomeRun
   |                                  |                             |
   |-- GET /api/guide --------------->|-- cloud Guide API           |
   |<-- channels + now/next ----------|                             |
   |                                  |                             |
   |-- POST /stream/3.1/hevc/start -->|-- spawn ffmpeg (QSV) ------->| tune
   |-- GET  /stream/3.1/hevc/ready -->|   (poll every 500ms)         |
   |<-- {"ready":true} ---------------|                             |
   |                                  |                             |
   |-- GET /stream/3.1/hevc/          |   MPEG2/AC3 -> HEVC/AAC HLS  |
   |       stream.m3u8 -------------->|                             |
   |<== HLS segments =================|<============================|
```

The start/poll handshake exists because the HLS playlist doesn't exist until
ffmpeg has spun up (typically 2–4s). Pointing the Video node at the `.m3u8`
before then fails. Don't collapse those steps.

Transcoding isn't optional here: Roku's MPEG-2 support varies across the device
fleet, and raw MPEG-TS straight from the tuner isn't a supported Roku stream
format regardless.

## Layout

```
manifest                     app metadata, icons, splash
source/main.brs              entry point
components/
  MainScene.*                screen stack, registry, server URL
  GuideScreen.*              compact multi-column channel guide
  GuideRow.*                 custom guide row renderer
  PlayerScreen.*             Video node + tuning overlay
  SettingsScreen.*           server URL editor
  RecordingsScreen.*         DVR list, active-state refresh, and actions
  RecordingPlayerScreen.*    recorded HLS playback
  GuideTask.*                fetches /api/guide off the render thread
  RecordingsTask.*           fetches, deletes, and stops recordings off the render thread
  RecordingStreamTask.*      starts/polls recorded HLS off the render thread
  StreamStartTask.*          start/poll handshake off the render thread
  Net.brs                    shared roUrlTransfer helpers
```

All network I/O lives in Task nodes — SceneGraph forbids blocking the render
thread, and doing so is the usual cause of an app that hangs on launch.
