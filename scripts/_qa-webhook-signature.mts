/**
 * Does the payment webhook actually refuse a forged delivery?
 *
 * The HMAC signature is the ENTIRE perimeter of the money path. Razorpay is never signed in, so
 * POST /api/webhooks/razorpay and POST /functions/v1/razorpay-webhook have to be reachable with
 * no session at all. Everything that stops a stranger with curl from marking a stranger's rent
 * as paid lives in one function — verifyWebhookSignature — and until this file there was no
 * test of it anywhere in the repo.
 *
 * Two copies of that function exist, because the two deployments cannot share code:
 *   lib/razorpay.ts                        Next.js / node:crypto / timingSafeEqual
 *   supabase/functions/_shared/razorpay.ts Deno    / WebCrypto   / crypto.subtle.verify
 * Both are exercised here with the same table of cases. A rule that holds in one and not the
 * other is a hole, because whichever URL is registered on the Razorpay dashboard is the one
 * that decides whether rent gets credited.
 *
 * THE CASE THAT MATTERS MOST is the first one: with RAZORPAY_WEBHOOK_SECRET unset, a verifier
 * must not quietly return true. It must throw, so the route answers 503 and refuses the
 * delivery. "Assume it's genuine when we can't check" is how a payment system gets emptied.
 *
 * RUN:  NODE_OPTIONS=--conditions=react-server npx tsx scripts/_qa-webhook-signature.mts
 *
 * The --conditions flag is not optional: lib/razorpay.ts imports `server-only`, which throws on
 * import under Node's default resolution and resolves to an empty module under `react-server`.
 * That import is a feature — it is what makes "the key secret reaches a browser" a build error
 * — so the test bends around it rather than asking for it to be removed.
 *
 * Exits 0 when every case passes, 1 otherwise. Touches no network and no database.
 */

import { createHmac } from "node:crypto";
import { readFileSync } from "node:fs";

/* The Edge copy calls Deno.env.get(). Stand one up before anything imports it. */
(globalThis as unknown as { Deno: { env: { get(k: string): string | undefined } } }).Deno = {
  env: { get: (k: string) => process.env[k] },
};

const { verifyWebhookSignature: verifyNode, isWebhookConfigured } = await import("../lib/razorpay");
const { verifyWebhookSignature: verifyEdge } = await import("../supabase/functions/_shared/razorpay");

/** A verifier under test. The Node one is sync, the Edge one is async; await covers both. */
type Verifier = (body: string, header: string | null | undefined) => boolean | Promise<boolean>;

const IMPLS: ReadonlyArray<{ name: string; verify: Verifier }> = [
  { name: "next.js  (node:crypto, timingSafeEqual)", verify: verifyNode },
  { name: "edge fn  (WebCrypto, subtle.verify)", verify: verifyEdge },
];

const WEBHOOK_SECRET = "whsec_test_only_never_a_real_one_9f2c";
const KEY_SECRET = "a_different_secret_entirely_4471";

/** A body shaped like the real thing: a captured ₹5,000 rent payment. */
const BODY = JSON.stringify({
  event: "payment.captured",
  payload: {
    payment: {
      entity: {
        id: "pay_QaBcDeFgHiJkL0",
        order_id: "order_QaBcDeFgHiJkL",
        amount: 500000,
        currency: "INR",
        method: "upi",
        status: "captured",
      },
    },
  },
});

/** Razorpay's documented scheme: lowercase hex of HMAC-SHA256(raw body, webhook secret). */
function sign(body: string, secret: string): string {
  return createHmac("sha256", secret).update(body, "utf8").digest("hex");
}

/** Flip one nibble, keeping the length and the hex alphabet — the near-miss an oracle would find. */
function flipOneNibble(hex: string): string {
  const c = hex[0] === "0" ? "1" : "0";
  return c + hex.slice(1);
}

let pass = 0;
let fail = 0;

function report(impl: string, label: string, ok: boolean, detail: string) {
  if (ok) {
    pass++;
    console.log(`  PASS  ${label}`);
  } else {
    fail++;
    console.log(`  FAIL  ${label}\n          *** ${detail}`);
  }
}

/** Assert a verifier's verdict on one (body, header) pair. */
async function expectVerdict(
  impl: { name: string; verify: Verifier },
  label: string,
  body: string,
  header: string | null | undefined,
  want: boolean,
) {
  let got: boolean | string;
  try {
    got = await impl.verify(body, header);
  } catch (e) {
    got = `threw: ${e instanceof Error ? e.message : String(e)}`;
  }
  report(impl.name, label, got === want, `expected ${want}, got ${JSON.stringify(got)}`);
}

/** Assert a verifier REFUSES to answer at all — the fail-closed contract. */
async function expectThrow(impl: { name: string; verify: Verifier }, label: string) {
  let threw = false;
  let detail = "";
  try {
    const got = await impl.verify(BODY, sign(BODY, WEBHOOK_SECRET));
    detail = `returned ${JSON.stringify(got)} instead of throwing — an unverifiable delivery was answered`;
  } catch (e) {
    threw = true;
    detail = e instanceof Error ? e.message : String(e);
  }
  report(impl.name, label, threw, detail);
}

/* ── 1. NO SECRET: the verifier must refuse to answer, not answer "fine" ─────────────────── */

console.log("\n=== With RAZORPAY_WEBHOOK_SECRET unset, nothing may be accepted ===");
for (const impl of IMPLS) {
  delete process.env.RAZORPAY_WEBHOOK_SECRET;
  await expectThrow(impl, `${impl.name} — refuses when the secret is absent`);

  process.env.RAZORPAY_WEBHOOK_SECRET = "";
  await expectThrow(impl, `${impl.name} — refuses when the secret is an empty string`);

  process.env.RAZORPAY_WEBHOOK_SECRET = "   ";
  await expectThrow(impl, `${impl.name} — refuses when the secret is only whitespace`);
}

delete process.env.RAZORPAY_WEBHOOK_SECRET;
report(
  "next.js",
  "isWebhookConfigured() is false with no secret (this is what makes the route answer 503)",
  isWebhookConfigured() === false,
  `isWebhookConfigured() returned ${isWebhookConfigured()}`,
);
process.env.RAZORPAY_WEBHOOK_SECRET = " " + WEBHOOK_SECRET + " ";
report(
  "next.js",
  "isWebhookConfigured() is true once a secret is set (whitespace trimmed)",
  isWebhookConfigured() === true,
  `isWebhookConfigured() returned ${isWebhookConfigured()}`,
);

/* ── 2. WITH THE SECRET: only the genuine signature over the exact bytes ─────────────────── */

process.env.RAZORPAY_WEBHOOK_SECRET = WEBHOOK_SECRET;
const GOOD = sign(BODY, WEBHOOK_SECRET);

console.log("\n=== With the secret set, only Razorpay's own signature is accepted ===");
for (const impl of IMPLS) {
  const n = impl.name;
  await expectVerdict(impl, `${n} — genuine signature over the exact bytes`, BODY, GOOD, true);
  await expectVerdict(impl, `${n} — same digest in UPPERCASE hex`, BODY, GOOD.toUpperCase(), true);
  await expectVerdict(impl, `${n} — genuine signature with surrounding whitespace`, BODY, `  ${GOOD}\n`, true);

  await expectVerdict(impl, `${n} — one nibble flipped (the byte-at-a-time oracle)`, BODY, flipOneNibble(GOOD), false);
  await expectVerdict(impl, `${n} — header missing entirely`, BODY, null, false);
  await expectVerdict(impl, `${n} — header undefined`, BODY, undefined, false);
  await expectVerdict(impl, `${n} — header empty`, BODY, "", false);
  await expectVerdict(impl, `${n} — header not hex`, BODY, "not-a-signature", false);
  await expectVerdict(impl, `${n} — 63 hex chars (short)`, BODY, GOOD.slice(0, 63), false);
  await expectVerdict(impl, `${n} — 65 hex chars (long)`, BODY, GOOD + "a", false);
  await expectVerdict(impl, `${n} — all zeroes`, BODY, "0".repeat(64), false);

  // The two secrets are different values from different places. Sharing them must not work.
  await expectVerdict(impl, `${n} — signed with the API key secret instead`, BODY, sign(BODY, KEY_SECRET), false);

  // The body is the thing signed. Change it and the old signature must die with it.
  const inflated = BODY.replace('"amount":500000', '"amount":1');
  await expectVerdict(impl, `${n} — amount edited from ₹5,000 to 1 paisa after signing`, inflated, GOOD, false);

  const otherStudent = BODY.replace("order_QaBcDeFgHiJkL", "order_ZzZzZzZzZzZzZ");
  await expectVerdict(impl, `${n} — order id swapped after signing`, otherStudent, GOOD, false);

  // A signature that is genuine — for a different delivery. Replaying it must not work.
  await expectVerdict(impl, `${n} — a real signature for a different body, replayed`, BODY, sign(inflated, WEBHOOK_SECRET), false);

  // JSON.stringify(JSON.parse(raw)) is the classic mistake: same meaning, different bytes.
  const reserialised = JSON.stringify(JSON.parse(BODY), null, 2);
  await expectVerdict(impl, `${n} — re-serialised body (why the RAW bytes must be verified)`, reserialised, GOOD, false);
}

/* ── 3. The comparison itself must not be a string compare ──────────────────────────────── */
//
// A `===` on hex returns at the first differing character, which leaks the length of the
// matching prefix and lets an attacker rebuild a valid signature one nibble at a time. This is
// not observable from the outside in a unit test — timing on a laptop is noise — so it is
// pinned at the source instead: the primitive that must be there, and the compare that must not.

console.log("\n=== The digests are not compared with === ===");
const nodeSrc = readFileSync(new URL("../lib/razorpay.ts", import.meta.url), "utf8");
const edgeSrc = readFileSync(new URL("../supabase/functions/_shared/razorpay.ts", import.meta.url), "utf8");

report(
  "next.js",
  "lib/razorpay.ts compares with timingSafeEqual",
  /timingSafeEqual\s*\(/.test(nodeSrc),
  "timingSafeEqual() is no longer called — a string compare here is a working forgery oracle",
);
report(
  "edge fn",
  "_shared/razorpay.ts compares with crypto.subtle.verify",
  /crypto\.subtle\.verify\s*\(/.test(edgeSrc),
  "crypto.subtle.verify() is no longer called — a string compare here is a working forgery oracle",
);
// The tell of a string compare is a HEX digest: bytes cannot be compared with ===, hex can.
// A `received.length !== expected.length` guard is not that and must not trip this — it is a
// precondition of timingSafeEqual, which throws on mismatched lengths.
for (const [name, src] of [["next.js", nodeSrc], ["edge fn", edgeSrc]] as const) {
  const verifier = src.slice(src.indexOf("export async function verifyWebhookSignature") >= 0
    ? src.indexOf("export async function verifyWebhookSignature")
    : src.indexOf("export function verifyWebhookSignature"));
  const stops = verifier.indexOf("\n}");
  const bodyOfFn = stops > 0 ? verifier.slice(0, stops) : verifier;
  report(
    name,
    `${name} — the expected digest is never rendered as a hex string to be compared`,
    !/\.digest\(\s*["']hex["']\s*\)/.test(bodyOfFn),
    "the expected digest is being turned into hex — the only reason to do that is a === compare",
  );
}

/* ── 4. Shape guard: 64 lowercase-or-uppercase hex, anchored ────────────────────────────── */

console.log("\n=== Ids that become database predicates are shape-checked ===");
const { ORDER_ID_RE, PAYMENT_ID_RE } = await import("../supabase/functions/_shared/razorpay");
const shapes: ReadonlyArray<[RegExp, string, string, boolean]> = [
  [ORDER_ID_RE, "order", "order_QaBcDeFgHiJkL", true],
  [ORDER_ID_RE, "order", "order_'; drop table public.fee_payments; --", false],
  [ORDER_ID_RE, "order", "order_abcdef", true],
  [ORDER_ID_RE, "order", "order_shrt", false],
  [ORDER_ID_RE, "order", "x_order_QaBcDeFgHiJk", false],
  [ORDER_ID_RE, "order", "order_QaBcDeFgHiJkL\norder_second", false],
  [PAYMENT_ID_RE, "payment", "pay_QaBcDeFgHiJkL0", true],
  [PAYMENT_ID_RE, "payment", "pay_' or 1=1 --", false],
  [PAYMENT_ID_RE, "payment", "order_QaBcDeFgHiJkL", false],
];
for (const [re, kind, value, want] of shapes) {
  const got = re.test(value);
  report("shared", `${kind} id ${JSON.stringify(value).slice(0, 46)} → ${want ? "accepted" : "refused"}`, got === want, `regex said ${got}`);
}

console.log(`\n═══ WEBHOOK SIGNATURE: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail ? 1 : 0);
