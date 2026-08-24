#!/usr/bin/env node
/**
 * Encrypted logical backup of the NIVORA application database.
 *
 *   node scripts/backup-db.mjs                 # write backups/hostelpro-<ref>-<ts>.hpb
 *   node scripts/backup-db.mjs --strict        # also FAIL if the live table set drifted
 *   node scripts/backup-db.mjs --out /tmp/bk   # choose the output directory
 *   node scripts/backup-db.mjs --tables users,hostels   # subset (debugging only)
 *
 * WHY THIS EXISTS AND NOT pg_dump
 * The Supabase org is on the FREE plan: there is no PITR and no managed scheduled
 * backup, and no direct Postgres password is provisioned for CI. What we *do* have
 * is the service-role key, which reaches every row through PostgREST regardless of
 * RLS. So this is a logical, row-level dump over the REST API. It is strictly less
 * than a physical dump — see docs/backup-and-dr.md for the exact list of what is
 * NOT in here (auth credentials, Storage objects, schema/policies) and how each of
 * those is recovered instead.
 *
 * ENCRYPTION
 * The dump contains every tenant's PII, so it is never written in the clear. The
 * payload is gzipped, then sealed with AES-256-GCM under BACKUP_ENCRYPTION_KEY.
 * The GCM tag is stored in the file header and the header's identity fields are fed
 * in as AAD, so editing the timestamp or the project ref of a backup invalidates it
 * rather than silently producing a plausible-looking file.
 *
 * Reads only. This script never writes to the database.
 *
 * Env (names only — never hardcode values):
 *   NEXT_PUBLIC_SUPABASE_URL | SUPABASE_URL   project REST endpoint
 *   SUPABASE_SERVICE_ROLE_KEY                 service-role key (bypasses RLS)
 *   BACKUP_ENCRYPTION_KEY                     32 bytes: 64 hex chars, or base64 of 32 bytes
 */
import { createClient } from "@supabase/supabase-js";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/* ── the reviewed table manifest ────────────────────────────────────────────
 * The backup itself does NOT use this list — it dumps whatever PostgREST says
 * exists, so a table added tomorrow is still captured tonight. The list is the
 * drift *check*: if live and manifest disagree, someone changed the schema and
 * nobody re-read this file. Under --strict that is a build failure, but only
 * AFTER the backup file has been written, so a drifting schema never costs you
 * the night's data.
 *
 * Verified against the live schema of project nimxvgzscbanhtvgnjll on 2026-08-20
 * via the PostgREST OpenAPI document (20 tables).
 *
 */
export const EXPECTED_TABLES = [
  "announcements",
  "audit_log",
  "beds",
  "complaint_events",
  "complaints",
  "expenses",
  "fee_payments",
  "floors",
  "hostels",
  "leaves",
  "menus",
  "notifications",
  "revenues",
  "rooms",
  "security_alerts",
  "payment_intents",
  "students",
  "subscriptions",
  "tasks",
  "users",
  "visitors",
];

/**
 * Tables that must never be empty in a healthy production backup. An empty
 * `users` or `hostels` means the dump ran against the wrong project, or against
 * a key that could not actually read — both of which look like a successful
 * backup unless something asserts on them. verify-backup.mjs enforces this.
 */
export const CORE_TABLES = ["users", "hostels", "subscriptions", "floors", "rooms", "beds", "students"];

/**
 * Insert order for restore. Reverse it to delete. Derived from the FK graph in
 * db/schema.sql; `deferred` names columns whose FK points at a table that comes
 * LATER, which is unavoidable because the schema has two reference cycles:
 *   users.hostel_id  -> hostels.owner_user_id -> users
 *   students.bed_id  -> beds.student_id       -> students
 * Those columns are stripped on insert and patched in a second pass.
 */
export const RESTORE_ORDER = [
  { table: "users", deferred: ["hostel_id"] },
  { table: "hostels" },
  { table: "subscriptions" },
  { table: "floors" },
  { table: "rooms" },
  { table: "students", deferred: ["bed_id"] },
  { table: "beds" },
  { table: "fee_payments" },
  { table: "expenses" },
  { table: "revenues" },
  { table: "complaints" },
  { table: "complaint_events" },
  { table: "leaves" },
  { table: "visitors" },
  { table: "tasks" },
  { table: "announcements" },
  { table: "menus" },
  { table: "notifications" },
  { table: "payment_intents" },
  { table: "audit_log" },
  { table: "security_alerts" },
];

/** Tables whose id is a bigserial/identity — their sequence must be re-seeded after a restore. */
export const SEQUENCE_TABLES = ["audit_log", "security_alerts"];

export const FILE_MAGIC = Buffer.from("HPB1", "ascii");
export const FORMAT = "hostelpro-logical-backup";
export const FORMAT_VERSION = 1;
const PAGE = 1000;

/* ── env ────────────────────────────────────────────────────────────────── */

/**
 * Real process env wins; `.env.local` fills the gaps. In CI there is no
 * .env.local at all and every value arrives as a GitHub Actions secret.
 * Values are never printed by this script.
 */
export function loadEnv() {
  const out = { ...process.env };
  for (const file of [".env.local", ".env"]) {
    const p = path.join(REPO_ROOT, file);
    if (!fs.existsSync(p)) continue;
    for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
      if (!line || line.trimStart().startsWith("#") || !line.includes("=")) continue;
      const i = line.indexOf("=");
      const k = line.slice(0, i).trim();
      let v = line.slice(i + 1).trim();
      if (v.length > 1 && ((v[0] === '"' && v.endsWith('"')) || (v[0] === "'" && v.endsWith("'")))) v = v.slice(1, -1);
      if (out[k] === undefined || out[k] === "") out[k] = v;
    }
  }
  return out;
}

export function requireEnv(env, names) {
  const url = names.url.map((n) => env[n]).find(Boolean);
  const key = names.key.map((n) => env[n]).find(Boolean);
  if (!url) throw new Error(`missing env: one of ${names.url.join(" / ")}`);
  if (!key) throw new Error(`missing env: one of ${names.key.join(" / ")}`);
  return { url: url.replace(/\/+$/, ""), key };
}

/** Supabase project ref = the first label of the *.supabase.co host. Public, not a secret. */
export function projectRef(url) {
  try {
    return new URL(url).host.split(".")[0];
  } catch {
    return "unknown";
  }
}

/**
 * BACKUP_ENCRYPTION_KEY -> 32 raw bytes. Accepts 64 hex chars or base64-of-32-bytes.
 * Never logs, echoes or includes the key material in an error message.
 */
export function resolveEncryptionKey(env) {
  const raw = String(env.BACKUP_ENCRYPTION_KEY || "").trim();
  if (!raw) {
    throw new Error(
      "BACKUP_ENCRYPTION_KEY is not set. Generate one with:\n" +
        '  node -e "console.log(require(\'node:crypto\').randomBytes(32).toString(\'hex\'))"',
    );
  }
  let key = null;
  if (/^[0-9a-fA-F]{64}$/.test(raw)) key = Buffer.from(raw, "hex");
  else {
    try {
      const b = Buffer.from(raw, "base64");
      if (b.length === 32) key = b;
    } catch {
      /* fall through to the error below */
    }
  }
  if (!key || key.length !== 32) {
    throw new Error("BACKUP_ENCRYPTION_KEY must be exactly 32 bytes — 64 hex characters, or base64 that decodes to 32 bytes.");
  }
  return key;
}

/* ── file envelope ──────────────────────────────────────────────────────────
 *   [4]  magic 'HPB1'
 *   [4]  uint32BE header length
 *   [n]  header JSON (cleartext: format identity, iv, GCM tag, ciphertext digest)
 *   [..] AES-256-GCM ciphertext of gzip(JSON payload)
 *
 * Row counts and table names live INSIDE the ciphertext, not in the header, so
 * possession of the file alone reveals nothing about tenant volumes.
 */

/** Header fields that are authenticated as AAD. Key order is part of the format. */
function aad(core) {
  return Buffer.from(
    JSON.stringify({
      format: core.format,
      version: core.version,
      createdAt: core.createdAt,
      project: core.project,
      cipher: core.cipher,
      compression: core.compression,
    }),
    "utf8",
  );
}

export function sealBackup(payload, key, { createdAt, project }) {
  const core = {
    format: FORMAT,
    version: FORMAT_VERSION,
    createdAt,
    project,
    cipher: "aes-256-gcm",
    compression: "gzip",
  };
  const plain = zlib.gzipSync(Buffer.from(JSON.stringify(payload), "utf8"), { level: 9 });
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  c.setAAD(aad(core));
  const ciphertext = Buffer.concat([c.update(plain), c.final()]);
  const header = {
    ...core,
    iv: iv.toString("base64"),
    authTag: c.getAuthTag().toString("base64"),
    ciphertextBytes: ciphertext.length,
    ciphertextSha256: crypto.createHash("sha256").update(ciphertext).digest("hex"),
  };
  const headerBuf = Buffer.from(JSON.stringify(header), "utf8");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(headerBuf.length, 0);
  return { file: Buffer.concat([FILE_MAGIC, len, headerBuf, ciphertext]), header, plaintextBytes: plain.length };
}

export function readHeader(file) {
  if (file.length < 8 || !file.subarray(0, 4).equals(FILE_MAGIC)) {
    throw new Error("not a NIVORA backup file (bad magic — expected 'HPB1')");
  }
  const headerLen = file.readUInt32BE(4);
  if (headerLen <= 0 || 8 + headerLen > file.length) throw new Error("corrupt backup: header length out of range");
  const header = JSON.parse(file.subarray(8, 8 + headerLen).toString("utf8"));
  return { header, ciphertext: file.subarray(8 + headerLen) };
}

export function openBackup(file, key) {
  const { header, ciphertext } = readHeader(file);
  if (header.format !== FORMAT) throw new Error(`unexpected format '${header.format}'`);
  if (header.version !== FORMAT_VERSION) throw new Error(`unsupported backup version ${header.version} (this tool reads ${FORMAT_VERSION})`);
  if (header.cipher !== "aes-256-gcm") throw new Error(`unsupported cipher '${header.cipher}'`);
  if (header.ciphertextBytes !== ciphertext.length) {
    throw new Error(`truncated backup: header declares ${header.ciphertextBytes} ciphertext bytes, file has ${ciphertext.length}`);
  }
  const digest = crypto.createHash("sha256").update(ciphertext).digest("hex");
  if (digest !== header.ciphertextSha256) throw new Error("ciphertext sha256 mismatch — the file was altered or truncated in transit");

  const d = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(header.iv, "base64"));
  d.setAAD(aad(header));
  d.setAuthTag(Buffer.from(header.authTag, "base64"));
  let plain;
  try {
    plain = Buffer.concat([d.update(ciphertext), d.final()]);
  } catch {
    // GCM gives no detail on failure by design; both causes look identical here.
    throw new Error("decryption failed — wrong BACKUP_ENCRYPTION_KEY, or the file/header was tampered with");
  }
  const payload = JSON.parse(zlib.gunzipSync(plain).toString("utf8"));
  return { header, payload };
}

/* ── discovery + dump ───────────────────────────────────────────────────── */

/**
 * Ask PostgREST what it exposes rather than trusting a hardcoded list. The
 * OpenAPI document's `definitions` are exactly the tables/views reachable with
 * this key, which is exactly what a logical backup can capture.
 */
export async function discoverTables(url, serviceKey) {
  const res = await fetch(`${url}/rest/v1/`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, Accept: "application/openapi+json" },
  });
  if (!res.ok) throw new Error(`schema discovery failed: HTTP ${res.status} from ${url}/rest/v1/`);
  const spec = await res.json();
  const names = Object.keys(spec.definitions || {}).filter((n) => /^[a-z_][a-z0-9_]*$/i.test(n));
  if (names.length === 0) throw new Error("schema discovery returned no tables — is SUPABASE_SERVICE_ROLE_KEY a service-role key?");
  return names.sort();
}

async function dumpTable(admin, table) {
  const rows = [];
  let ordered = true;
  for (let from = 0; ; from += PAGE) {
    let q = admin.from(table).select("*").range(from, from + PAGE - 1);
    if (ordered) q = q.order("id", { ascending: true });
    const { data, error } = await q;
    if (error) {
      // 42703 = undefined column: a table without `id` cannot be page-ordered by it.
      if (ordered && (error.code === "42703" || /column .*id.* does not exist/i.test(error.message))) {
        ordered = false;
        from -= PAGE;
        continue;
      }
      throw new Error(`${table}: ${error.message}`);
    }
    rows.push(...data);
    if (data.length < PAGE) break;
  }
  return { rows, ordered };
}

/**
 * The auth user *directory* — ids, emails, phones, metadata and which MFA factors
 * exist. Deliberately NOT credentials: the Admin API does not return password
 * hashes or factor secrets, and we do not try to reconstruct them. What this buys
 * on restore is the ability to recreate accounts under their ORIGINAL uuids, which
 * public.users.id depends on; users then reset their password and re-enrol MFA.
 */
async function dumpAuthUsers(admin) {
  const out = [];
  for (let page = 1; ; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: PAGE });
    if (error) throw new Error(`auth.users: ${error.message}`);
    for (const u of data.users) {
      out.push({
        id: u.id,
        email: u.email ?? null,
        phone: u.phone ?? null,
        role: u.role ?? null,
        created_at: u.created_at ?? null,
        updated_at: u.updated_at ?? null,
        email_confirmed_at: u.email_confirmed_at ?? null,
        phone_confirmed_at: u.phone_confirmed_at ?? null,
        last_sign_in_at: u.last_sign_in_at ?? null,
        banned_until: u.banned_until ?? null,
        app_metadata: u.app_metadata ?? {},
        user_metadata: u.user_metadata ?? {},
        factors: (u.factors ?? []).map((f) => ({
          id: f.id,
          friendly_name: f.friendly_name ?? null,
          factor_type: f.factor_type ?? null,
          status: f.status ?? null,
          created_at: f.created_at ?? null,
        })),
      });
    }
    if (data.users.length < PAGE) break;
  }
  return out;
}

/* ── main ───────────────────────────────────────────────────────────────── */

function parseArgs(argv) {
  const a = { out: path.join(REPO_ROOT, "backups"), strict: false, tables: null, quiet: false };
  for (let i = 0; i < argv.length; i++) {
    const v = argv[i];
    if (v === "--strict") a.strict = true;
    else if (v === "--quiet") a.quiet = true;
    else if (v === "--out") a.out = argv[++i];
    else if (v === "--tables") a.tables = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
    else if (v === "--help" || v === "-h") a.help = true;
    else throw new Error(`unknown argument: ${v}`);
  }
  return a;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log("usage: node scripts/backup-db.mjs [--out DIR] [--strict] [--tables a,b] [--quiet]");
    return 0;
  }
  const env = loadEnv();
  const { url, key: serviceKey } = requireEnv(env, {
    url: ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"],
    key: ["SUPABASE_SERVICE_ROLE_KEY"],
  });
  const encKey = resolveEncryptionKey(env);
  const ref = projectRef(url);
  const started = Date.now();
  const log = args.quiet ? () => {} : (...m) => console.log(...m);

  log(`\n=== NIVORA logical backup — project ${ref} ===`);

  const live = await discoverTables(url, serviceKey);
  const missing = EXPECTED_TABLES.filter((t) => !live.includes(t)); // in manifest, gone from the DB
  const added = live.filter((t) => !EXPECTED_TABLES.includes(t)); // in the DB, not yet reviewed
  log(`  discovered ${live.length} table(s) via PostgREST`);

  // Dump parents before children. PostgREST gives no cross-table snapshot, so a row
  // inserted mid-dump lands in one table and not another. Parents-first means the
  // worst case is a child that is simply absent (harmless); child-first would leave a
  // row pointing at a parent that was never read, which will not restore. Tables the
  // manifest has never seen go last, so new tables cannot reorder the known graph.
  const known = RESTORE_ORDER.map((s) => s.table);
  const inOrder = [...live].sort((a, b) => {
    const ia = known.indexOf(a), ib = known.indexOf(b);
    return (ia === -1 ? known.length : ia) - (ib === -1 ? known.length : ib) || a.localeCompare(b);
  });
  const tables = args.tables ?? inOrder;
  if (args.tables) log(`  !! --tables given: backing up only ${tables.join(", ")} — NOT a complete backup`);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const dump = {};
  let rowCount = 0;
  for (const t of tables) {
    const { rows, ordered } = await dumpTable(admin, t);
    dump[t] = { rowCount: rows.length, rows };
    rowCount += rows.length;
    log(`  ${t.padEnd(18)} ${String(rows.length).padStart(7)} row(s)${ordered ? "" : "   [unordered — no id column]"}`);
  }

  const authUsers = await dumpAuthUsers(admin);
  log(`  ${"auth.users".padEnd(18)} ${String(authUsers.length).padStart(7)} account(s)  [directory only — no passwords/MFA secrets]`);

  const createdAt = new Date().toISOString();
  const payload = {
    meta: {
      format: FORMAT,
      version: FORMAT_VERSION,
      createdAt,
      project: ref,
      generator: "scripts/backup-db.mjs",
      partial: Boolean(args.tables),
      tableCount: Object.keys(dump).length,
      rowCount,
      authUserCount: authUsers.length,
      discoveredTables: live,
      expectedTables: EXPECTED_TABLES,
      drift: { missing, added },
      durationMs: Date.now() - started,
      notCovered: [
        "auth.users credentials (password hashes, MFA factor secrets, refresh tokens)",
        "Supabase Storage objects",
        "database schema, RLS policies, functions, triggers, roles (see db/schema.sql, db/rls-policies.sql)",
      ],
    },
    tables: dump,
    authUsers: { rowCount: authUsers.length, rows: authUsers },
  };

  const { file, header, plaintextBytes } = sealBackup(payload, encKey, { createdAt, project: ref });

  fs.mkdirSync(args.out, { recursive: true });
  // Self-contained ignore file: a plaintext-equivalent dump must never become
  // committable just because someone points --out at a directory inside the repo.
  const ignore = path.join(args.out, ".gitignore");
  if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, "*\n");

  const stamp = createdAt.replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const outFile = path.join(args.out, `hostelpro-${ref}-${stamp}.hpb`);
  fs.writeFileSync(outFile, file);

  log(
    `\n  wrote ${outFile}` +
      `\n  ${rowCount} row(s) + ${authUsers.length} account(s) | ${plaintextBytes} B gzipped -> ${header.ciphertextBytes} B sealed (aes-256-gcm)` +
      `\n  sha256(ciphertext) ${header.ciphertextSha256}`,
  );

  // The file is on disk before anything below can fail. Drift never costs data.
  let exit = 0;
  if (missing.length || added.length) {
    for (const t of added) console.log(`\n  ! DRIFT  live table '${t}' is not in EXPECTED_TABLES (it IS backed up — add it to the manifest and to db/schema.sql)`);
    for (const t of missing) console.log(`\n  ! DRIFT  expected table '${t}' no longer exists in the database`);
    if (args.strict) {
      console.log(`\n  x FAIL   schema drift, and --strict was given. The backup above is complete and valid; update scripts/backup-db.mjs.`);
      exit = 3;
    }
  } else {
    log(`  table manifest matches the live schema (${EXPECTED_TABLES.length} tables)`);
  }
  // stdout contract for CI: the workflow greps this line to find the artifact.
  console.log(`BACKUP_FILE=${outFile}`);
  return exit;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main()
    .then((code) => process.exit(code))
    .catch((e) => {
      console.error(`\n  x BACKUP FAILED  ${e.message}`);
      process.exit(1);
    });
}
