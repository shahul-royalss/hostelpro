#!/usr/bin/env node
/**
 * Restore a NIVORA logical backup into a target Supabase project.
 *
 *   node scripts/restore-db.mjs <file.hpb>                       # DRY RUN (default)
 *   node scripts/restore-db.mjs <file.hpb> --execute --confirm-overwrite <project-ref>
 *   node scripts/restore-db.mjs <file.hpb> --execute --confirm-overwrite <ref> --truncate
 *   node scripts/restore-db.mjs <file.hpb> --execute --confirm-overwrite <ref> --recreate-auth-users
 *
 * THIS OVERWRITES DATA. It therefore refuses to write unless BOTH:
 *   --execute                       is present, and
 *   --confirm-overwrite <ref>       exactly matches the project ref it resolved
 *                                   from the target URL.
 * Typing the ref by hand is the point: it is impossible to restore into the wrong
 * project by re-running a shell line whose --target you forgot to change.
 *
 * The default target is RESTORE_SUPABASE_URL / RESTORE_SUPABASE_SERVICE_ROLE_KEY.
 * It falls back to the app's own NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
 * — which is production — and says so loudly when it does.
 *
 * ORDERING
 * Rows go in parents-first (RESTORE_ORDER in backup-db.mjs). Two FK cycles in the
 * schema make a single pass impossible:
 *   users.hostel_id -> hostels.owner_user_id -> users
 *   students.bed_id -> beds.student_id       -> students
 * Those two columns are stripped on insert and patched afterwards.
 *
 * Env: BACKUP_ENCRYPTION_KEY, plus the target URL/key pair above.
 */
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { RESTORE_ORDER, SEQUENCE_TABLES, loadEnv, openBackup, projectRef, resolveEncryptionKey } from "./backup-db.mjs";

const BATCH = 500;

function parseArgs(argv) {
  const a = {
    file: null,
    execute: false,
    confirm: null,
    truncate: false,
    recreateAuth: false,
    tables: null,
    targetUrl: null,
    targetKey: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const v = argv[i];
    if (v === "--execute") a.execute = true;
    else if (v === "--confirm-overwrite") a.confirm = argv[++i];
    else if (v === "--truncate") a.truncate = true;
    else if (v === "--recreate-auth-users") a.recreateAuth = true;
    else if (v === "--tables") a.tables = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
    else if (v === "--target-url") a.targetUrl = argv[++i];
    else if (v === "--target-key-env") a.targetKey = argv[++i]; // name of an env var, never a value
    else if (v === "--help" || v === "-h") a.help = true;
    else if (!v.startsWith("-") && !a.file) a.file = v;
    else throw new Error(`unknown argument: ${v}`);
  }
  return a;
}

const chunk = (arr, n) => {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
};

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.file) {
    console.log(
      "usage: node scripts/restore-db.mjs <file.hpb> [--execute --confirm-overwrite REF]\n" +
        "                                   [--truncate] [--recreate-auth-users] [--tables a,b]\n" +
        "                                   [--target-url URL] [--target-key-env ENV_NAME]\n\n" +
        "Without --execute this is a dry run: it reads the target and prints the plan, writing nothing.",
    );
    return args.help ? 0 : 1;
  }
  if (!fs.existsSync(args.file)) throw new Error(`no such file: ${args.file}`);

  const env = loadEnv();
  const key = resolveEncryptionKey(env);

  /* ── resolve the target, loudly ─────────────────────────────────────── */
  const usingFallback = !args.targetUrl && !env.RESTORE_SUPABASE_URL;
  const url = (args.targetUrl || env.RESTORE_SUPABASE_URL || env.NEXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL || "").replace(/\/+$/, "");
  const svcName = args.targetKey || (env.RESTORE_SUPABASE_SERVICE_ROLE_KEY ? "RESTORE_SUPABASE_SERVICE_ROLE_KEY" : "SUPABASE_SERVICE_ROLE_KEY");
  const svc = env[svcName];
  if (!url) throw new Error("no target: set RESTORE_SUPABASE_URL or pass --target-url");
  if (!svc) throw new Error(`no target key: ${svcName} is not set`);
  // Never send the app's own service-role key to a host someone typed on the command
  // line. --target-url without a matching key would do exactly that, handing the
  // production key to whatever answers at that address.
  if (args.targetUrl && svcName === "SUPABASE_SERVICE_ROLE_KEY") {
    throw new Error(
      "--target-url was given but the only key available is SUPABASE_SERVICE_ROLE_KEY (the app's own).\n" +
        "  Refusing to send the production service-role key to a hand-typed host.\n" +
        "  Set RESTORE_SUPABASE_SERVICE_ROLE_KEY to the target's key, or name one with --target-key-env.",
    );
  }
  const targetRef = projectRef(url);

  /* ── open the backup ────────────────────────────────────────────────── */
  // openBackup() verifies the GCM auth tag and the sha256 before returning, so the header
  // itself is not needed here — a tampered or wrong-key file throws rather than reaching this.
  const { payload } = openBackup(fs.readFileSync(args.file), key);
  const sourceRef = payload.meta.project;
  const tables = payload.tables ?? {};
  const authRows = payload.authUsers?.rows ?? [];

  console.log(`\n=== NIVORA restore ===`);
  console.log(`  backup   ${args.file}`);
  console.log(`  taken    ${payload.meta.createdAt}  from project ${sourceRef}`);
  console.log(`  carries  ${payload.meta.rowCount} row(s) across ${Object.keys(tables).length} table(s), ${authRows.length} account(s)`);
  console.log(`  target   ${targetRef}  (key from ${svcName})`);
  if (payload.meta.partial) console.log(`  !! this backup is PARTIAL (taken with --tables)`);
  if (usingFallback) {
    console.log(`\n  !! RESTORE_SUPABASE_URL is not set, so the target fell back to the APP'S OWN project.`);
    console.log(`     If ${targetRef} is production, this will overwrite live data.`);
  }
  if (targetRef === sourceRef) console.log(`  !! target is the SAME project this backup came from — this is an in-place restore.`);

  /* ── the refusal ────────────────────────────────────────────────────── */
  const armed = args.execute && args.confirm === targetRef;
  if (!args.execute) {
    console.log(`\n  DRY RUN — nothing will be written. To actually restore:`);
    console.log(`    node scripts/restore-db.mjs ${args.file} --execute --confirm-overwrite ${targetRef}`);
  } else if (!armed) {
    console.error(
      `\n  x REFUSING TO RUN` +
        `\n    --execute was given but --confirm-overwrite ${args.confirm === null ? "was not" : `was '${args.confirm}'`}, and the target is '${targetRef}'.` +
        `\n    Re-run with:  --execute --confirm-overwrite ${targetRef}\n`,
    );
    return 2;
  }
  if (args.truncate && payload.meta.partial) {
    throw new Error("--truncate with a PARTIAL backup would delete rows this file cannot restore. Refusing.");
  }

  const admin = createClient(url, svc, { auth: { persistSession: false, autoRefreshToken: false } });

  /* ── plan: what is in the target right now ──────────────────────────── */
  const plan = RESTORE_ORDER.filter((s) => (args.tables ? args.tables.includes(s.table) : true)).filter((s) => s.table in tables);
  const unknown = Object.keys(tables).filter((t) => !RESTORE_ORDER.some((s) => s.table === t));
  if (unknown.length) {
    console.log(`\n  !! the backup contains table(s) with no restore position: ${unknown.join(", ")}`);
    console.log(`     They will NOT be restored. Add them to RESTORE_ORDER in scripts/backup-db.mjs (FK order matters).`);
  }

  console.log(`\n  ${"table".padEnd(18)} ${"in backup".padStart(10)} ${"in target".padStart(10)}   action`);
  for (const step of plan) {
    const { count, error } = await admin.from(step.table).select("*", { count: "exact", head: true });
    const have = error ? "err" : count;
    const n = tables[step.table].rows.length;
    const action = args.truncate ? `delete ${have}, insert ${n}` : `upsert ${n} on id`;
    console.log(
      `  ${step.table.padEnd(18)} ${String(n).padStart(10)} ${String(have).padStart(10)}   ${action}` +
        (step.deferred ? `  [${step.deferred.join(",")} patched in pass 2]` : "") +
        (error ? `  (${error.message})` : ""),
    );
  }
  if (args.recreateAuth) console.log(`  ${"auth.users".padEnd(18)} ${String(authRows.length).padStart(10)} ${"-".padStart(10)}   create missing accounts (no password)`);

  if (!armed) {
    console.log(`\n  Dry run complete. Nothing was written.\n`);
    return 0;
  }

  /* ── write ──────────────────────────────────────────────────────────── */
  console.log(`\n  ---- WRITING TO ${targetRef} ----`);
  const problems = [];

  // 0. auth accounts first: public.users.id references auth.users(id), so the
  //    accounts must exist before any application row can land.
  if (args.recreateAuth) {
    let made = 0, existed = 0;
    for (const u of authRows) {
      // `id` is NOT declared on AdminUserAttributes in @supabase/auth-js typings, but GoTrue
      // does honour it — verified empirically against this project: creating a user with a
      // chosen UUID returns that same UUID. This is load-bearing, not cosmetic: public.users.id
      // is an FK to auth.users(id), so if the id were ignored the restore would silently
      // produce a database whose every user row points at a non-existent account. If a future
      // auth-js release stops honouring it, this loop must fail loudly rather than continue.
      const { error } = await admin.auth.admin.createUser({
        id: u.id,
        email: u.email ?? undefined,
        phone: u.phone ?? undefined,
        email_confirm: Boolean(u.email_confirmed_at),
        phone_confirm: Boolean(u.phone_confirmed_at),
        user_metadata: u.user_metadata ?? {},
        app_metadata: u.app_metadata ?? {},
      });
      if (!error) made++;
      else if (/already (been )?registered|already exists|duplicate/i.test(error.message)) existed++;
      else problems.push(`auth.users ${u.id}: ${error.message}`);
      // Guard the assumption above rather than trusting it: if GoTrue ever stops honouring a
      // supplied id, every subsequent public.users insert would fail on its FK with a far more
      // confusing error, halfway through a restore someone is running under pressure.
      if (!error && made === 1) {
        const { data: probe } = await admin.auth.admin.getUserById(u.id);
        if (!probe?.user) {
          throw new Error(
            `auth.users id was not honoured: asked for ${u.id} and it does not exist afterwards. ` +
            `@supabase/auth-js no longer preserves caller-supplied UUIDs, so this restore would ` +
            `break every public.users foreign key. Aborting before any application row is written.`,
          );
        }
      }
    }
    console.log(`  auth.users        created ${made}, already present ${existed}`);
    if (made) console.log(`                    NOTE: created WITHOUT a password. Each user must use "forgot password" before they can sign in.`);
  }

  // 1. delete, children first
  if (args.truncate) {
    for (const step of [...plan].reverse()) {
      const { error } = await admin.from(step.table).delete().not("id", "is", null);
      if (error) problems.push(`delete ${step.table}: ${error.message}`);
      else console.log(`  cleared ${step.table}`);
    }
  }

  // 2. insert, parents first, deferring the cycle columns
  const deferredPatches = [];
  for (const step of plan) {
    const rows = tables[step.table].rows;
    if (!rows.length) {
      console.log(`  ${step.table.padEnd(18)} 0 rows, skipped`);
      continue;
    }
    let payloadRows = rows;
    if (step.deferred?.length) {
      payloadRows = rows.map((r) => {
        const c = { ...r };
        for (const col of step.deferred) delete c[col];
        return c;
      });
      const patches = rows.filter((r) => step.deferred.some((col) => r[col] !== null && r[col] !== undefined));
      if (patches.length) deferredPatches.push({ table: step.table, cols: step.deferred, rows: patches });
    }
    let done = 0;
    for (const part of chunk(payloadRows, BATCH)) {
      const { error } = await admin.from(step.table).upsert(part, { onConflict: "id" });
      if (error) {
        problems.push(`${step.table}: ${error.message}`);
        break;
      }
      done += part.length;
    }
    console.log(`  ${step.table.padEnd(18)} ${String(done).padStart(6)}/${rows.length} row(s)`);
  }

  // 3. pass 2 — the columns that closed an FK cycle
  for (const p of deferredPatches) {
    let n = 0;
    for (const r of p.rows) {
      const patch = {};
      for (const col of p.cols) patch[col] = r[col];
      const { error } = await admin.from(p.table).update(patch).eq("id", r.id);
      if (error) problems.push(`${p.table}.${p.cols.join(",")} (${r.id}): ${error.message}`);
      else n++;
    }
    console.log(`  ${p.table}.${p.cols.join(",")} patched on ${n}/${p.rows.length} row(s)`);
  }

  /* ── what this tool cannot do, stated as work you still have to do ───── */
  console.log(`\n  ---- MANUAL FOLLOW-UP (PostgREST cannot run these) ----`);
  console.log(`  Re-seed the identity sequences, or the next insert collides with a restored id.`);
  console.log(`  Run in the Supabase SQL editor:`);
  for (const t of SEQUENCE_TABLES) {
    if (!(t in tables)) continue;
    console.log(`    select setval(pg_get_serial_sequence('public.${t}','id'), coalesce((select max(id) from public.${t}), 1));`);
  }
  console.log(`\n  Passwords and MFA are NOT in any logical backup:`);
  console.log(`    - every restored account needs a password reset before first sign-in`);
  const mfa = authRows.reduce((n, u) => n + (u.factors?.length ?? 0), 0);
  console.log(`    - ${mfa} MFA factor(s) existed at backup time and must be re-enrolled by their owners`);
  console.log(`  Storage objects and the schema itself are also not in this file — see docs/backup-and-dr.md.`);

  if (problems.length) {
    console.log(`\n  x ${problems.length} problem(s):`);
    for (const p of problems.slice(0, 25)) console.log(`      ${p}`);
    if (problems.length > 25) console.log(`      … and ${problems.length - 25} more`);
    console.log("");
    return 1;
  }
  console.log(`\n  RESTORE COMPLETE into ${targetRef}. Now run scripts/_qa-rls-attack.mjs against it before letting anyone in.\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main()
    .then((code) => process.exit(code))
    .catch((e) => {
      console.error(`\n  x RESTORE FAILED  ${e.message}\n`);
      process.exit(1);
    });
}
