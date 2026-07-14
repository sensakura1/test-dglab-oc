export function randomIntInRange([min, max], rng = Math.random) {
  if (min === max) return min;
  return Math.floor(rng() * (max - min + 1)) + min;
}
