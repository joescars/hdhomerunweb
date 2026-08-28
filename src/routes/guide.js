const express = require('express');
const guide = require('../guide');
const hdhr = require('../hdhomerun');
const cache = require('../cache');

const router = express.Router();
const GUIDE_TTL_MS = Number(process.env.GUIDE_CACHE_TTL_MS || 30000);

router.get('/guide', async (req, res) => {
  res.set('Cache-Control', 'private, max-age=10, stale-while-revalidate=20');
  res.render('guide', { now: Math.floor(Date.now() / 1000) });
});

router.get('/guide/fragment', async (req, res) => {
  res.set('Cache-Control', 'private, max-age=30, stale-while-revalidate=30');
  const now = Math.floor(Date.now() / 1000);
  try {
    const cacheKey = 'guide:duration:6';
    let guideChannels = cache.get(cacheKey);
    if (!guideChannels) {
      guideChannels = await guide.getGuide({ duration: 6 });
      cache.set(cacheKey, guideChannels, GUIDE_TTL_MS);
    }
    const lineup = await hdhr.getLineup().catch(() => []);
    const channels = guide.mergeFavorites(guideChannels, lineup);
    res.render('_guide_accordion', { channels, error: null, now });
  } catch (err) {
    res.render('_guide_accordion', { channels: [], error: err.message, now });
  }
});

router.get('/guide/grid', async (req, res) => {
  res.set('Cache-Control', 'private, max-age=30, stale-while-revalidate=30');
  const now = Math.floor(Date.now() / 1000);
  try {
    const cacheKey = 'guide:duration:8';
    let guideChannels = cache.get(cacheKey);
    if (!guideChannels) {
      guideChannels = await guide.getGuide({ duration: 8 });
      cache.set(cacheKey, guideChannels, GUIDE_TTL_MS);
    }
    const lineup = await hdhr.getLineup().catch(() => []);
    const channels = guide.mergeFavorites(guideChannels, lineup);
    res.render('guide-grid', { channels, error: null, now });
  } catch (err) {
    res.render('guide-grid', { channels: [], error: err.message, now });
  }
});

module.exports = router;
