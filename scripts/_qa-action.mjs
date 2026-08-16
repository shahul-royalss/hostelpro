// QA helper: invoke a Next.js server action over HTTP as a signed-in demo user.
//   node scripts/_qa-action.mjs <email> <password> <page-path> <actionId> '<json-args-array>'
//   node scripts/_qa-action.mjs <email> <password> <page-path> <actionId> --form key=value key=value ...
// Prints the RSC response tail (the action's return value is the last JSON row).
import { createServerClient } from "@supabase/ssr";
import fs from "node:fs";

const env = Object.fromEntries(
  fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l && !l.startsWith("#") && l.includes("=")).map((l) => {
    const i = l.indexOf("=");
    return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
  }),
);
const [email, password, path, actionId, ...rest] = process.argv.slice(2);
const jar = new Map();
const s = createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  cookies: { getAll() { return [...jar].map(([name, value]) => ({ name, value })); }, setAll(cs) { cs.forEach((c) => jar.set(c.name, c.value)); } },
});
const { error } = await s.auth.signInWithPassword({ email, password });
if (error) { console.error("LOGIN FAILED", error.message); process.exit(1); }
const cookie = [...jar].map(([n, v]) => `${n}=${v}`).join("; ");

let body, headers;
if (rest[0] === "--form") {
  // Progressive-enhancement path (what a non-hydrated <form action={serverAction}> posts):
  // multipart with a `$ACTION_ID_<id>` field; Next calls the action with the raw FormData.
  const fd = new FormData();
  fd.append(`$ACTION_ID_${actionId}`, "");
  for (const kv of rest.slice(1)) { const i = kv.indexOf("="); fd.append(kv.slice(0, i), kv.slice(i + 1)); }
  body = fd; headers = {};
} else {
  body = rest[0] ?? "[]";
  headers = { "Content-Type": "text/plain;charset=UTF-8", "Next-Action": actionId };
}
const res = await fetch(`http://localhost:3000${path}`, {
  method: "POST",
  headers: { ...headers, Accept: "text/x-component", Cookie: cookie },
  body,
});
const text = await res.text();
const lines = text.trim().split("\n");
// The action result is the row whose id was referenced by "0:" — print last few rows compactly
console.log(`HTTP ${res.status}`);
console.log(lines.slice(-3).map((l) => l.slice(0, 400)).join("\n"));
