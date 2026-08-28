const hdhr = require('./hdhomerun');

const GUIDE_BASE = 'https://api.hdhomerun.com';
const TIMEOUT_MS = 8000;

async function getGuide({ duration = 6 } = {}) {
  const device = await hdhr.getDeviceInfo();
  if (!device || !device.DeviceAuth) {
    throw new Error('Device did not return a DeviceAuth token');
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const url = `${GUIDE_BASE}/api/guide?DeviceAuth=${encodeURIComponent(device.DeviceAuth)}&Duration=${duration}`;
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`Guide request failed: ${res.status} ${res.statusText}`);
    }
    return res.json();
  } finally {
    clearTimeout(timeout);
  }
}

function indexLineupByNumber(lineup) {
  const map = new Map();
  (lineup || []).forEach((entry) => {
    if (entry && entry.GuideNumber) {
      map.set(entry.GuideNumber, entry);
    }
  });
  return map;
}

function mergeFavorites(guideChannels, lineup) {
  const lineupByNumber = indexLineupByNumber(lineup);
  return (guideChannels || []).map((ch) => {
    const lineupEntry = lineupByNumber.get(ch.GuideNumber) || {};
    return {
      ...ch,
      Favorite: !!lineupEntry.Favorite,
      Hidden: Number(lineupEntry.Enabled) === 0,
    };
  });
}

module.exports = { getGuide, indexLineupByNumber, mergeFavorites };
