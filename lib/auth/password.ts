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

/**
 * THE METER COUNTS THE RULES THE FORM ENFORCES, AND NOTHING ELSE.
 *
 * It used to score length twice (>= 8 and >= 12) and pair the character classes two at a time,
 * so `correcthorsebattery` scored 2 of 4 while failing changePasswordSchema outright, and
 * `Correct1horse` scored 3 of 4 — "Good" — while Supabase refused it for having no symbol. A
 * bar that fills for reasons the validator ignores is a lie with a progress bar attached.
 *
 * The four steps below are now exactly the four constraints in changePasswordSchema beyond
 * length, so the meter is full at the moment the form would accept the password and the server
 * would keep it. Length is the floor rather than a step: below it nothing else is worth
 * scoring, which is what "Too short" means.
 */
export function passwordStrength(pw: string): { score: 0 | 1 | 2 | 3 | 4; label: string } {
  if (pw.length < PASSWORD_MIN_LENGTH) return { score: 0, label: "Too short" };
  let score = 0;
  if (/[a-z]/.test(pw)) score++;
  if (/[A-Z]/.test(pw)) score++;
  if (/\d/.test(pw)) score++;
  if (/[^A-Za-z0-9\s]/.test(pw)) score++;
  const label = ["Too short", "Weak", "Fair", "Good", "Strong"][score];
  return { score: score as 0 | 1 | 2 | 3 | 4, label };
}
