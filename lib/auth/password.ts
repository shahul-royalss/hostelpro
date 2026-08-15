import { randomInt } from "crypto";

/**
 * Generate a memorable-but-strong temporary password, e.g. "Sage-7413-Kite".
 * Users must change it on first login (Hard rule §4.9).
 */
const WORDS = [
  "Amber", "Birch", "Cedar", "Delta", "Ember", "Fjord", "Grove", "Haven", "Ivory", "Juno",
  "Kite", "Lotus", "Maple", "Nova", "Opal", "Pearl", "Quill", "Ridge", "Sage", "Tide",
  "Umber", "Vale", "Willow", "Xenon", "Yarrow", "Zephyr", "Coral", "Dune", "Flint", "Marsh",
];

export function generatePassword(): string {
  const w1 = WORDS[randomInt(WORDS.length)];
  const w2 = WORDS[randomInt(WORDS.length)];
  const num = randomInt(1000, 9999);
  return `${w1}-${num}-${w2}`;
}

export const PASSWORD_MIN_LENGTH = 8;

export function passwordStrength(pw: string): { score: 0 | 1 | 2 | 3 | 4; label: string } {
  let score = 0;
  if (pw.length >= PASSWORD_MIN_LENGTH) score++;
  if (pw.length >= 12) score++;
  if (/[A-Z]/.test(pw) && /[a-z]/.test(pw)) score++;
  if (/\d/.test(pw) && /[^A-Za-z0-9]/.test(pw)) score++;
  const label = ["Too short", "Weak", "Fair", "Good", "Strong"][score];
  return { score: score as 0 | 1 | 2 | 3 | 4, label };
}
