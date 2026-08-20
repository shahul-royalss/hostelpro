#!/usr/bin/env node
/**
 * Prove a backup is restorable instead of assuming it.
 *
 *   node scripts/verify-backup.mjs backups/hostelpro-<ref>-<ts>.hpb
 *   node scripts/verify-backup.mjs <file> --max-age-hours 26 --min-rows 100
 *   node scripts/verify-backup.mjs --latest            # newest file in backups/
 *
 * A backup job that only checks "did the file get written" catches nothing. The
 * failure modes that actually bite are: the key does not decrypt it, the dump ran
 * against an empty or wrong project, a table silently returned zero rows, or the
 * snapshot has dangling foreign keys and therefore cannot be inserted back. This
 * script decrypts the file and asserts against all four.
 *
 * Exits non-zero on any failure, so CI can gate on it.
 *
 * Env: BACKUP_ENCRYPTION_KEY (same key the backup was sealed with).
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { CORE_TABLES, EXPECTED_TABLES, FORMAT, FORMAT_VERSION, loadEnv, openBackup, resolveEncryptionKey } from "./backup-db.mjs";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Foreign keys worth asserting, as [table, column, referencedTable]. Transcribed
 * from db/schema.sql. Null values are skipped (all of these columns are nullable
 * or their parent row is guaranteed by an earlier check). A violation here means
 * the dump captured a child whose parent it never read — the snapshot is torn and
 * the restore would abort partway, so it is a hard failure, not a warning.
 */
const FK_CHECKS = [
  ["users", "hostel_id", "hostels"],
  ["hostels", "owner_user_id", "users"],
  ["subscriptions", "hostel_id", "hostels"],
  ["subscriptions", "owner_user_id", "users"],
  ["floors", "hostel_id", "hostels"],
  ["rooms", "hostel_id", "hostels"],
  ["rooms", "floor_id", "floors"],
  ["students", "hostel_id", "hostels"],
  ["students", "user_id", "users"],
  ["students", "room_id", "rooms"],
  ["students", "bed_id", "beds"],
  ["beds", "hostel_id", "hostels"],
  ["beds", "room_id", "rooms"],
  ["beds", "student_id", "students"],
  ["fee_payments", "hostel_id", "hostels"],
  ["fee_payments", "student_id", "students"],
  ["fee_payments", "recorded_by", "users"],
  ["expenses", "hostel_id", "hostels"],
  ["expenses", "uploaded_by", "users"],
  ["revenues", "hostel_id", "hostels"],
  ["revenues", "uploaded_by", "users"],
  ["complaints", "hostel_id", "hostels"],
  ["complaints", "student_id", "students"],
  ["complaint_events", "hostel_id", "hostels"],
  ["complaint_events", "complaint_id", "complaints"],
  ["complaint_events", "actor_user_id", "users"],
  ["leaves", "hostel_id", "hostels"],
  ["leaves", "student_id", "students"],
  ["visitors", "hostel_id", "hostels"],
  ["visitors", "student_id", "students"],
  ["tasks", "hostel_id", "hostels"],
  ["tasks", "assigned_to", "users"],
  ["tasks", "created_by", "users"],
  ["announcements", "hostel_id", "hostels"],
  ["announcements", "author_user_id", "users"],
  ["menus", "hostel_id", "hostels"],
  ["notifications", "hostel_id", "hostels"],
  ["notifications", "user_id", "users"],
];

function parseArgs(argv) {
  const a = { file: null, latest: false, dir: path.join(REPO_ROOT, "backups"), maxAgeHours: null, minRows: 1, expect: null, quiet: false };
  for (let i = 0; i < argv.length; i++) {
    const v = argv[i];
    if (v === "--latest") a.latest = true;
    else if (v === "--dir") a.dir = argv[++i];
    else if (v === "--max-age-hours") a.maxAgeHours = Number(argv[++i]);
    else if (v === "--min-rows") a.minRows = Number(argv[++i]);
    else if (v === "--expect-tables") a.expect = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
    else if (v === "--quiet") a.quiet = true;
    else if (v === "--help" || v === "-h") a.help = true;
    else if (!v.startsWith("-") && !a.file) a.file = v;
    else throw new Error(`unknown argument: ${v}`);
  }
  return a;
}

function newestIn(dir) {
  if (!fs.existsSync(dir)) throw new Error(`no backup directory at ${dir}`);
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".hpb"))
    .map((f) => path.join(dir, f))
    .sort((x, y) => fs.statSync(y).mtimeMs - fs.statSync(x).mtimeMs);
  if (!files.length) throw new Error(`no .hpb files in ${dir}`);
  return files[0];
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log("usage: node scripts/verify-backup.mjs <file.hpb | --latest [--dir DIR]> [--max-age-hours H] [--min-rows N] [--expect-tables a,b]");
    return 0;
  }
  const file = args.file ?? (args.latest ? newestIn(args.dir) : null);
  if (!file) throw new Error("give a backup file path, or --latest");
  if (!fs.existsSync(file)) throw new Error(`no such file: ${file}`);

  const key = resolveEncryptionKey(loadEnv());
  const log = args.quiet ? () => {} : (...m) => console.log(...m);

  let fails = 0;
  const fail = (msg) => {
    fails++;
    console.log(`  x FAIL  ${msg}`);
  };
  const ok = (msg) => log(`  . ${msg}`);

  const stat = fs.statSync(file);
  log(`\n=== verify ${path.basename(file)} (${stat.size} bytes) ===`);

  /* 1. envelope, digest and authenticated decryption — throws if any of these fail */
  const { header, payload } = openBackup(fs.readFileSync(file), key);
  ok(`envelope ok: ${header.cipher}, gzip, sha256 ${header.ciphertextSha256.slice(0, 16)}…`);
  ok(`decrypted and authenticated (GCM tag verified against header AAD)`);

  /* 2. identity */
  if (payload?.meta?.format !== FORMAT) fail(`payload format is '${payload?.meta?.format}', expected '${FORMAT}'`);
  if (payload?.meta?.version !== FORMAT_VERSION) fail(`payload version ${payload?.meta?.version}, expected ${FORMAT_VERSION}`);
  if (payload?.meta?.project !== header.project) fail(`project mismatch: header '${header.project}' vs payload '${payload?.meta?.project}'`);
  if (payload?.meta?.partial) fail(`this backup was taken with --tables and is NOT complete`);
  else ok(`identity ok: project ${payload.meta.project}, taken ${payload.meta.createdAt}`);

  /* 3. freshness */
  const ageH = (Date.now() - Date.parse(payload.meta.createdAt)) / 3_600_000;
  if (Number.isFinite(args.maxAgeHours)) {
    if (!(ageH <= args.maxAgeHours)) fail(`backup is ${ageH.toFixed(1)}h old, limit is ${args.maxAgeHours}h`);
    else ok(`freshness ok: ${ageH.toFixed(1)}h old (limit ${args.maxAgeHours}h)`);
  } else {
    ok(`age ${ageH.toFixed(1)}h`);
  }

  /* 4. every expected table is present */
  const expect = args.expect ?? EXPECTED_TABLES;
  const tables = payload.tables ?? {};
  for (const t of expect) if (!(t in tables)) fail(`table '${t}' is missing from the backup`);
  const extra = Object.keys(tables).filter((t) => !expect.includes(t));
  if (extra.length) log(`  ! note  backup also contains un-manifested table(s): ${extra.join(", ")}`);
  if (expect.every((t) => t in tables)) ok(`all ${expect.length} expected tables present`);

  /* 5. structure and counts, per table */
  const ids = new Map();
  let total = 0;
  for (const [t, block] of Object.entries(tables)) {
    if (!Array.isArray(block?.rows)) {
      fail(`table '${t}' has no rows array`);
      continue;
    }
    const rows = block.rows;
    total += rows.length;
    if (block.rowCount !== rows.length) fail(`table '${t}' declares ${block.rowCount} rows but carries ${rows.length}`);

    const bad = rows.findIndex((r) => r === null || typeof r !== "object" || Array.isArray(r));
    if (bad !== -1) fail(`table '${t}' row ${bad} is not an object`);

    if (rows.length && "id" in rows[0]) {
      const seen = new Set();
      let dupes = 0, nulls = 0;
      for (const r of rows) {
        if (r.id === null || r.id === undefined) nulls++;
        else if (seen.has(String(r.id))) dupes++;
        else seen.add(String(r.id));
      }
      ids.set(t, seen);
      if (nulls) fail(`table '${t}' has ${nulls} row(s) with a null id`);
      // Duplicate ids mean the paged read overlapped — the page window shifted under us.
      if (dupes) fail(`table '${t}' has ${dupes} duplicate id(s) — the paged read was not stable`);
    } else {
      ids.set(t, new Set());
    }

    // Column shape: every row of a table should agree on its keys. A row missing a
    // column is how a partially-projected select silently loses data.
    if (rows.length > 1) {
      const shape = Object.keys(rows[0]).sort().join(",");
      const odd = rows.findIndex((r) => Object.keys(r).sort().join(",") !== shape);
      if (odd !== -1) fail(`table '${t}' row ${odd} has a different column set than row 0`);
    }
    log(`  . ${t.padEnd(18)} ${String(rows.length).padStart(7)} row(s)${rows.length ? `  ${Object.keys(rows[0]).length} cols` : ""}`);
  }
  if (payload.meta.rowCount !== total) fail(`meta.rowCount is ${payload.meta.rowCount} but the tables carry ${total} rows`);
  if (total < args.minRows) fail(`backup carries ${total} rows, expected at least ${args.minRows}`);

  /* 6. a backup of an empty database looks identical to a successful one */
  for (const t of CORE_TABLES) {
    if (!(t in tables)) continue;
    if (tables[t].rows.length === 0) fail(`core table '${t}' is EMPTY — the dump probably ran against the wrong project or without a service-role key`);
  }
  if (CORE_TABLES.every((t) => !(t in tables) || tables[t].rows.length > 0)) ok(`core tables non-empty (${CORE_TABLES.join(", ")})`);

  /* 7. auth directory, and the FK public.users.id -> auth.users.id that a restore depends on */
  const authRows = payload.authUsers?.rows;
  if (!Array.isArray(authRows)) fail(`authUsers block is missing`);
  else {
    if (payload.authUsers.rowCount !== authRows.length) fail(`authUsers declares ${payload.authUsers.rowCount} but carries ${authRows.length}`);
    const authIds = new Set(authRows.map((u) => u.id));
    const leaked = authRows.find((u) => Object.keys(u).some((k) => /password|secret|token|hash/i.test(k)));
    if (leaked) fail(`an auth user record contains a credential-shaped field — the backup must never carry secrets`);
    const orphans = (tables.users?.rows ?? []).filter((u) => !authIds.has(u.id));
    if (orphans.length) fail(`${orphans.length} public.users row(s) have no matching auth account — restore would violate users.id -> auth.users(id)`);
    else ok(`auth directory ok: ${authRows.length} account(s), every public.users row has one`);
    const mfa = authRows.reduce((n, u) => n + (u.factors?.length ?? 0), 0);
    log(`  . ${"auth.users".padEnd(18)} ${String(authRows.length).padStart(7)} account(s)  ${mfa} MFA factor(s) recorded (secrets NOT recoverable)`);
  }

  /* 8. referential integrity of the snapshot itself */
  let fkViolations = 0;
  for (const [t, col, target] of FK_CHECKS) {
    const rows = tables[t]?.rows;
    const parent = ids.get(target);
    if (!rows || !parent) continue;
    let n = 0;
    for (const r of rows) {
      const v = r[col];
      if (v === null || v === undefined) continue;
      if (!parent.has(String(v))) n++;
    }
    if (n) {
      fkViolations += n;
      fail(`${n} row(s) in '${t}' reference a '${target}' that is not in this backup (${t}.${col})`);
    }
  }
  if (fkViolations === 0) ok(`referential integrity ok across ${FK_CHECKS.length} foreign keys — this snapshot can be inserted back`);
  else console.log(`          a torn snapshot: rows changed between table reads. Re-run the backup; if it repeats, the FK map in this script is stale.`);

  console.log(
    fails === 0
      ? `\n  RESTORABLE  ${total} rows across ${Object.keys(tables).length} tables + ${authRows?.length ?? 0} accounts verified\n`
      : `\n  x ${fails} CHECK(S) FAILED — do not rely on this backup\n`,
  );
  return fails === 0 ? 0 : 1;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main()
    .then((code) => process.exit(code))
    .catch((e) => {
      console.error(`\n  x VERIFY FAILED  ${e.message}\n`);
      process.exit(1);
    });
}
