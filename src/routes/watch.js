const express = require('express');
const fs = require('fs');
const path = require('path');

const stream = require('../stream');
const hdhr = require('../hdhomerun');

const router = express.Router();

const CHANNEL_RE = /^[0-9]+(\.[0-9]+)?$/;
const CODEC_RE = /^(h264|hevc|direct)$/;
const FILE_RE = /^(stream\.m3u8|segment[0-9]+\.ts|captions\.vtt)$/;
const PROFILE_RE = /^(low|medium|high)$/;

function parseStreamRequest(req, includeFile = false) {
  const { channel, codec } = req.params;
  const profile = req.params.profile || stream.DEFAULT_PROFILE;
  if (!CHANNEL_RE.test(channel) || !CODEC_RE.test(codec) || !PROFILE_RE.test(profile)) {
    return null;
  }

  if (!includeFile) {
    return { channel, codec, profile };
  }

  const { file } = req.params;
  if (!FILE_RE.test(file)) {
    return null;
  }
  return { channel, codec, profile, file };
}

router.get('/watch/:channel', async (req, res) => {
  res.set('Cache-Control', 'no-store');

  const { channel } = req.params;
  if (!CHANNEL_RE.test(channel)) return res.status(400).send('Invalid channel');

  let channelName = null;
  try {
    const channels = await hdhr.getLineup();
    const ch = (channels || []).find((c) => c.GuideNumber === channel);
    if (ch) channelName = ch.GuideName;
  } catch (err) {
    // Lineup lookup is cosmetic only; ignore failures.
  }

  const requestedQuality = String(req.query.quality || '').toLowerCase();
  const qualityProfile = PROFILE_RE.test(requestedQuality)
    ? requestedQuality
    : null;

  res.render('watch', {
    channel,
    channelName,
    qualityProfile,
    qualityOptions: stream.STREAM_PROFILES,
    webvttSidecarEnabled: String(process.env.WEBVTT_SIDECAR_MODE || 'on').toLowerCase() !== 'off',
  });
});

// :codec picks the ffmpeg encoder - h264 for browsers (hls.js's TS demuxer
// can't parse HEVC NAL units), hevc for the Roku client, which decodes it
// natively via its Video node. See CLAUDE.md.
function startSession(req, res) {
  const parsed = parseStreamRequest(req);
  if (!parsed) return res.status(400).send('Invalid request');
  stream.start(parsed.channel, parsed.codec, parsed.profile);
  res.status(202).end();
}

function readyState(req, res) {
  const parsed = parseStreamRequest(req);
  if (!parsed) return res.status(400).send('Invalid request');
  stream.touch(parsed.channel, parsed.codec, parsed.profile);
  res.json(stream.isReady(parsed.channel, parsed.codec, parsed.profile));
}

function heartbeat(req, res) {
  const parsed = parseStreamRequest(req);
  if (!parsed) return res.status(400).send('Invalid request');
  stream.touch(parsed.channel, parsed.codec, parsed.profile, 'heartbeat');
  res.status(204).end();
}

async function streamFile(req, res) {
  const parsed = parseStreamRequest(req, true);
  if (!parsed) return res.status(400).send('Invalid request');

  try {
    const session = await stream.ensureSession(parsed.channel, parsed.codec, parsed.profile);
    stream.touch(parsed.channel, parsed.codec, parsed.profile);
    const filePath = path.join(session.dir, parsed.file);
    if (!fs.existsSync(filePath)) return res.status(404).end();

    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader(
      'Content-Type',
      parsed.file.endsWith('.m3u8')
        ? 'application/vnd.apple.mpegurl'
        : (parsed.file.endsWith('.vtt') ? 'text/vtt; charset=utf-8' : 'video/mp2t')
    );
    fs.createReadStream(filePath).pipe(res);
  } catch (err) {
    res.status(502).send(err.message);
  }
}

router.get('/stream/metrics', (req, res) => {
  res.json(stream.getMetrics());
});

async function streamStats(req, res) {
  const parsed = parseStreamRequest(req);
  if (!parsed) return res.status(400).send('Invalid request');

  const session = await stream.getSessionInfoWithCaptions(parsed.channel, parsed.codec, parsed.profile);
  if (!session) return res.status(404).json({ error: 'No active session for that stream' });

  let tuner = null;
  let signalError = null;
  try {
    const tunerStatus = await hdhr.getTunerStatus();
    tuner = (tunerStatus || []).find((entry) => String(entry.VctNumber || '') === parsed.channel) || null;
  } catch (err) {
    signalError = err.message;
  }

  res.json({
    channel: parsed.channel,
    codec: parsed.codec,
    profile: parsed.profile,
    session,
    tuner: tuner
      ? {
          resource: tuner.Resource || null,
          channelNumber: tuner.VctNumber || null,
          channelName: tuner.VctName || null,
          signalStrengthPercent: typeof tuner.SignalStrengthPercent === 'number'
            ? tuner.SignalStrengthPercent
            : null,
          signalQualityPercent: typeof tuner.SignalQualityPercent === 'number'
            ? tuner.SignalQualityPercent
            : null,
          symbolQualityPercent: typeof tuner.SymbolQualityPercent === 'number'
            ? tuner.SymbolQualityPercent
            : null,
          networkRateMbps: typeof tuner.NetworkRate === 'number'
            ? Number(((tuner.NetworkRate * 8) / 1000000).toFixed(2))
            : null,
        }
      : null,
    signalError,
  });
}

router.get('/stream/:channel/:codec/stats', streamStats);
router.get('/stream/:channel/:codec/:profile/stats', streamStats);

router.post('/stream/:channel/:codec/start', startSession);
router.post('/stream/:channel/:codec/:profile/start', startSession);
router.get('/stream/:channel/:codec/ready', readyState);
router.get('/stream/:channel/:codec/:profile/ready', readyState);
router.post('/stream/:channel/:codec/heartbeat', heartbeat);
router.post('/stream/:channel/:codec/:profile/heartbeat', heartbeat);
router.get('/stream/:channel/:codec/:file', streamFile);
router.get('/stream/:channel/:codec/:profile/:file', streamFile);

module.exports = router;
