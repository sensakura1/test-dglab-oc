export function clamp(value, min, max) {
  if (!Number.isFinite(value)) return min;
  return Math.min(Math.max(value, min), max);
}

export function normalizeRange(range, fallback, min, max) {
  const input = Array.isArray(range) && range.length === 2 ? range : fallback;
  const low = clamp(Number(input[0]), min, max);
  const high = clamp(Number(input[1]), min, max);
  return low <= high ? [low, high] : [high, low];
}
