const express = require('express');
const guide = require('../guide');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/api/guide', async (req, res) => {
  let guideChannels;
  try {
    guideChannels = await guide.getGuide({ duration: 4 });
  } catch (err) {
    res.status(502).json({ error: err.message });
    return;
  }

  const lineup = await hdhr.getLineup().catch(() => []);
  const lineupByNumber = guide.indexLineupByNumber(lineup);

  const channels = [];
  for (const ch of guideChannels || []) {
    const lineupEntry = lineupByNumber.get(ch.GuideNumber);
    if (lineupEntry && (lineupEntry.Subscribed === 0 || lineupEntry.Enabled === 0)) {
      continue;
    }

    const programsRaw = (ch.Guide || []).slice().sort((a, b) => a.StartTime - b.StartTime);
    const programs = [];
    for (let i = 0; i < programsRaw.length; i += 1) {
      const p = programsRaw[i];
      const next = programsRaw[i + 1];
      const endTime = next ? Math.min(p.EndTime, next.StartTime) : p.EndTime;
      const duration = endTime - p.StartTime;
      if (duration <= 0) {
        continue;
      }
      programs.push({
        title: p.Title || '',
        start: p.StartTime,
        duration,
        episodeTitle: p.EpisodeTitle || '',
        synopsis: p.Synopsis || '',
        image: p.ImageURL || '',
      });
    }

    if (programs.length === 0) {
      continue;
    }

    channels.push({
      number: ch.GuideNumber,
      name: (lineupEntry && lineupEntry.GuideName) || ch.GuideName || '',
      logo: ch.ImageURL || '',
      favorite: !!(lineupEntry && lineupEntry.Favorite),
      streamPath: `/stream/${ch.GuideNumber}/hevc/stream.m3u8`,
      programs,
    });
  }

  res.json({
    serverTime: Math.floor(Date.now() / 1000),
    channels,
  });
});

module.exports = router;
