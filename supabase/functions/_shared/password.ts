/**
 * Temporary passwords — same generator as the web app (lib/auth/password.ts), so a credential
 * issued from the phone reads exactly like one issued from the browser: "Sage-7413-Kite".
 *
 * The password is returned to the caller ONCE and is never written to any table, log, or audit
 * row (audit_event() also strips password-ish keys from meta as a second line of defence).
 */
const WORDS = [
  "Amber", "Birch", "Cedar", "Delta", "Ember", "Fjord", "Grove", "Haven", "Ivory", "Juno",
  "Kite", "Lotus", "Maple", "Nova", "Opal", "Pearl", "Quill", "Ridge", "Sage", "Tide",
  "Umber", "Vale", "Willow", "Xenon", "Yarrow", "Zephyr", "Coral", "Dune", "Flint", "Marsh",
];

/**
 * Uniform random integer in [min, max) from the CSPRNG.
 *
 * The obvious `getRandomValues() % range` is biased when range does not divide 2^32 — with 30
 * words the first 16 would come up slightly more often. Rejection sampling removes that.
 */
function randomInt(min: number, max: number): number {
  const range = max - min;
  if (range <= 0) throw new Error("randomInt: empty range");
  const limit = Math.floor(0xffffffff / range) * range;
  const buf = new Uint32Array(1);
  let x = 0;
  do {
    crypto.getRandomValues(buf);
    x = buf[0];
  } while (x >= limit);
  return min + (x % range);
}

export function generatePassword(): string {
  const w1 = WORDS[randomInt(0, WORDS.length)];
  const w2 = WORDS[randomInt(0, WORDS.length)];
  const num = randomInt(1000, 9999);
  return `${w1}-${num}-${w2}`;
}
