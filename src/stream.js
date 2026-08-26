const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const hdhr = require('./hdhomerun');

const STREAM_ROOT = path.join(os.tmpdir(), 'hdhomerun-web-streams');
const IDLE_TIMEOUT_MS = 20_000;
const READY_TIMEOUT_MS = 50_000;

const sessions = new Map();

function channelDir(channel) {
  return path.join(STREAM_ROOT, channel);
}

function spawnFfmpeg(channel) {
  const dir = channelDir(channel);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const sourceUrl = `http://${hdhr.HOST}:5004/auto/v${channel}`;
  const playlist = path.join(dir, 'stream.m3u8');

  const args = [
    '-hide_banner', '-loglevel', 'warning',
    '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv', '-c:v', 'mpeg2_qsv',
    '-i', sourceUrl,
    '-map', '0:v:0', '-map', '0:a:0',
    '-c:v', 'h264_qsv', '-global_quality', '23', '-look_ahead', '0', '-forced_idr', '1',
    '-g', '60', '-force_key_frames', 'expr:gte(t,n_forced*2)',
    '-c:a', 'aac', '-b:a', '128k', '-ac', '2',
    '-f', 'hls',
    '-hls_time', '2',
    '-hls_list_size', '12',
    '-hls_flags', 'delete_segments+independent_segments+omit_endlist',
    '-hls_segment_filename', path.join(dir, 'segment%d.ts'),
    playlist,
  ];

  const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'ignore', 'pipe'] });
  let stderrTail = '';
  proc.stderr.on('data', (chunk) => {
    stderrTail = (stderrTail + chunk.toString()).slice(-4000);
  });

  const session = {
    process: proc,
    dir,
    playlist,
    lastAccess: Date.now(),
    stderrTail: () => stderrTail,
    exited: false,
  };

  proc.on('exit', () => {
    session.exited = true;
    sessions.delete(channel);
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

function getOrCreateSession(channel) {
  let session = sessions.get(channel);
  if (!session) {
    session = spawnFfmpeg(channel);
    sessions.set(channel, session);
  }
  session.lastAccess = Date.now();
  return session;
}

// Starts a session if needed without waiting for it to be ready. Used by the
// player to kick off ffmpeg as soon as the watch page loads, before polling
// isReady() rather than holding one long HTTP request (tuning can take
// anywhere from ~5s to ~40s and browsers/hls.js time out long single
// requests well before that).
function start(channel) {
  getOrCreateSession(channel);
}

function isReady(channel) {
  const session = sessions.get(channel);
  if (!session) return { ready: false, failed: false };
  if (session.exited) return { ready: false, failed: true, error: session.stderrTail() };
  return { ready: fs.existsSync(session.playlist), failed: false };
}

async function ensureSession(channel) {
  const session = getOrCreateSession(channel);
  try {
    await waitForPlaylist(session);
  } catch (err) {
    stopSession(channel);
    throw err;
  }
  return session;
}

function touch(channel) {
  const session = sessions.get(channel);
  if (session) session.lastAccess = Date.now();
}

function stopSession(channel) {
  const session = sessions.get(channel);
  if (session) session.process.kill('SIGTERM');
}

setInterval(() => {
  const now = Date.now();
  for (const [channel, session] of sessions) {
    if (now - session.lastAccess > IDLE_TIMEOUT_MS) {
      stopSession(channel);
    }
  }
}, 5_000).unref();

module.exports = { ensureSession, start, isReady, touch, stopSession, channelDir };
