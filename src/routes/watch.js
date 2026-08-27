const express = require('express');
const fs = require('fs');
const path = require('path');

const stream = require('../stream');
const hdhr = require('../hdhomerun');

const router = express.Router();

const CHANNEL_RE = /^[0-9]+(\.[0-9]+)?$/;
const CODEC_RE = /^(h264|hevc)$/;
const FILE_RE = /^(stream\.m3u8|segment[0-9]+\.ts)$/;

router.get('/watch/:channel', async (req, res) => {
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

  res.render('watch', { channel, channelName });
});

// :codec picks the ffmpeg encoder - h264 for browsers (hls.js's TS demuxer
// can't parse HEVC NAL units), hevc for the Roku client, which decodes it
// natively via its Video node. See CLAUDE.md.
router.post('/stream/:channel/:codec/start', (req, res) => {
  const { channel, codec } = req.params;
  if (!CHANNEL_RE.test(channel) || !CODEC_RE.test(codec)) return res.status(400).send('Invalid request');
  stream.start(channel, codec);
  res.status(202).end();
});

router.get('/stream/:channel/:codec/ready', (req, res) => {
  const { channel, codec } = req.params;
  if (!CHANNEL_RE.test(channel) || !CODEC_RE.test(codec)) return res.status(400).send('Invalid request');
  stream.touch(channel, codec);
  res.json(stream.isReady(channel, codec));
});

router.get('/stream/:channel/:codec/:file', async (req, res) => {
  const { channel, codec, file } = req.params;
  if (!CHANNEL_RE.test(channel) || !CODEC_RE.test(codec) || !FILE_RE.test(file)) {
    return res.status(400).send('Invalid request');
  }

  try {
    const session = await stream.ensureSession(channel, codec);
    stream.touch(channel, codec);
    const filePath = path.join(session.dir, file);
    if (!fs.existsSync(filePath)) return res.status(404).end();

    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader(
      'Content-Type',
      file.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp2t'
    );
    fs.createReadStream(filePath).pipe(res);
  } catch (err) {
    res.status(502).send(err.message);
  }
});

module.exports = router;
