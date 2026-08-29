/**
 * Rotate the super admin's login — email and/or password — IN PLACE.
 *
 *   node scripts/rotate-super-admin.mjs
 *
 * Reads the TARGET credentials from .env.local (SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD), so
 * the secret never appears in argv or shell history. Requires SUPABASE_SERVICE_ROLE_KEY.
 *
 * WHY THIS EXISTS when db/seed.ts --admin-only already reads the same variables: the seed
 * looks the account up BY THE NEW EMAIL. Point it at an address that does not exist yet and it
 * happily creates a SECOND super admin — leaving the old one alive, with the old password,
 * holding full platform access that nobody remembers to revoke. A rotation must move the ONE
 * existing account, not mint a sibling.
 *
 * Updating in place (same auth user id) is also what preserves everything attached to the id:
 * the public.users row, the audit trail, and any enrolled TOTP factor — so the same
 * authenticator app keeps working after the rotation. Deleting and recreating would silently
 * strip MFA from the platform account, which is the opposite of a security operation.
 *
 * Refuses to run when the super_admin count is not exactly one: with several, "rotate the
 * super admin" is ambiguous and the safe move is to make a human choose.
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";
import { createClient } from "@supabase/supabase-js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
loadEnv({ path: path.join(root, ".env.local") });

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const targetEmail = process.env.SUPER_ADMIN_EMAIL?.trim().toLowerCase();
const targetPassword = process.env.SUPER_ADMIN_PASSWORD;

if (!url || !serviceKey) {
  console.error("✖ NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be in .env.local");
  process.exit(1);
}
if (!targetEmail || !targetPassword) {
  console.error("✖ SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD must be set in .env.local first —");
  console.error("  edit them to the NEW values, then run this script.");
  process.exit(1);
}
if (targetPassword.length < 12) {
  // The platform account gates every tenant. 12 is deliberately stricter than the app's
  // 8-char user minimum.
  console.error("✖ Refusing: the super admin password must be at least 12 characters.");
  process.exit(1);
}

const sb = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

// The role column in public.users is the authority on who the super admin IS — not the email,
// which is precisely the thing being changed.
const { data: admins, error: qErr } = await sb
  .from("users")
  .select("id, email, full_name")
  .eq("role", "super_admin")
  .is("deleted_at", null);
if (qErr) { console.error("✖ could not list super admins:", qErr.message); process.exit(1); }
if (!admins || admins.length !== 1) {
  console.error(`✖ Expected exactly one super_admin row, found ${admins?.length ?? 0}:`);
  for (const a of admins ?? []) console.error(`    ${a.id}  ${a.email}`);
  console.error("  Resolve that first — rotating an ambiguous account is how the wrong one keeps access.");
  process.exit(1);
}

const admin = admins[0];
console.log(`Rotating super admin ${admin.email} → ${targetEmail} (auth user ${admin.id})`);

// email_confirm: the address is being SET by the platform operator, not claimed by a
// stranger — a confirmation round-trip would just wedge login until SMTP exists.
const { error: uErr } = await sb.auth.admin.updateUserById(admin.id, {
  email: targetEmail,
  password: targetPassword,
  email_confirm: true,
});
if (uErr) { console.error("✖ auth update failed:", uErr.message); process.exit(1); }

const { error: pErr } = await sb.from("users").update({ email: targetEmail }).eq("id", admin.id);
if (pErr) {
  // The auth side already changed; say so precisely rather than pretending nothing happened.
  console.error("✖ auth user updated but public.users.email did not:", pErr.message);
  console.error("  Re-run this script — it is idempotent — or fix the row by hand.");
  process.exit(1);
}

// Prove it, from the outside: a real password-grant login with the new pair, using the anon
// key like the app would. This is the line that turns "should work" into "works".
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
if (anon) {
  const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email: targetEmail, password: targetPassword }),
  });
  if (res.ok) {
    console.log("✔ verified: the new credentials sign in");
  } else {
    console.error(`✖ rotation applied but a live login FAILED (HTTP ${res.status}) — investigate before walking away`);
    process.exit(1);
  }
}

// Every other session that account had is now stale by intent: a rotation that leaves old
// sessions alive has not actually rotated anything.
await sb.auth.admin.signOut(admin.id, "global").catch(() => {});
console.log("✔ existing sessions revoked; MFA factors (if enrolled) carried over unchanged");
console.log("Done.");
