const express = require('express');
const guide = require('../guide');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/guide', async (req, res) => {
  try {
    const channels = await guide.getGuide({ duration: 6 });
    res.render('guide', { channels: channels || [], error: null, now: Math.floor(Date.now() / 1000) });
  } catch (err) {
    res.render('guide', { channels: [], error: err.message, now: Math.floor(Date.now() / 1000) });
  }
});

router.get('/guide/grid', async (req, res) => {
  const now = Math.floor(Date.now() / 1000);
  try {
    const [guideChannels, lineup] = await Promise.all([
      guide.getGuide({ duration: 8 }),
      hdhr.getLineup().catch(() => []),
    ]);
    const channels = guide.mergeFavorites(guideChannels, lineup);
    res.render('guide-grid', { channels, error: null, now });
  } catch (err) {
    res.render('guide-grid', { channels: [], error: err.message, now });
  }
});

module.exports = router;
