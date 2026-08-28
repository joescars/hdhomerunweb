const store = new Map();

function get(key) {
  const entry = store.get(key);
  if (!entry) return null;

  if (entry.expiresAt <= Date.now()) {
    store.delete(key);
    return null;
  }

  return entry.value;
}

function set(key, value, ttlMs) {
  store.set(key, {
    value,
    expiresAt: Date.now() + ttlMs,
  });
}

function clear(key) {
  if (typeof key === 'string') {
    store.delete(key);
    return;
  }
  store.clear();
}

module.exports = {
  get,
  set,
  clear,
};
