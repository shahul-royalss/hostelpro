#!/usr/bin/env node
/**
 * Reduce the project to a single super-admin account and nothing else.
 *
 *   node scripts/wipe-to-super-admin.mjs                      # DRY RUN — prints the plan
 *   node scripts/wipe-to-super-admin.mjs --execute --confirm <project-ref>
 *
 * THIS DELETES EVERY TENANT. Hostels, staff, residents, fee history, complaints,
 * leaves, visitors, payments. It is the "hand this to a customer as a blank slate"
 * button, not a cleanup utility.
 *
 * Deliberately refuses unless BOTH --execute and a hand-typed --confirm <ref> matching
 * the project it resolved are present, for the same reason restore-db.mjs does: typing
 * the ref is the step that makes it impossible to wipe the wrong project by re-running
 * a shell line you forgot to edit.
 *
 * WHY THE ADMIN API AND NOT SQL. Deleting rows out of auth.users by hand leaves GoTrue's
 * own bookkeeping behind — sessions, identities, refresh tokens, MFA factors. The Admin
 * API is the supported path and cleans all of it up.
 *
 * ORDERING. hostels.owner_user_id and users.hostel_id are plain foreign keys with no
 * ON DELETE clause, so the tenant graph has to be unhooked before either side will go:
 *   1. null out users.hostel_id      (users_update_guard exempts the service role)
 *   2. delete hostels                (cascades floors → rooms → beds → students →
 *                                     fee_payments, complaints, leaves, visitors, tasks,
 *                                     announcements, menus, subscriptions, payment_intents)
 *   3. delete every auth user except the super admin (cascades public.users)
 *
 * Take a backup first: node scripts/backup-db.mjs --strict
 */
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";

const env = Object.fromEntries(
  fs.readFileSync(".env.local", "utf8").split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#") && l.includes("="))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }),
);

const URL_ = (env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
const KEY = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !KEY) throw new Error("NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
const REF = new URL(URL_).hostname.split(".")[0];

const args = process.argv.slice(2);
const EXECUTE = args.includes("--execute");
const CONFIRM = args[args.indexOf("--confirm") + 1];

const admin = createClient(URL_, KEY, { auth: { persistSession: false } });

async function main() {
  const { data: list, error: le } = await admin.auth.admin.listUsers({ perPage: 1000 });
  if (le) throw new Error(`listUsers: ${le.message}`);

  const { data: profiles, error: pe } = await admin.from("users").select("id, email, role, full_name");
  if (pe) throw new Error(`users: ${pe.message}`);

  const supers = profiles.filter((p) => p.role === "super_admin");
  if (supers.length !== 1) {
    throw new Error(`Expected exactly one super_admin, found ${supers.length}. Refusing to wipe.`);
  }
  const su = supers[0];

  const byRole = profiles.reduce((a, p) => ((a[p.role] = (a[p.role] ?? 0) + 1), a), {});
  const doomedAuth = list.users.filter((u) => u.id !== su.id);

  const counts = {};
  for (const t of ["hostels", "students", "fee_payments", "payment_intents", "complaints", "leaves", "visitors", "tasks", "announcements", "subscriptions"]) {
    const { count } = await admin.from(t).select("*", { count: "exact", head: true });
    counts[t] = count ?? 0;
  }

  console.log(`\n=== wipe-to-super-admin ===`);
  console.log(`  project        ${REF}`);
  console.log(`  KEEPING        ${su.email}  (${su.full_name})`);
  console.log(`  deleting       ${doomedAuth.length} auth account(s)`);
  console.log(`  profiles       ${JSON.stringify(byRole)}`);
  console.log(`  tenant data    ${Object.entries(counts).map(([k, v]) => `${k}=${v}`).join("  ")}`);

  const armed = EXECUTE && CONFIRM === REF;
  if (!EXECUTE) {
    console.log(`\n  DRY RUN — nothing was changed.`);
    console.log(`  To actually wipe:  node scripts/wipe-to-super-admin.mjs --execute --confirm ${REF}\n`);
    return 0;
  }
  if (!armed) {
    console.error(`\n  x REFUSING: --confirm was ${CONFIRM === undefined ? "not given" : `'${CONFIRM}'`}, project is '${REF}'.\n`);
    return 2;
  }

  // 1. unhook profiles from their hostel so the hostel rows can go
  const { error: e1 } = await admin.from("users").update({ hostel_id: null }).neq("id", su.id);
  if (e1) throw new Error(`unhook users.hostel_id: ${e1.message}`);
  console.log(`\n  . unhooked ${profiles.length - 1} profile(s) from their hostel`);

  // 2. hostels — this is the cascade that removes the bulk of the data
  const { error: e2 } = await admin.from("hostels").delete().neq("id", "00000000-0000-0000-0000-000000000000");
  if (e2) throw new Error(`delete hostels: ${e2.message}`);
  console.log(`  . deleted ${counts.hostels} hostel(s) and everything cascading from them`);

  // 3. the accounts themselves, through GoTrue so sessions/identities/factors go too
  let ok = 0, failed = 0;
  for (const u of doomedAuth) {
    const { error } = await admin.auth.admin.deleteUser(u.id);
    if (error) { failed++; console.error(`    ! ${u.email}: ${error.message}`); } else ok++;
  }
  console.log(`  . deleted ${ok} auth account(s)${failed ? `, ${failed} FAILED` : ""}`);

  const after = {};
  for (const t of ["users", "hostels", "students", "fee_payments", "payment_intents"]) {
    const { count } = await admin.from(t).select("*", { count: "exact", head: true });
    after[t] = count ?? 0;
  }
  const { data: rest } = await admin.auth.admin.listUsers({ perPage: 1000 });
  console.log(`\n  remaining      ${Object.entries(after).map(([k, v]) => `${k}=${v}`).join("  ")}  auth=${rest.users.length}`);
  console.log(`  survivor       ${rest.users.map((u) => u.email).join(", ")}\n`);
  return failed ? 1 : 0;
}

main().then((c) => process.exit(c)).catch((e) => { console.error(`\n  x ${e.message}\n`); process.exit(1); });
