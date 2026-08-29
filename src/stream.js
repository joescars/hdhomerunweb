const { spawn, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const hdhr = require('./hdhomerun');

const STREAM_ROOT = path.join(os.tmpdir(), 'hdhomerun-web-streams');
const IDLE_TIMEOUT_MS = 20_000;
const READY_TIMEOUT_MS = 50_000;
const CAPTION_PROBE_INTERVAL_MS = 15_000;
const DEFAULT_PROFILE = 'medium';
// Blocked by an unfixed upstream ffmpeg bug (EIA-608 "columns exceeding
// screen width" drops every cue - https://trac.ffmpeg.org/ticket/11101,
// still present as of ffmpeg 7.1.4) that silently produces an empty VTT
// file regardless of source captions. Off by default; kept as an opt-in
// fallback in case that bug is ever fixed upstream.
const WEBVTT_SIDECAR_MODE = String(process.env.WEBVTT_SIDECAR_MODE || 'off').toLowerCase() === 'on' ? 'on' : 'off';
const SOURCE_CAPTION_PROBE = String(process.env.SOURCE_CAPTION_PROBE || 'off').toLowerCase() === 'on';
// Full hardware (qsv) decode does not propagate A/53 CC side data to the
// encoder, so -a53cc silently produces captionless output. Software decode
// (still QSV-encoded) is required for embedded captions to survive at all;
// confirmed via VLC + hls.js CEA-608 parsing. Costs CPU per concurrent
// stream but is the default since captionless output is a worse trade-off.
const STREAM_DECODE_MODE = (
  String(process.env.STREAM_DECODE_MODE || process.env.CAPTION_DECODE_MODE || 'sw').toLowerCase() === 'qsv'
    ? 'qsv'
    : 'sw'
);

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

// Phase 1 caption support: keep the existing hardware transcode path and
// explicitly request embedded A/53 captions where the encoder supports it.
//
// CAPTION_MODE options:
//   - embedded (default): attempt embedded CC passthrough in the output video
//   - off: disable caption-specific encoder flags
const CAPTION_MODE = process.env.CAPTION_MODE === 'off' ? 'off' : 'embedded';
const FFPROBE_CANDIDATES = [
  process.env.FFPROBE_BIN,
  '/usr/lib/jellyfin-ffmpeg/ffprobe',
  'ffprobe',
].filter(Boolean);

function execFileAsync(file, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(file, args, options, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

async function runFfprobeJson(input, options = {}) {
  const timeoutMs = Number(options.timeoutMs || 8_000);
  const probeSize = options.probeSize || null;
  const analyzeDuration = options.analyzeDuration || null;

  const ffprobeArgs = ['-v', 'error'];
  if (probeSize) ffprobeArgs.push('-probesize', String(probeSize));
  if (analyzeDuration) ffprobeArgs.push('-analyzeduration', String(analyzeDuration));
  ffprobeArgs.push('-show_streams', '-print_format', 'json', input);

  let lastError = null;

  for (const ffprobeBin of FFPROBE_CANDIDATES) {
    try {
      const { stdout } = await execFileAsync(
        ffprobeBin,
        ffprobeArgs,
        {
          timeout: timeoutMs,
          maxBuffer: 4 * 1024 * 1024,
        }
      );

      return JSON.parse(stdout || '{}');
    } catch (err) {
      lastError = err;
      if (err && err.code === 'ENOENT') {
        continue;
      }
      throw err;
    }
  }

  throw lastError || new Error('No ffprobe binary found');
}

function parseCaptionProbeResult(probeJson) {
  const streams = Array.isArray(probeJson && probeJson.streams) ? probeJson.streams : [];
  const videoStream = streams.find((s) => s.codec_type === 'video') || null;
  const subtitleTracks = streams.filter((s) => s.codec_type === 'subtitle');

  const closedCaptions = !!(
    videoStream
    && (
      Number(videoStream.closed_captions) === 1
      || Number(videoStream.disposition && videoStream.disposition.captions) === 1
    )
  );

  const subtitleTrackCount = subtitleTracks.length;

  return {
    detected: closedCaptions || subtitleTrackCount > 0,
    closedCaptions,
    subtitleTrackCount,
    videoCodec: videoStream ? videoStream.codec_name : null,
  };
}

function isProcessAlive(proc) {
  if (!proc) return false;
  if (proc.exitCode !== null || proc.killed) return false;
  return true;
}

function startWebVttSidecar(session) {
  if (!session) return;
  if (isProcessAlive(session.webvttProcess)) return;

  // Sticky terminal state: a channel confirmed to carry no CC data would
  // otherwise get ffmpeg respawned on every stream file request (~1/s,
  // since ensureSession() is called on every segment fetch) for the rest
  // of the session. Only genuinely transient failures should retry.
  if (session.webvtt && session.webvtt.reason === 'no_subtitle_stream') return;

  if (WEBVTT_SIDECAR_MODE !== 'on') {
    session.webvtt = {
      ...session.webvtt,
      state: 'disabled',
      mode: WEBVTT_SIDECAR_MODE,
      lastUpdateAt: Date.now(),
    };
    return;
  }

  const lavfiSource = session.sourceUrl
    .replace(/\\/g, '\\\\')
    .replace(/:/g, '\\:')
    .replace(/'/g, "\\'");

  const args = [
    '-hide_banner', '-loglevel', 'warning', '-y',
    '-f', 'lavfi',
    '-i', `movie='${lavfiSource}'[out0+subcc]`,
    '-map', 's:0',
    '-c:s', 'webvtt',
    '-f', 'webvtt',
    'pipe:1',
  ];

  const proc = spawn('ffmpeg', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let stderrTail = '';
  let headerStripped = false;

  try {
    fs.writeFileSync(session.webvtt.path, 'WEBVTT\n\n');
  } catch (err) {
    session.webvtt = {
      ...session.webvtt,
      state: 'failed',
      reason: 'sidecar_open_failed',
      lastUpdateAt: Date.now(),
      lastError: err && err.message ? err.message : 'Could not initialize sidecar output',
    };
    return;
  }

  session.webvtt = {
    ...session.webvtt,
    state: 'running',
    mode: WEBVTT_SIDECAR_MODE,
    lastUpdateAt: Date.now(),
    lastError: null,
    stderrTail: null,
  };
  session.webvttProcess = proc;

  proc.stdout.on('data', (chunk) => {
    let text = chunk.toString();
    if (!text) return;

    if (!headerStripped) {
      text = text.replace(/^WEBVTT\s*/i, '');
      headerStripped = true;
    }

    if (text.trim().length > 0) {
      try {
        fs.appendFileSync(session.webvtt.path, text);
      } catch (err) {
        session.webvtt = {
          ...session.webvtt,
          state: 'failed',
          reason: 'sidecar_write_failed',
          lastUpdateAt: Date.now(),
          lastError: err && err.message ? err.message : 'Could not write sidecar output',
        };
        return;
      }
    }

    session.webvtt = {
      ...session.webvtt,
      state: 'running',
      reason: 'cues_streaming',
      lastUpdateAt: Date.now(),
      lastError: null,
    };
  });

  proc.stderr.on('data', (chunk) => {
    const text = chunk.toString();
    stderrTail = (stderrTail + text).slice(-2000);
    session.webvtt = {
      ...session.webvtt,
      lastUpdateAt: Date.now(),
      stderrTail,
    };
  });

  proc.on('exit', (code) => {
    const failed = code !== 0;
    let reason = failed ? 'ffmpeg_exit' : 'ended';
    if (failed && /matches no streams|subcc|stream map .*matches no streams/i.test(stderrTail)) {
      reason = 'no_subtitle_stream';
    }

    session.webvtt = {
      ...session.webvtt,
      state: failed ? 'failed' : 'ended',
      reason,
      lastUpdateAt: Date.now(),
      lastError: failed ? (stderrTail || `ffmpeg exited with code ${code}`) : null,
      stderrTail: stderrTail || null,
    };
  });
}

function getCaptionConfig(codec) {
  if (CAPTION_MODE !== 'embedded') {
    return {
      ffmpegArgs: [],
      active: false,
      strategy: 'disabled',
    };
  }

  // h264_qsv exposes -a53cc; hevc_qsv does not. Keep HEVC on pure hardware
  // path without unsupported flags, and surface this in diagnostics.
  if (codec === 'h264') {
    return {
      ffmpegArgs: ['-a53cc', '1'],
      active: true,
      strategy: 'a53cc_h264_qsv',
    };
  }

  return {
    ffmpegArgs: [],
    active: false,
    strategy: 'no_explicit_hevc_qsv_flag',
  };
}

function getDecodeConfig() {
  if (STREAM_DECODE_MODE === 'sw') {
    return {
      decoder: 'mpeg2video',
      inputArgs: ['-init_hw_device', 'qsv=hw', '-filter_hw_device', 'hw', '-c:v', 'mpeg2video'],
      preEncodeArgs: ['-vf', 'format=nv12,hwupload=extra_hw_frames=64'],
    };
  }

  return {
    decoder: 'mpeg2_qsv',
    inputArgs: ['-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv', '-c:v', 'mpeg2_qsv'],
    preEncodeArgs: [],
  };
}

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
  const captionConfig = getCaptionConfig(codec);
  const decodeConfig = getDecodeConfig();
  const dir = channelDir(channel, codec, normalizedProfile);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });

  const sourceUrl = `http://${hdhr.HOST}:5004/auto/v${channel}`;
  const playlist = path.join(dir, 'stream.m3u8');

  const args = [
    '-hide_banner', '-loglevel', 'warning',
    '-probesize', '500k', '-analyzeduration', '1000000',
    ...decodeConfig.inputArgs,
    '-i', sourceUrl,
    '-map', '0:v:0', '-map', '0:a:0',
    ...decodeConfig.preEncodeArgs,
    '-c:v', CODECS[codec],
    ...captionConfig.ffmpegArgs,
    '-look_ahead', '0', '-forced_idr', '1',
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
    sourceUrl,
    channel,
    codec,
    profile: normalizedProfile,
    startedAt: Date.now(),
    lastAccess: Date.now(),
    lastHeartbeat: null,
    stopReason: null,
    ffmpeg: {
      decodeMode: STREAM_DECODE_MODE,
      videoDecoder: decodeConfig.decoder,
      videoEncoder: CODECS[codec],
      audioEncoder: 'aac',
      captionMode: CAPTION_MODE,
      captionActive: captionConfig.active,
      captionStrategy: captionConfig.strategy,
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
    captions: {
      detected: null,
      closedCaptions: null,
      subtitleTrackCount: null,
      videoCodec: null,
      source: 'output_ffprobe',
      lastProbeAt: null,
      lastProbeError: null,
    },
    webvtt: {
      mode: WEBVTT_SIDECAR_MODE,
      state: 'idle',
      path: path.join(dir, 'captions.vtt'),
      reason: null,
      lastUpdateAt: null,
      lastError: null,
      stderrTail: null,
    },
    webvttProcess: null,
    sourceCaptions: {
      detected: null,
      closedCaptions: null,
      subtitleTrackCount: null,
      videoCodec: null,
      source: SOURCE_CAPTION_PROBE ? 'input_ffprobe' : 'disabled',
      lastProbeAt: null,
      lastProbeError: SOURCE_CAPTION_PROBE ? null : 'input probe disabled',
    },
    captionProbePromise: null,
    sourceCaptionProbePromise: null,
    exited: false,
  };

  try {
    fs.writeFileSync(
      session.webvtt.path,
      `WEBVTT\n\nNOTE generated by hdhomerun-web sidecar test\n\n`
    );
    session.webvtt = {
      ...session.webvtt,
      state: 'placeholder',
      reason: 'waiting_for_cues',
      lastUpdateAt: Date.now(),
      lastError: null,
    };
  } catch (err) {
    session.webvtt = {
      ...session.webvtt,
      state: 'failed',
      reason: 'placeholder_write_failed',
      lastUpdateAt: Date.now(),
      lastError: err && err.message ? err.message : 'Failed to create placeholder VTT',
    };
  }

  console.info(
    `[stream] session start channel=${channel} codec=${codec} profile=${normalizedProfile} captions=${captionConfig.strategy}`
  );

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
    if (session.stopReason === 'startup_error' && stderrTail) {
      const oneLine = stderrTail.replace(/\s+/g, ' ').trim();
      if (oneLine) {
        console.warn(`[stream] ffmpeg tail channel=${channel} codec=${codec}: ${oneLine.slice(-1200)}`);
      }
    }
    if (isProcessAlive(session.webvttProcess)) {
      session.webvttProcess.kill('SIGTERM');
    }
    fs.rmSync(dir, { recursive: true, force: true });
  });

  return session;
}

async function maybeProbeCaptionTarget(session, resultField, promiseField, input, probeOptions = {}) {
  if (!session || session.exited) return;

  const target = session[resultField];
  if (!target) return;

  const now = Date.now();
  if (
    target.lastProbeAt
    && (now - target.lastProbeAt) < CAPTION_PROBE_INTERVAL_MS
  ) {
    return;
  }

  if (session[promiseField]) {
    await session[promiseField];
    return;
  }

  session[promiseField] = (async () => {
    try {
      const probeJson = await runFfprobeJson(input, probeOptions);
      const parsed = parseCaptionProbeResult(probeJson);

      session[resultField] = {
        ...session[resultField],
        ...parsed,
        lastProbeAt: Date.now(),
        lastProbeError: null,
      };
    } catch (err) {
      session[resultField] = {
        ...session[resultField],
        lastProbeAt: Date.now(),
        lastProbeError: err && err.message ? err.message : 'Caption probe failed',
      };
    } finally {
      session[promiseField] = null;
    }
  })();

  await session[promiseField];
}

async function maybeProbeSessionCaptions(session) {
  if (!session || session.exited) return;

  const probes = [
    maybeProbeCaptionTarget(session, 'captions', 'captionProbePromise', session.playlist),
  ];

  if (SOURCE_CAPTION_PROBE) {
    probes.push(
      maybeProbeCaptionTarget(
        session,
        'sourceCaptions',
        'sourceCaptionProbePromise',
        session.sourceUrl,
        {
          timeoutMs: 12_000,
          probeSize: '16M',
          analyzeDuration: '16M',
        }
      )
    );
  }

  await Promise.all(probes);
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
    startWebVttSidecar(session);
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
  if (isProcessAlive(session.webvttProcess)) {
    session.webvttProcess.kill('SIGTERM');
  }
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
    captions: {
      ...session.captions,
      probeInFlight: !!session.captionProbePromise,
    },
    sourceCaptions: {
      ...session.sourceCaptions,
      probeInFlight: !!session.sourceCaptionProbePromise,
    },
    webvtt: {
      ...session.webvtt,
      active: isProcessAlive(session.webvttProcess),
    },
  };
}

async function getSessionInfoWithCaptions(channel, codec, profile) {
  const session = sessions.get(sessionKey(channel, codec, profile));
  if (!session) return null;

  await maybeProbeSessionCaptions(session);
  return getSessionInfo(channel, codec, profile);
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
  getSessionInfoWithCaptions,
};
