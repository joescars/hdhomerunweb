const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/channels', async (req, res) => {
  try {
    const channels = await hdhr.getLineup();
    res.render('channels', { channels: channels || [], error: null });
  } catch (err) {
    res.render('channels', { channels: [], error: err.message });
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
