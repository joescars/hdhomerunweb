const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const hdhr = require('./hdhomerun');

const STREAM_ROOT = path.join(os.tmpdir(), 'hdhomerun-web-streams');
const IDLE_TIMEOUT_MS = 20_000;
const READY_TIMEOUT_MS = 50_000;
const DEFAULT_PROFILE = 'medium';

const QUALITY_PROFILES = {
  low: {
    videoBitrate: '1800k',
    maxrate: '2200k',
    bufsize: '3600k',
    audioBitrate: '96k',
  },
  medium: {
    videoBitrate: '3200k',
    maxrate: '4200k',
    bufsize: '6400k',
    audioBitrate: '128k',
  },
  high: {
    videoBitrate: '5200k',
    maxrate: '6800k',
    bufsize: '9600k',
    audioBitrate: '160k',
  },
};
const STREAM_PROFILES = Object.keys(QUALITY_PROFILES);

// h264 is the broadly-compatible default (every browser's MSE/hls.js pipeline
// plays it). hevc is opt-in, used only by the Roku client, whose Video node
// decodes it natively rather than through a JS demuxer - see CLAUDE.md.
const CODECS = {
  h264: 'h264_qsv',
  hevc: 'hevc_qsv',
};

const sessions = new Map();
const metrics = {
  sessionsStarted: 0,
  sessionsExited: 0,
  sessionsStoppedIdle: 0,
  sessionsStoppedError: 0,
  heartbeats: 0,
  cleanupRuns: 0,
  lastCleanupAt: null,
};

const FF_PROGRESS_KEYS = new Set([
  'frame',
  'fps',
  'stream_0_0_q',
  'bitrate',
  'total_size',
  'out_time_us',
  'out_time_ms',
  'out_time',
  'dup_frames',
  'drop_frames',
  'speed',
  'progress',
]);

function normalizeProfile(profile) {
  return STREAM_PROFILES.includes(profile) ? profile : DEFAULT_PROFILE;
}

function sessionKey(channel, codec, profile) {
  return `${channel}:${codec}:${normalizeProfile(profile)}`;
}

function channelDir(channel, codec, profile) {
  return path.join(STREAM_ROOT, `${channel}-${codec}-${normalizeProfile(profile)}`);
}

function spawnFfmpeg(channel, codec, profile) {
  const normalizedProfile = normalizeProfile(profile);
  const profileConfig = QUALITY_PROFILES[normalizedProfile];
  const dir = channelDir(channel, codec, normalizedProfile);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const sourceUrl = `http://${hdhr.HOST}:5004/auto/v${channel}`;
  const playlist = path.join(dir, 'stream.m3u8');

  const args = [
    '-hide_banner', '-loglevel', 'warning',
    '-probesize', '500k', '-analyzeduration', '1000000',
    '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv', '-c:v', 'mpeg2_qsv',
    '-i', sourceUrl,
    '-map', '0:v:0', '-map', '0:a:0',
    '-c:v', CODECS[codec], '-look_ahead', '0', '-forced_idr', '1',
    '-b:v', profileConfig.videoBitrate,
    '-maxrate', profileConfig.maxrate,
    '-bufsize', profileConfig.bufsize,
    '-g', '30', '-force_key_frames', 'expr:eq(n,0)+gte(t,n_forced*1)',
    '-c:a', 'aac', '-b:a', profileConfig.audioBitrate, '-ac', '2',
    '-f', 'hls',
    '-hls_time', '1',
    '-hls_list_size', '6',
    '-hls_flags', 'delete_segments+independent_segments+omit_endlist',
    '-hls_segment_filename', path.join(dir, 'segment%d.ts'),
    '-progress', 'pipe:2',
    '-nostats',
    playlist,
  ];

  const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderrTail = '';
  let stderrBuffer = '';

  const key = sessionKey(channel, codec, normalizedProfile);
  const session = {
    process: proc,
    dir,
    playlist,
    channel,
    codec,
    profile: normalizedProfile,
    startedAt: Date.now(),
    lastAccess: Date.now(),
    lastHeartbeat: null,
    stopReason: null,
    ffmpeg: {
      videoEncoder: CODECS[codec],
      audioEncoder: 'aac',
      hlsTimeSeconds: 1,
      hlsListSize: 6,
      targetVideoBitrate: profileConfig.videoBitrate,
      maxrate: profileConfig.maxrate,
      bufsize: profileConfig.bufsize,
      targetAudioBitrate: profileConfig.audioBitrate,
    },
    progress: {
      frame: null,
      fps: null,
      bitrate: null,
      speed: null,
      outTimeMs: null,
      totalSizeBytes: null,
      dupFrames: null,
      dropFrames: null,
      lastUpdateAt: null,
    },
    stderrTail: () => stderrTail,
    exited: false,
  };
  metrics.sessionsStarted += 1;

  function parseProgressLine(line) {
    const idx = line.indexOf('=');
    if (idx < 1) return false;
    const keyName = line.slice(0, idx);
    if (!FF_PROGRESS_KEYS.has(keyName)) return false;
    const value = line.slice(idx + 1).trim();
    switch (keyName) {
      case 'frame':
        session.progress.frame = Number.parseInt(value, 10) || 0;
        break;
      case 'fps':
        session.progress.fps = Number.parseFloat(value) || 0;
        break;
      case 'bitrate':
        session.progress.bitrate = value;
        break;
      case 'speed':
        session.progress.speed = value;
        break;
      case 'out_time_ms':
      case 'out_time_us':
        session.progress.outTimeMs = Math.max(0, Math.floor((Number.parseInt(value, 10) || 0) / 1000));
        break;
      case 'total_size':
        session.progress.totalSizeBytes = Number.parseInt(value, 10) || 0;
        break;
      case 'dup_frames':
        session.progress.dupFrames = Number.parseInt(value, 10) || 0;
        break;
      case 'drop_frames':
        session.progress.dropFrames = Number.parseInt(value, 10) || 0;
        break;
      case 'progress':
        session.progress.lastUpdateAt = Date.now();
        break;
      default:
        break;
    }
    return true;
  }

  proc.stderr.on('data', (chunk) => {
    const text = chunk.toString().replace(/\r/g, '\n');
    stderrBuffer += text;
    const lines = stderrBuffer.split('\n');
    stderrBuffer = lines.pop() || '';
    for (const lineRaw of lines) {
      const line = lineRaw.trim();
      if (!line) continue;
      const wasProgress = parseProgressLine(line);
      if (!wasProgress) {
        stderrTail = (stderrTail + line + '\n').slice(-4000);
      }
    }
  });

  proc.on('exit', () => {
    metrics.sessionsExited += 1;
    if (session.stopReason === 'idle_timeout') metrics.sessionsStoppedIdle += 1;
    if (session.stopReason === 'startup_error') metrics.sessionsStoppedError += 1;
    session.exited = true;
    sessions.delete(key);
    console.info(
      `[stream] session exited channel=${channel} codec=${codec} profile=${normalizedProfile} reason=${session.stopReason || 'process_exit'}`
    );
    fs.rmSync(dir, { recursive: true, force: true });
  });

  return session;
}

async function waitForPlaylist(session) {
  const start = Date.now();
  while (Date.now() - start < READY_TIMEOUT_MS) {
    if (session.exited) {
      throw new Error(`ffmpeg exited before producing output:\n${session.stderrTail()}`);
    }
    if (fs.existsSync(session.playlist)) {
      return;
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error('Timed out waiting for stream to start');
}

function getOrCreateSession(channel, codec, profile) {
  const normalizedProfile = normalizeProfile(profile);
  const key = sessionKey(channel, codec, normalizedProfile);
  let session = sessions.get(key);
  if (!session) {
    session = spawnFfmpeg(channel, codec, normalizedProfile);
    sessions.set(key, session);
  }
  session.lastAccess = Date.now();
  return session;
}

// Starts a session if needed without waiting for it to be ready. Used by the
// player to kick off ffmpeg as soon as the watch page loads, before polling
// isReady() rather than holding one long HTTP request (tuning can take
// anywhere from ~5s to ~40s and browsers/hls.js time out long single
// requests well before that).
function start(channel, codec, profile) {
  getOrCreateSession(channel, codec, profile);
}

function isReady(channel, codec, profile) {
  const session = sessions.get(sessionKey(channel, codec, profile));
  if (!session) return { ready: false, failed: false };
  if (session.exited) return { ready: false, failed: true, error: session.stderrTail() };
  return { ready: fs.existsSync(session.playlist), failed: false };
}

async function ensureSession(channel, codec, profile) {
  const session = getOrCreateSession(channel, codec, profile);
  try {
    await waitForPlaylist(session);
  } catch (err) {
    stopSession(channel, codec, profile, 'startup_error');
    throw err;
  }
  return session;
}

function touch(channel, codec, profile, source = 'access') {
  const session = sessions.get(sessionKey(channel, codec, profile));
  if (!session) return;
  session.lastAccess = Date.now();
  if (source === 'heartbeat') {
    session.lastHeartbeat = Date.now();
    metrics.heartbeats += 1;
  }
}

function stopSession(channel, codec, profile, reason = 'manual') {
  const session = sessions.get(sessionKey(channel, codec, profile));
  if (!session) return;
  session.stopReason = reason;
  session.process.kill('SIGTERM');
}

function getMetrics() {
  return {
    ...metrics,
    activeSessions: sessions.size,
    sessions: Array.from(sessions.values()).map((session) => ({
      channel: session.channel,
      codec: session.codec,
      profile: session.profile,
      ageMs: Date.now() - session.startedAt,
      idleMs: Date.now() - session.lastAccess,
      heartbeatAgeMs: session.lastHeartbeat ? Date.now() - session.lastHeartbeat : null,
    })),
  };
}

function getSessionInfo(channel, codec, profile) {
  const session = sessions.get(sessionKey(channel, codec, profile));
  if (!session) return null;
  return {
    channel: session.channel,
    codec: session.codec,
    profile: session.profile,
    startedAt: session.startedAt,
    ageMs: Date.now() - session.startedAt,
    idleMs: Date.now() - session.lastAccess,
    heartbeatAgeMs: session.lastHeartbeat ? Date.now() - session.lastHeartbeat : null,
    ffmpeg: { ...session.ffmpeg },
    progress: {
      ...session.progress,
      bitrate: session.progress.bitrate || null,
      speed: session.progress.speed || null,
    },
  };
}

setInterval(() => {
  metrics.cleanupRuns += 1;
  metrics.lastCleanupAt = Date.now();
  const now = Date.now();
  for (const session of sessions.values()) {
    if (now - session.lastAccess > IDLE_TIMEOUT_MS) {
      stopSession(session.channel, session.codec, session.profile, 'idle_timeout');
    }
  }
}, 5_000).unref();

module.exports = {
  ensureSession,
  start,
  isReady,
  touch,
  stopSession,
  channelDir,
  CODECS,
  STREAM_PROFILES,
  DEFAULT_PROFILE,
  getMetrics,
  getSessionInfo,
};
