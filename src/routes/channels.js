const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();
const CHANNEL_BATCH_SIZE = Math.max(20, Number(process.env.CHANNEL_BATCH_SIZE || 80) || 80);

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) return fallback;
  return parsed;
}

router.get('/channels', async (req, res) => {
  try {
    const channels = await hdhr.getLineup() || [];
    const initialChannels = channels.slice(0, CHANNEL_BATCH_SIZE);
    res.render('channels', {
      channels: initialChannels,
      totalChannels: channels.length,
      nextOffset: initialChannels.length,
      batchSize: CHANNEL_BATCH_SIZE,
      error: null,
    });
  } catch (err) {
    res.render('channels', {
      channels: [],
      totalChannels: 0,
      nextOffset: 0,
      batchSize: CHANNEL_BATCH_SIZE,
      error: err.message,
    });
  }
});

router.get('/channels/rows', async (req, res) => {
  const offset = parsePositiveInt(req.query.offset, 0);
  const requestedLimit = parsePositiveInt(req.query.limit, CHANNEL_BATCH_SIZE);
  const limit = Math.min(Math.max(requestedLimit, 20), 200);

  try {
    const channels = await hdhr.getLineup() || [];
    const slice = channels.slice(offset, offset + limit);
    res.render('_channel_rows', {
      channels: slice,
      nextOffset: offset + slice.length,
      totalChannels: channels.length,
      limit,
    });
  } catch (err) {
    res.status(502).send(err.message);
  }
});

router.post('/channels/flag', async (req, res) => {
  const { guide, mode } = req.query;
  try {
    await hdhr.setChannelFlag(guide, mode);
    const channels = await hdhr.getLineup();
    const ch = (channels || []).find((c) => c.GuideNumber === guide);
    if (!ch) return res.status(404).send('Channel not found');
    res.render('_channel_row', { ch });
  } catch (err) {
    res.status(502).send(err.message);
  }
});

module.exports = router;
