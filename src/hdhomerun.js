const HOST = process.env.HDHOMERUN_HOST || 'hdhomerun.local';
const PORT = process.env.HDHOMERUN_PORT || 80;
const BASE = `http://${HOST}:${PORT}`;
const TIMEOUT_MS = 5000;

async function request(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${BASE}${path}`, { ...options, signal: controller.signal });
    if (!res.ok) {
      throw new Error(`HDHomeRun request failed: ${res.status} ${res.statusText}`);
    }
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  } finally {
    clearTimeout(timeout);
  }
}

function getDeviceInfo() {
  return request('/discover.json');
}

function getLineup() {
  return request('/lineup.json?show=all');
}

function getLineupStatus() {
  return request('/lineup_status.json');
}

function startScan() {
  return request('/lineup.post?scan=start', { method: 'POST' });
}

function abortScan() {
  return request('/lineup.post?scan=abort', { method: 'POST' });
}

function getTunerStatus() {
  return request('/status.json');
}

module.exports = {
  HOST,
  getDeviceInfo,
  getLineup,
  getLineupStatus,
  startScan,
  abortScan,
  getTunerStatus,
};
