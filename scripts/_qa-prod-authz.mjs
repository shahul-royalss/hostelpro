// Route + authorization smoke test against a DEPLOYED environment (checklist §36: test the
// production-like environment, not only localhost). Every role must reach its own pages and
// be redirected away from every other role's pages.
//
//   node scripts/_qa-prod-authz.mjs [baseUrl]     (default: production)
import { createServerClient } from "@supabase/ssr";
import crypto from "node:crypto";
import fs from "node:fs";

const BASE = process.argv[2] ?? "https://hostelpro-three.vercel.app";
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
  .filter((l) => l && !l.startsWith("#") && l.includes("="))
  .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }));

// The four demo-tenant passwords are seeded constants (db/seed.ts) and are printed in the
// credentials table for the client — they are public by design and rotate on every re-seed.
// The SUPER ADMIN password is NOT: it comes from SUPER_ADMIN_PASSWORD in .env.local and is a
// real production secret, so it is read from the environment and never written down here.
const SA_PASSWORD = env.SUPER_ADMIN_PASSWORD;
if (!SA_PASSWORD) {
  console.error("SUPER_ADMIN_PASSWORD is not set in .env.local — cannot test the super admin.");
  process.exit(1);
}
const ACCOUNTS = {
  owner:   ["owner@demo.hostelpro.app", "Owner@12345"],
  manager: ["manager@demo.hostelpro.app", "Manager@12345"],
  warden:  ["warden@demo.hostelpro.app", "Warden@12345"],
  student: ["9000000001@student.hostelpro.local", "Student@12345"],
  admin:   [env.SUPER_ADMIN_EMAIL ?? "admin@hostelpro.app", SA_PASSWORD],
};
const OWN = {
  owner:   ["/owner", "/owner/staff", "/owner/students", "/owner/finance", "/owner/complaints", "/owner/updates"],
  manager: ["/manager", "/manager/expenses", "/manager/tasks", "/manager/menu"],
  warden:  ["/warden", "/warden/fees", "/warden/complaints", "/warden/visitors", "/warden/leaves",
            "/warden/rooms", "/warden/register", "/warden/announcements"],
  student: ["/student", "/student/complaints", "/student/leave", "/student/menu", "/student/room",
            "/student/info", "/student/profile"],
  admin:   ["/super-admin", "/super-admin/hostels", "/super-admin/subscriptions", "/super-admin/create"],
};

// Roles listed in MFA_REQUIRED_ROLES must hold a verified factor before they can reach any
// page. A password-only session is deliberately bounced to /security/mfa, so this suite has
// to step those roles up before it can assert anything about their own routes - otherwise it
// would report the security control as a routing failure.
const MFA_REQUIRED = new Set((env.MFA_REQUIRED_ROLES ?? "").split(",").map((r) => r.trim()).filter(Boolean));

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

async function cookieFor(email, password) {
  const jar = new Map();
  const s = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: { getAll: () => [...jar].map(([name, value]) => ({ name, value })), setAll: (cs) => cs.forEach((c) => jar.set(c.name, c.value)) },
  });
  const { error } = await s.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`login ${email}: ${error.message}`);
  const cookie = () => [...jar].map(([n, v]) => `${n}=${v}`).join("; ");
  return { client: s, cookie };
}
const status = async (cookie, path) =>
  (await fetch(`${BASE}${path}`, { headers: { cookie }, redirect: "manual" })).status;

let pass = 0, fail = 0;
const cookies = {};
console.log(`\ntarget: ${BASE}\n`);
const temporaryFactors = [];
for (const [role, [email, password]] of Object.entries(ACCOUNTS)) {
  const { client, cookie } = await cookieFor(email, password);
  if (MFA_REQUIRED.has(role === "admin" ? "super_admin" : role)) {
    // the gate itself is part of what we are verifying
    const bounced = await fetch(`${BASE}${OWN[role][0]}`, { headers: { cookie: cookie() }, redirect: "manual" });
    const loc = bounced.headers.get("location") ?? "";
    if (bounced.status === 307 && loc.includes("/security/mfa")) {
      console.log(`  PASS  ${role.padEnd(8)} password-only session is bounced to enrol (${loc})`); pass++;
    } else {
      console.log(`  FAIL  ${role.padEnd(8)} *** MFA is required for this role but a password-only session got ${bounced.status}`); fail++;
    }
    const { data: en, error: ee } = await client.auth.mfa.enroll({ factorType: "totp", friendlyName: `qa-authz-${Date.now()}` });
    if (ee) throw new Error(`enroll ${role}: ${ee.message}`);
    const { data: ch } = await client.auth.mfa.challenge({ factorId: en.id });
    const { error: ve } = await client.auth.mfa.verify({ factorId: en.id, challengeId: ch.id, code: totp(en.totp.secret) });
    if (ve) throw new Error(`step-up ${role}: ${ve.message}`);
    temporaryFactors.push({ client, factorId: en.id, role, userId: (await client.auth.getUser()).data.user?.id });
  }
  cookies[role] = cookie();
}

try {
  console.log("=== each role reaches its own pages ===");
  for (const [role, paths] of Object.entries(OWN)) {
    const codes = await Promise.all(paths.map((p) => status(cookies[role], p)));
    const bad = paths.filter((_, i) => codes[i] !== 200);
    if (bad.length === 0) { console.log(`  PASS  ${role.padEnd(8)} ${paths.length} routes 200`); pass++; }
    else { console.log(`  FAIL  ${role.padEnd(8)} ${bad.map((p, i) => `${p}->${codes[paths.indexOf(p)]}`).join(" ")}`); fail++; }
  }

  console.log("\n=== no role reaches another role's pages ===");
  for (const [owner, paths] of Object.entries(OWN)) {
    for (const role of Object.keys(ACCOUNTS)) {
      if (role === owner) continue;
      const codes = await Promise.all(paths.map((p) => status(cookies[role], p)));
      const leaked = paths.filter((_, i) => codes[i] === 200);
      if (leaked.length === 0) { console.log(`  PASS  ${role.padEnd(8)} denied all ${paths.length} ${owner} routes`); pass++; }
      else { console.log(`  FAIL  ${role.padEnd(8)} *** REACHED ${leaked.join(" ")}`); fail++; }
    }
  }
} finally {
  // MUST run even if an assertion above throws. A factor left behind here holds a secret
  // that only this process ever saw, so the account it belongs to is locked out — which is
  // exactly the bug this suite exists to catch, self-inflicted. The service-role fallback
  // matters because unenroll() itself needs aal2, and a session that died mid-run no
  // longer has it.
  if (temporaryFactors.length) console.log("\n=== cleanup ===");
  for (const { client, factorId, role, userId } of temporaryFactors) {
    let { error } = await client.auth.mfa.unenroll({ factorId });
    if (error) {
      const { createClient } = await import("@supabase/supabase-js");
      const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
      ({ error } = await admin.auth.admin.mfa.deleteFactor({ userId, id: factorId }));
    }
    if (error) {
      console.log(`  FAIL  ${role} temporary factor ${factorId} SURVIVED — remove it by hand or that account is locked out: ${error.message}`);
      fail++;
    } else {
      console.log(`  PASS  ${role} temporary factor removed`);
      pass++;
    }
  }
}

console.log(`\n═══ RESULT: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail ? 1 : 0);
