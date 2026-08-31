const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.join(os.tmpdir(), 'hdhomerun-web-recordings');
const IDLE_TIMEOUT_MS = 60_000;
const PROFILES = {
  low: { videoBitrate: '1800k', maxrate: '2200k', bufsize: '3600k', audioBitrate: '96k' },
  medium: { videoBitrate: '3200k', maxrate: '4200k', bufsize: '6400k', audioBitrate: '128k' },
  high: { videoBitrate: '5200k', maxrate: '6800k', bufsize: '9600k', audioBitrate: '160k' },
};
const sessions = new Map();

function normalizeProfile(profile) {
  return PROFILES[profile] ? profile : 'medium';
}

function key(id, profile) {
  return `${id}:${normalizeProfile(profile)}`;
}

function stop(session) {
  if (!session || session.process.exitCode !== null || session.process.killed) return;
  session.process.kill('SIGTERM');
}

function start(id, sourceUrl, profile) {
  const normalizedProfile = normalizeProfile(profile);
  const sessionKey = key(id, normalizedProfile);
  const existing = sessions.get(sessionKey);
  if (existing && existing.process.exitCode === null && !existing.process.killed) {
    existing.lastAccess = Date.now();
    return existing;
  }

  const dir = path.join(ROOT, `${id}-${normalizedProfile}`);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  const config = PROFILES[normalizedProfile];
  const playlist = path.join(dir, 'stream.m3u8');
  const process = spawn('ffmpeg', [
    '-hide_banner', '-loglevel', 'warning',
    '-i', sourceUrl,
    '-map', '0:v:0', '-map', '0:a:0?',
    '-c:v', 'h264_qsv', '-look_ahead', '0', '-forced_idr', '1',
    '-b:v', config.videoBitrate, '-maxrate', config.maxrate, '-bufsize', config.bufsize,
    '-g', '30', '-force_key_frames', 'expr:eq(n,0)+gte(t,n_forced*1)',
    '-c:a', 'aac', '-b:a', config.audioBitrate, '-ac', '2',
    '-f', 'hls', '-hls_time', '2', '-hls_list_size', '8',
    '-hls_flags', 'delete_segments+independent_segments+omit_endlist',
    '-hls_segment_filename', path.join(dir, 'segment%d.ts'),
    playlist,
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderr = '';
  process.stderr.on('data', (chunk) => {
    stderr = `${stderr}${chunk}`.slice(-4000);
  });
  const session = { process, dir, playlist, lastAccess: Date.now(), stderr: () => stderr };
  sessions.set(sessionKey, session);
  process.on('exit', () => {
    setTimeout(() => {
      if (sessions.get(sessionKey) === session) sessions.delete(sessionKey);
    }, IDLE_TIMEOUT_MS);
  });
  return session;
}

function get(id, profile) {
  const session = sessions.get(key(id, profile));
  if (session) session.lastAccess = Date.now();
  return session || null;
}

function isReady(id, profile) {
  const session = get(id, profile);
  if (!session) return { ready: false, error: 'Recording stream has not started' };
  if (fs.existsSync(session.playlist)) return { ready: true };
  if (session.process.exitCode !== null) return { ready: false, error: session.stderr() || 'Transcoder stopped' };
  return { ready: false };
}

setInterval(() => {
  const now = Date.now();
  for (const session of sessions.values()) {
    if (now - session.lastAccess > IDLE_TIMEOUT_MS) stop(session);
  }
}, 15_000).unref();

module.exports = { start, get, isReady, normalizeProfile, PROFILES };
