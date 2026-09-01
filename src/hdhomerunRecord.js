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

async function stopRecording(recording) {
  if (!recording || !recording.SeriesID || !recording.ChannelNumber || !recording.StartTime || !isConfigured()) {
    throw new Error('Recording not found');
  }

  const device = await hdhr.getDeviceInfo();
  if (!device || !device.DeviceAuth) throw new Error('Device did not return a DeviceAuth token');

  const rulesUrl = `${API_BASE}/api/recording_rules?${new URLSearchParams({ DeviceAuth: device.DeviceAuth })}`;
  const rules = await getJson(rulesUrl);
  const rule = (Array.isArray(rules) ? rules : []).find((candidate) => (
    candidate.SeriesID === recording.SeriesID
    && String(candidate.ChannelOnly) === String(recording.ChannelNumber)
    && Number(candidate.DateTimeOnly) === Number(recording.StartTime)
  ));
  if (rule && rule.RecordingRuleID) {
    const params = new URLSearchParams({
      DeviceAuth: device.DeviceAuth,
      Cmd: 'delete',
      RecordingRuleID: String(rule.RecordingRuleID),
    });
    const res = await fetchWithTimeout(`${API_BASE}/api/recording_rules?${params.toString()}`, { method: 'POST' });
    if (!res.ok) throw new Error(`Recording rule delete failed: ${res.status} ${res.statusText}`);
  }
  await fetchWithTimeout(`${RECORD_BASE}/recording_events.post?sync`, { method: 'POST' });
  // The RECORD engine exposes no stop-and-keep-partial operation. Deleting an
  // active file terminates its writer; removing the rule first prevents it from
  // being immediately scheduled again.
  await deleteRecording(recording);
}

async function getJson(url) {
  const res = await fetchWithTimeout(url);
  if (!res.ok) throw new Error(`RECORD engine request failed: ${res.status} ${res.statusText}`);
  return res.json();
}

function recordingId(playUrl) {
  try {
    const url = new URL(playUrl);
    const id = url.searchParams.get('id');
    return /^[a-f0-9]+$/i.test(id || '') ? id : null;
  } catch (err) {
    return null;
  }
}

async function getRecordings() {
  if (!isConfigured()) throw new Error('RECORD_ENGINE_HOST is not configured');
  const now = Math.floor(Date.now() / 1000);
  const series = await getJson(`${RECORD_BASE}/recorded_files.json`);
  const groups = await Promise.all((Array.isArray(series) ? series : []).map(async (show) => {
    const episodes = await getJson(`${RECORD_BASE}/recorded_files.json?${new URLSearchParams({ SeriesID: show.SeriesID })}`);
    return {
      ...show,
      episodes: (Array.isArray(episodes) ? episodes : [])
        .map((episode) => ({
          ...episode,
          id: recordingId(episode.PlayURL),
          recording: Number(episode.RecordStartTime) <= now && now < Number(episode.RecordEndTime || episode.EndTime),
        }))
        .filter((episode) => episode.id),
    };
  }));
  return groups.filter((group) => group.episodes.length);
}

async function getRecording(id) {
  if (!/^[a-f0-9]+$/i.test(id)) return null;
  const groups = await getRecordings();
  for (const group of groups) {
    const recording = group.episodes.find((episode) => episode.id === id);
    if (recording) return recording;
  }
  return null;
}

function getPlaybackUrl(id) {
  if (!/^[a-f0-9]+$/i.test(id) || !isConfigured()) return null;
  return `${RECORD_BASE}/recorded/play?id=${encodeURIComponent(id)}`;
}

async function deleteRecording(recording) {
  if (!recording || !recording.id || !recording.CmdURL || !isConfigured()) throw new Error('Recording not found');
  const url = new URL(recording.CmdURL);
  if (url.origin !== RECORD_BASE) throw new Error('Recording command URL is invalid');
  url.searchParams.set('cmd', 'delete');
  const res = await fetchWithTimeout(url, { method: 'POST' });
  if (!res.ok) throw new Error(`Delete recording request failed: ${res.status} ${res.statusText}`);
}

module.exports = { isConfigured, recordCurrentAiring, stopRecording, getRecordings, getRecording, getPlaybackUrl, deleteRecording };
