// Route + authorization smoke test against a DEPLOYED environment (checklist §36: test the
// production-like environment, not only localhost). Every role must reach its own pages and
// be redirected away from every other role's pages.
//
//   node scripts/_qa-prod-authz.mjs [baseUrl]     (default: production)
import { createServerClient } from "@supabase/ssr";
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

async function cookieFor(email, password) {
  const jar = new Map();
  const s = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: { getAll: () => [...jar].map(([name, value]) => ({ name, value })), setAll: (cs) => cs.forEach((c) => jar.set(c.name, c.value)) },
  });
  const { error } = await s.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`login ${email}: ${error.message}`);
  return [...jar].map(([n, v]) => `${n}=${v}`).join("; ");
}
const status = async (cookie, path) =>
  (await fetch(`${BASE}${path}`, { headers: { cookie }, redirect: "manual" })).status;

let pass = 0, fail = 0;
const cookies = {};
console.log(`\ntarget: ${BASE}\n`);
for (const [role, [email, password]] of Object.entries(ACCOUNTS)) cookies[role] = await cookieFor(email, password);

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
console.log(`\n═══ RESULT: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail ? 1 : 0);
