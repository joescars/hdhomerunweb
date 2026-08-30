// Client for the local HDHomeRun RECORD engine - a separate process from the
// tuner device itself, with its own local API and storage. Only used for the
// "record what I'm watching" action; the engine's own periodic guide poll
// and recording pipeline handle everything else.
const hdhr = require('./hdhomerun');

const RECORD_HOST = process.env.RECORD_ENGINE_HOST || '';
const RECORD_PORT = process.env.RECORD_ENGINE_PORT || 37899;
const RECORD_BASE = RECORD_HOST ? `http://${RECORD_HOST}:${RECORD_PORT}` : null;
const API_BASE = 'https://api.hdhomerun.com';
const TIMEOUT_MS = 8000;

function isConfigured() {
  return !!RECORD_BASE;
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

// Schedules a single-airing ("DateTimeOnly") recording rule for the program
// currently airing on `channel`, using its own SeriesID/StartTime from the
// guide data - this is how Silicondust's own apps implement "record this
// airing" (there's no separate "record now" verb in their API). The local
// record engine polls for rule changes periodically; poking it via
// recording_events.post makes it pick this rule up immediately instead of
// waiting for that poll.
async function recordCurrentAiring({ seriesId, channel, startTime }) {
  if (!isConfigured()) {
    throw new Error('RECORD_ENGINE_HOST is not configured');
  }

  const device = await hdhr.getDeviceInfo();
  if (!device || !device.DeviceAuth) {
    throw new Error('Device did not return a DeviceAuth token');
  }

  const params = new URLSearchParams({
    DeviceAuth: device.DeviceAuth,
    Cmd: 'add',
    SeriesID: seriesId,
    DateTimeOnly: String(startTime),
    ChannelOnly: channel,
  });

  // The API accepts GET for read-only Cmd=list calls but rejects Cmd=add
  // with a bare 400 unless sent as POST (confirmed empirically - the docs
  // don't specify a method).
  const res = await fetchWithTimeout(`${API_BASE}/api/recording_rules?${params.toString()}`, { method: 'POST' });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Recording rule request failed: ${res.status} ${res.statusText} ${text}`);
  }

  await fetchWithTimeout(`${RECORD_BASE}/recording_events.post?sync`, { method: 'POST' }).catch(() => {});

  return text ? JSON.parse(text) : null;
}

module.exports = { isConfigured, recordCurrentAiring };
