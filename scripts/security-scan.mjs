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

// Demo credentials that are deliberately in the docs/seed, plus doc placeholders.
const ALLOW = /[REDACTED-ROTATED-CREDENTIAL]|Owner@12345|Manager@12345|Warden@12345|Student@12345|ChangeMe!2026|NewPass@2026|AuditPass1|SUPER_ADMIN_PASSWORD|your-default-host|example\.com|placeholder|PASSWORD_MIN_LENGTH|password:\s*["']?\$\{|p_password|passwordStrength/i;

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
