# hdhomerun-web

A mobile-responsive web UI for managing your [HDHomeRun](https://www.silicondust.com/) device, meant as a friendlier alternative to the device's built-in web interface. It talks to your HDHomeRun over its local HTTP API and runs as a small self-hosted Docker container.

## Features

- **System Menu** (`/`) — device info at a glance: friendly name, model, firmware version, device ID, tuner count. Includes a link to the device's own system log.
- **Channel Lineup** (`/channels`) — full channel list including hidden and unsubscribed channels, with per-channel signal strength/quality, codec info, and direct stream URL. Toggle filters for Favorites, HD, and Show Hidden.
- **Detect Channels** (`/scan`) — start or abort a channel scan, with live progress.
- **System Status** (`/status`) — per-tuner status: currently tuned channel, signal strength/quality meters, and network rate (Mbit/s), auto-refreshing.
- **Light/dark mode** toggle in the navbar, remembered across visits.

## Screenshots

| Channel Lineup (dark) | System Status (light) |
|---|---|
| ![Channel Lineup, dark mode](docs/screenshot-dark.png) | ![System Status, light mode](docs/screenshot-light.png) |

## Stack

- Node.js + Express, server-rendered with EJS (no SPA build step)
- [htmx](https://htmx.org/) for the small bits of live-updating UI (scan progress, tuner status)
- [Bootstrap 5](https://getbootstrap.com/) for styling, loaded via CDN, with a light/dark theme toggle
- Talks directly to your HDHomeRun's HTTP API (`discover.json`, `lineup.json`, `lineup.post`, `lineup_status.json`, `status.json`)

## Running

```bash
docker compose up -d --build
```

The app listens on port `8080` by default — visit `http://<docker-host>:8080`.

### Configuration

Configuration lives in a `.env` file (read automatically by `docker compose`). Copy the example and edit it:

```bash
cp .env.example .env
```

| Variable          | Default          | Notes                                                                 |
|-------------------|------------------|------------------------------------------------------------------------|
| `HDHOMERUN_HOST`  | —                | **Use your device's LAN IP, not its `.local` mDNS name.** Containers on the default Docker bridge network can't resolve mDNS names. |
| `HDHOMERUN_PORT`  | `80`             | HDHomeRun's HTTP port.                                                |
| `PORT`            | `8080`           | Port the web app listens on inside the container.                    |

You can find your device's current IP via its own web UI, your router's DHCP client list, or `avahi-resolve -n hdhomerun.local` on a machine with mDNS support. A DHCP reservation for the device is recommended so the IP doesn't change.

## Local development (without Docker)

```bash
npm install
HDHOMERUN_HOST=<device-ip> npm start
```

## Project layout

```
server.js              Express app entrypoint
src/hdhomerun.js        Client for the HDHomeRun HTTP API
src/routes/            Route handlers for each page
views/                 EJS templates (server-rendered)
public/                Static assets (CSS, favicon)
```
