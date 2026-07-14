export function nowIso() {
  return new Date().toISOString();
}

export function secondsBetween(startMs, endMs = Date.now()) {
  return Math.max(0, Math.floor((endMs - startMs) / 1000));
}
