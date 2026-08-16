// QA helper: invoke a Next.js server action over HTTP as a signed-in demo user.
//   node scripts/_qa-action.mjs <email> <password> <page-path> <actionId> '<json-args-array>'
//   node scripts/_qa-action.mjs <email> <password> <page-path> <actionId> --form key=value ... [--file field=path ...]
// Prints the action's ActionResult (parsed from the RSC response) when it can be found.
// Action ids: .next/server/server-reference-manifest.json (dev) — see scripts/README.md.
// Git Bash: run with MSYS_NO_PATHCONV=1 so "/manager/..." isn't rewritten to a Windows path.
import { createServerClient } from "@supabase/ssr";
import fs from "node:fs";
import path from "node:path";

const env = Object.fromEntries(
  fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l && !l.startsWith("#") && l.includes("=")).map((l) => {
    const i = l.indexOf("=");
    return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
  }),
);
const [email, password, pagePath, actionId, ...rest] = process.argv.slice(2);
const jar = new Map();
const s = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  cookies: { getAll() { return [...jar].map(([name, value]) => ({ name, value })); }, setAll(cs) { cs.forEach((c) => jar.set(c.name, c.value)); } },
});
const { error } = await s.auth.signInWithPassword({ email, password });
if (error) { console.error("LOGIN FAILED", error.message); process.exit(1); }
const cookie = [...jar].map(([n, v]) => `${n}=${v}`).join("; ");

const MIME = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", pdf: "application/pdf" };
let body, headers;
if (rest[0] === "--form") {
  // Progressive-enhancement path (what a non-hydrated <form action={serverAction}> posts):
  // multipart with a `$ACTION_ID_<id>` field; Next calls the action with the raw FormData.
  const fd = new FormData();
  fd.append(`$ACTION_ID_${actionId}`, "");
  let mode = "kv";
  for (const tok of rest.slice(1)) {
    if (tok === "--file") { mode = "file"; continue; }
    const i = tok.indexOf("=");
    const k = tok.slice(0, i), v = tok.slice(i + 1);
    if (mode === "file") {
      const buf = fs.readFileSync(v);
      const ext = path.extname(v).slice(1).toLowerCase();
      fd.append(k, new Blob([buf], { type: MIME[ext] ?? "application/octet-stream" }), path.basename(v));
      mode = "kv";
    } else fd.append(k, v);
  }
  body = fd; headers = {};
} else {
  body = rest[0] ?? "[]";
  headers = { "Content-Type": "text/plain;charset=UTF-8", "Next-Action": actionId };
}
const res = await fetch(`http://localhost:3000${pagePath}`, {
  method: "POST",
  headers: { ...headers, Accept: "text/x-component", Cookie: cookie },
  body,
});
const text = await res.text();
console.log(`HTTP ${res.status}`);
// Find the ActionResult row: an RSC line like `N:{"ok":true,...}` or `N:{"ok":false,...}`
const m = text.match(/^[0-9a-f]+:(\{"ok":(?:true|false).*)$/m);
if (m) console.log(m[1].slice(0, 1200));
else console.log(text.trim().split("\n").slice(-2).map((l) => l.slice(0, 300)).join("\n"));
