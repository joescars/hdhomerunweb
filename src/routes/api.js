const express = require('express');
const guide = require('../guide');
const hdhr = require('../hdhomerun');
const cache = require('../cache');

const router = express.Router();
const GUIDE_TTL_MS = Number(process.env.GUIDE_CACHE_TTL_MS || 30000);

function buildPrograms(channel) {
  const programsRaw = (channel.Guide || []).slice().sort((a, b) => a.StartTime - b.StartTime);
  const programs = [];
  for (let i = 0; i < programsRaw.length; i += 1) {
    const p = programsRaw[i];
    const next = programsRaw[i + 1];
    const endTime = next ? Math.min(p.EndTime, next.StartTime) : p.EndTime;
    const duration = endTime - p.StartTime;
    if (duration <= 0) continue;
    programs.push({
      title: p.Title || '',
      start: p.StartTime,
      duration,
      episodeTitle: p.EpisodeTitle || '',
      synopsis: p.Synopsis || '',
      image: p.ImageURL || '',
    });
  }
  return programs;
}

function programAt(programs, timestamp) {
  return programs.find((program) => program.start <= timestamp && program.start + program.duration > timestamp)
    || { title: '', episodeTitle: '', synopsis: '', image: '' };
}

function nextProgramAt(programs, timestamp) {
  return programs.find((program) => program.start > timestamp) || { title: '' };
}

router.get('/api/guide', async (req, res) => {
  res.set('Cache-Control', 'private, max-age=15, stale-while-revalidate=30');
  const slim = req.query.slim === '1';
  const serverTime = Math.floor(Date.now() / 1000);
  const slotStart = serverTime - (serverTime % 1800);
  const slimCacheKey = `guide:roku:duration:4:${slotStart}`;
  if (slim) {
    const cachedSlim = cache.get(slimCacheKey);
    if (cachedSlim) return res.json(cachedSlim);
  }

  let guideChannels;
  try {
    const cacheKey = 'guide:duration:4';
    guideChannels = cache.get(cacheKey);
    if (!guideChannels) {
      guideChannels = await guide.getGuide({ duration: 4 });
      cache.set(cacheKey, guideChannels, GUIDE_TTL_MS);
    }
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

    const programs = buildPrograms(ch);

    if (programs.length === 0) {
      continue;
    }

    const channel = {
      number: ch.GuideNumber,
      name: (lineupEntry && lineupEntry.GuideName) || ch.GuideName || '',
      logo: ch.ImageURL || '',
      favorite: !!(lineupEntry && lineupEntry.Favorite),
    };
    if (slim) {
      channel.slots = [0, 1800, 3600].map((offset) => programAt(programs, slotStart + offset));
      channel.nextTitle = nextProgramAt(programs, serverTime).title;
    } else {
      channel.streamPath = `/stream/${ch.GuideNumber}/hevc/stream.m3u8`;
      channel.programs = programs;
    }
    channels.push(channel);
  }

  const payload = { serverTime, channels };
  if (slim) cache.set(slimCacheKey, payload, GUIDE_TTL_MS);
  res.json(payload);
});

module.exports = router;
