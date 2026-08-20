#!/usr/bin/env node
/**
 * Repeatable security scan — GOD-MODE checklist §2 (secrets), §13 (client bundle),
 * §15 (AI-generated-code / backdoor audit), §22 (dependencies).
 *
 *   node scripts/security-scan.mjs               # working tree + full git history
 *   node scripts/security-scan.mjs --no-history  # skip history (faster, for pre-commit)
 *
 * Exits 1 if any BLOCKER fires, so it can gate CI.
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const args = new Set(process.argv.slice(2));
const SCAN_HISTORY = !args.has("--no-history");
let blockers = 0;
let warnings = 0;

const sh = (cmd) => {
  try {
    return execSync(cmd, { maxBuffer: 1024 * 1024 * 256, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch (e) {
    // npm audit exits non-zero when it finds vulnerabilities — its stdout is still valid.
    return e && typeof e.stdout === "string" ? e.stdout : "";
  }
};
const indent = (s) => s.split("\n").slice(0, 6).map((l) => "      " + l).join("\n");
const block = (title, detail) => { blockers++; console.log(`\n  x BLOCKER  ${title}\n${indent(detail)}`); };
const warn = (title, detail) => { warnings++; console.log(`\n  ! WARN     ${title}\n${indent(detail)}`); };
const ok = (title) => console.log(`  . ${title}`);

/* ── §2 SECRETS ─────────────────────────────────────────────────────────── */
console.log("\n=== 2  SECRETS ===");

// Real credential shapes. The Supabase ANON key is public by design (a browser key
// protected by RLS) so it is not a finding; the service_role key is.
const SECRET_PATTERNS = [
  ["Supabase service_role JWT", /"role"\s*:\s*"service_role"/],
  ["Supabase secret key", /\bsb_secret_[A-Za-z0-9_-]{10,}/],
  ["AWS access key id", /\bAKIA[0-9A-Z]{16}\b/],
  ["Google API key", /\bAIza[0-9A-Za-z_-]{35}\b/],
  ["Stripe secret key", /\bsk_(live|test)_[0-9a-zA-Z]{16,}/],
  ["GitHub token", /\bgh[pousr]_[A-Za-z0-9]{30,}/],
  ["Slack token", /\bxox[baprs]-[0-9A-Za-z-]{10,}/],
  ["Private key block", /-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/],
  // Requires entropy in the value: a purely alphabetic value is a UI label, not a secret.
  ["Hardcoded password assignment", /(password|passwd|pwd)\s*[:=]\s*["'](?=[^"'\s]{8,}["'])(?=[^"'\s]*[0-9])(?=[^"'\s]*[^A-Za-z0-9"'\s])[^"'\s]+["']/i],
];

// Demo-tenant credentials are seeded constants (db/seed.ts), printed in the credentials
// table for the client, and rotate on every re-seed — they are public by design.
//
// NOTE: this list previously also carried the super-admin password value and the
// SUPER_ADMIN_PASSWORD key. That was a real hole: the super-admin password is NOT a demo
// constant - it comes from .env.local - and allowlisting its value blinded this scanner to
// the one secret that actually mattered. Never allowlist a value that appears in .env.local;
// the check below enforces that independently of any pattern or allowlist.
const ALLOW = /Owner@12345|Manager@12345|Warden@12345|Student@12345|ChangeMe!2026|NewPass@2026|AuditPass1|your-default-host|example\.com|placeholder|PASSWORD_MIN_LENGTH|password:\s*["']?\$\{|p_password|passwordStrength/i;

/**
 * Shape-independent leak check: take the ACTUAL secret values out of .env.local and look for
 * them verbatim in tracked files. Regex patterns only catch the shapes someone thought to
 * write down — an array-literal credential pair matched none of them. This catches any shape,
 * because it compares against the real values rather than guessing at their syntax.
 */
function envSecretValues() {
  const out = [];
  for (const file of [".env.local", ".env"]) {
    let raw;
    try { raw = fs.readFileSync(file, "utf8"); } catch { continue; }
    for (const line of raw.split(/\r?\n/)) {
      const t = line.trim();
      if (!t || t.startsWith("#") || !t.includes("=")) continue;
      const i = t.indexOf("=");
      const key = t.slice(0, i).trim();
      const val = t.slice(i + 1).trim().replace(/^["']|["']$/g, "");
      // NEXT_PUBLIC_* is compiled into the browser bundle by definition, so it is not a secret.
      if (key.startsWith("NEXT_PUBLIC_")) continue;
      // Only credential-bearing keys. SUPER_ADMIN_EMAIL / _NAME are identifiers, not
      // secrets, and they legitimately appear in the README and the seed defaults.
      if (!/PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|DSN|PRIVATE/i.test(key)) continue;
      if (val.length < 8) continue;
      out.push({ key, val });
    }
  }
  return out;
}

const tracked = sh("git ls-files")
  .split("\n")
  .filter(Boolean)
  .filter((f) => !/^design-exports\/|^skills\//.test(f));

let treeHits = 0;
for (const f of tracked) {
  let content = "";
  try {
    content = fs.readFileSync(f, "utf8");
  } catch {
    continue;
  }
  content.split("\n").forEach((line, i) => {
    if (ALLOW.test(line)) return;
    for (const [name, re] of SECRET_PATTERNS) {
      if (re.test(line)) {
        block(`${name} in a tracked file`, `${f}:${i + 1}  ${line.trim().slice(0, 110)}`);
        treeHits++;
      }
    }
  });
}
if (!treeHits) ok(`no credentials in ${tracked.length} tracked files`);

// Any real .env value appearing verbatim in a tracked file is a leak, whatever its syntax.
const envSecrets = envSecretValues();
let envLeaks = 0;
for (const f of tracked) {
  let text;
  try { text = fs.readFileSync(f, "utf8"); } catch { continue; }
  for (const { key, val } of envSecrets) {
    if (!text.includes(val)) continue;
    const line = text.split(/\r?\n/).findIndex((l) => l.includes(val)) + 1;
    block(`value of ${key} (.env) is committed in a tracked file`, `${f}:${line}`);
    envLeaks++;
  }
}
if (!envLeaks) ok(`no .env value appears in tracked files (${envSecrets.length} secrets compared)`);

const envTracked = tracked.filter((f) => /(^|\/)\.env($|\.)/.test(f) && !f.endsWith(".env.example"));
if (envTracked.length) block(".env file is tracked by git", envTracked.join("\n"));
else ok(".env files are not tracked");

if (SCAN_HISTORY) {
  const hist = sh("git log --all -p --no-color");
  let histHits = 0;
  for (const [name, re] of SECRET_PATTERNS) {
    const bad = hist.split("\n").filter((l) => l.startsWith("+") && re.test(l) && !ALLOW.test(l));
    if (bad.length) {
      block(`${name} in git history`, bad.join("\n"));
      histHits++;
    }
  }
  // The same shape-independent check, applied to history. A secret removed from HEAD is still
  // disclosed to anyone who can read the repo, so this must not fall silent once HEAD is clean.
  // The only real remedies are rotating the value or rewriting history.
  for (const { key, val } of envSecrets) {
    const bad = hist.split("\n").filter((l) => l.startsWith("+") && l.includes(val));
    if (bad.length) {
      block(`value of ${key} (.env) appears in git history — rotate it`, bad[0].trim().slice(0, 140));
      histHits++;
    }
  }
  if (!histHits) ok(`no credentials in git history (${hist.split("\n").length.toLocaleString()} diff lines scanned)`);
} else {
  ok("git history scan skipped (--no-history)");
}

/* ── §13 CLIENT BUNDLE ──────────────────────────────────────────────────── */
console.log("\n=== 13 CLIENT BUNDLE ===");
if (fs.existsSync(".next/static")) {
  const files = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(js|map)$/.test(e.name)) files.push(p);
    }
  })(".next/static");
  const blob = files.map((f) => { try { return fs.readFileSync(f, "utf8"); } catch { return ""; } }).join("\n");
  let n = 0;
  for (const [name, re] of [
    ["service_role credential", /"role"\s*:\s*"service_role"|sb_secret_/],
    ["SUPER_ADMIN_PASSWORD", /SUPER_ADMIN_PASSWORD/],
  ]) {
    if (re.test(blob)) { block(`${name} present in client bundle`, `${files.length} files under .next/static`); n++; }
  }
  if (!n) ok(`no server secrets in client bundle (${files.length} files scanned)`);
} else {
  warn("client bundle not scanned", "run `npx next build` first so .next/static exists");
}

/* ── §15 AI-CODE / BACKDOOR AUDIT ───────────────────────────────────────── */
console.log("\n=== 15 AI-CODE / BACKDOOR AUDIT ===");
const SRC = tracked.filter((f) => /^(app|components|lib|hooks|db)\/|^middleware\.ts$/.test(f) && /\.(ts|tsx)$/.test(f));

const DANGER = [
  ["eval / Function constructor", /\beval\s*\(|new\s+Function\s*\(/],
  ["shell execution", /child_process|execSync|spawnSync/],
  ["unsafe HTML injection", /dangerouslySetInnerHTML|\.innerHTML\s*=/],
  ["wildcard CORS", /Access-Control-Allow-Origin[^\n]{0,12}\*/],
  ["auth-bypass marker", /disable\s*auth|bypass\s*auth|skip\s*auth|master[_ ]?password|backdoor|allow\s*all/i],
  ["security TODO left in code", /(TODO|FIXME|HACK|XXX)[^\n]{0,60}(security|auth|permission|rls|temporar)/i],
  ["suppressed type error", /@ts-(ignore|expect-error)/],
];
let dangerHits = 0;
for (const f of SRC) {
  const lines = fs.readFileSync(f, "utf8").split("\n");
  lines.forEach((line, i) => {
    for (const [name, re] of DANGER) {
      if (re.test(line)) { warn(name, `${f}:${i + 1}  ${line.trim().slice(0, 110)}`); dangerHits++; }
    }
  });
}
if (!dangerHits) ok(`no dangerous patterns across ${SRC.length} source files`);

// The service-role client bypasses RLS — it must stay inside vetted server modules.
const ADMIN_ALLOWED = new Set([
  "lib/supabase/admin.ts",
  "lib/auth/accounts.ts",
  "lib/storage.ts",
  "lib/rate-limit.ts",
  "lib/audit.ts",
  "lib/actions/warden.ts",
  // Account-deletion requests. Three uses, each forced by an RLS policy rather than chosen:
  //   1. inserting notifications  - notifications_insert requires app.is_service_role()
  //   2. reading audit_log        - audit_log_select allows only super_admin / hostel owner, so a
  //                                 resident cannot see even their own request; the query is
  //                                 pinned to the caller's own actor_user_id
  //   3. resolving the recipients - users_select stops a student enumerating staff accounts
  // A fourth use (reading the caller's own students row) was removed instead of allowlisted:
  // students_select already permits user_id = auth.uid(). Adding a file here is a review
  // decision, not a formality - it exempts that file from the RLS-bypass check permanently.
  "lib/actions/account.ts",
  "db/seed.ts",
]);
const adminUsers = SRC.filter((f) => /createAdminClient|supabase\/admin/.test(fs.readFileSync(f, "utf8")));
const rogue = adminUsers.filter((f) => !ADMIN_ALLOWED.has(f.replace(/\\/g, "/")));
if (rogue.length) block("service-role client used outside vetted modules", rogue.join("\n"));
else ok(`service-role client confined to ${adminUsers.length} vetted modules`);

// No client component may import a server-only module at runtime.
const SERVER_ONLY = /lib\/(supabase\/(admin|server)|permissions|audit|rate-limit|storage)/;
const clientLeaks = SRC.filter((f) => {
  const c = fs.readFileSync(f, "utf8");
  if (!/^\s*["']use client["']/m.test(c)) return false;
  return c.split("\n").some((l) => /^\s*import\s/.test(l) && !/^\s*import\s+type\s/.test(l) && SERVER_ONLY.test(l));
});
if (clientLeaks.length) block("client component imports a server-only module", clientLeaks.join("\n"));
else ok("no client component imports a server-only module");

/* ── §22 DEPENDENCIES ───────────────────────────────────────────────────── */
console.log("\n=== 22 DEPENDENCIES ===");
const auditRaw = sh("npm audit --omit=dev --json");
if (auditRaw) {
  try {
    const a = JSON.parse(auditRaw);
    const v = a.metadata?.vulnerabilities ?? {};
    const line = Object.entries(v).filter(([, n]) => n > 0).map(([k, n]) => `${n} ${k}`).join(", ") || "none";
    if (v.critical > 0) block("critical dependency vulnerability", line);
    else if (v.high > 0) warn("high dependency vulnerabilities — confirm reachability", line);
    else ok(`production dependency audit: ${line}`);
  } catch {
    warn("npm audit output unparseable", "run `npm audit --omit=dev` manually");
  }
} else {
  warn("npm audit unavailable", "registry unreachable (offline or TLS interception)");
}

if (fs.existsSync("package-lock.json")) ok("dependency versions locked (package-lock.json)");
else block("no lockfile committed", "commit package-lock.json for reproducible installs");

/* ── SUMMARY ────────────────────────────────────────────────────────────── */
console.log(`\n${"=".repeat(62)}`);
console.log(`  RESULT: ${blockers} blocker(s), ${warnings} warning(s)`);
console.log(`${"=".repeat(62)}\n`);
process.exit(blockers > 0 ? 1 : 0);
