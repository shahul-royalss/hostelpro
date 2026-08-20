// Verify /super-admin/security renders in a DEPLOYED environment.
//
// The super admin is in MFA_REQUIRED_ROLES, so reaching the page requires a genuine aal2
// session. This enrols a temporary TOTP factor, steps up, checks the page, then unenrols -
// leaving the account exactly as it was found, so the operator's own enrolment is untouched.
//
//   node scripts/_qa-security-console.mjs [baseUrl]
import { createServerClient } from "@supabase/ssr";
import crypto from "node:crypto";
import fs from "node:fs";

const BASE = process.argv[2] ?? "https://hostelpro-three.vercel.app";
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
  .filter((l) => l && !l.startsWith("#") && l.includes("="))
  .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }));

const EMAIL = env.SUPER_ADMIN_EMAIL;
const PASSWORD = env.SUPER_ADMIN_PASSWORD;
if (!EMAIL || !PASSWORD) { console.error("SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD not set in .env.local"); process.exit(1); }

function b32(s) {
  const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of s.replace(/=+$/, "").toUpperCase()) { const v = A.indexOf(c); if (v >= 0) bits += v.toString(2).padStart(5, "0"); }
  const out = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(out);
}
function totp(sec) {
  const ctr = Buffer.alloc(8);
  ctr.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 1000 / 30)));
  const h = crypto.createHmac("sha1", b32(sec)).update(ctr).digest();
  const o = h[h.length - 1] & 0xf;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1000000).padStart(6, "0");
}

let pass = 0, fail = 0;
const ok = (c, m) => { console.log(`  ${c ? "PASS" : "FAIL"}  ${m}`); c ? pass++ : fail++; };

const jar = new Map();
const sb = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  cookies: {
    getAll: () => [...jar].map(([name, value]) => ({ name, value })),
    setAll: (cs) => cs.forEach((c) => jar.set(c.name, c.value)),
  },
});
const cookie = () => [...jar].map(([n, v]) => `${n}=${v}`).join("; ");
const get = async (path) => {
  const res = await fetch(`${BASE}${path}`, { headers: { cookie: cookie() }, redirect: "manual" });
  return { status: res.status, location: res.headers.get("location"), body: res.status === 200 ? await res.text() : "" };
};

console.log(`\ntarget: ${BASE}\n`);

const { error: le } = await sb.auth.signInWithPassword({ email: EMAIL, password: PASSWORD });
if (le) { console.error("login failed:", le.message); process.exit(1); }

// aal1 must NOT reach the console
const before = await get("/super-admin/security");
ok(before.status === 307 && (before.location ?? "").includes("/security/mfa"),
   `without a factor the super admin is sent to enrol (${before.status} -> ${before.location ?? "-"})`);

const { data: en, error: ee } = await sb.auth.mfa.enroll({ factorType: "totp", friendlyName: `qa-console-${Date.now()}` });
if (ee) { console.error("enroll failed:", ee.message); process.exit(1); }
const factorId = en.id;

try {
  const { data: ch } = await sb.auth.mfa.challenge({ factorId });
  const { error: ve } = await sb.auth.mfa.verify({ factorId, challengeId: ch.id, code: totp(en.totp.secret) });
  ok(!ve, `stepped up to aal2${ve ? `: ${ve.message}` : ""}`);

  const page = await get("/super-admin/security");
  ok(page.status === 200, `/super-admin/security renders for an aal2 super admin (${page.status})`);
  ok(/Security/.test(page.body) && /Audit trail/.test(page.body),
     "page contains the Alerts + Audit trail console");
  ok(/Alerts are raised automatically|Severity|What happened/.test(page.body),
     "alerts section rendered (empty-state or table)");

  // a role that is not the super admin still cannot reach it, even at aal2
  const jar2 = new Map();
  const sb2 = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: { getAll: () => [...jar2].map(([name, value]) => ({ name, value })), setAll: (cs) => cs.forEach((c) => jar2.set(c.name, c.value)) },
  });
  await sb2.auth.signInWithPassword({ email: "warden@demo.hostelpro.app", password: "Warden@12345" });
  const asWarden = await fetch(`${BASE}/super-admin/security`, {
    headers: { cookie: [...jar2].map(([n, v]) => `${n}=${v}`).join("; ") }, redirect: "manual",
  });
  ok(asWarden.status !== 200, `warden cannot reach the security console (${asWarden.status})`);
} finally {
  const { error: ue } = await sb.auth.mfa.unenroll({ factorId });
  ok(!ue, `temporary factor removed - account left as found${ue ? `: ${ue.message}` : ""}`);
}

console.log(`\n═══ RESULT: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail ? 1 : 0);
