"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { resolveLoginEmail } from "@/lib/utils";
import { ROLE_HOME, type UserRole } from "@/lib/roles";
import { changePasswordSchema, loginSchema } from "@/lib/validators/auth";
import { fail, type ActionResult } from "@/lib/types";
import { getSessionUser, errorMessage } from "@/lib/permissions";
import { clearMustChangePassword } from "@/lib/auth/accounts";
import { LIMITS, getClientIp, rateLimit } from "@/lib/rate-limit";
import { audit, auditSystem, hashIdentifier } from "@/lib/audit";

const GENERIC_LOGIN_ERROR = "Incorrect email/phone or password.";

/** Only same-origin relative paths under the user's own role home are honoured as a post-login target. */
function safeNext(next: string | undefined, role: UserRole): string {
  const home = ROLE_HOME[role];
  if (!next) return home;
  if (!next.startsWith("/") || next.startsWith("//") || /[\\\r\n]/.test(next)) return home;
  return next === home || next.startsWith(home + "/") ? next : home;
}

/**
 * Single login for all roles (§3). Accepts email OR phone (students).
 * Brute-force protection: durable limits per IP and per identifier (fail-closed),
 * on top of Supabase Auth's own limits. Failures/successes are audited (identifier hashed).
 * On success redirects to the role home, /change-password (first login) or /mfa (step-up).
 */
export async function signIn(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const parsed = loginSchema.safeParse({
    identifier: formData.get("identifier"),
    password: formData.get("password"),
    next: formData.get("next") ?? undefined,
  });
  if (!parsed.success) {
    return fail("Check your details and try again.", parsed.error.flatten().fieldErrors);
  }
  const { identifier, password, next } = parsed.data;
  const email = resolveLoginEmail(identifier);
  const idHash = hashIdentifier(email);
  const ip = await getClientIp();

  // Rate limits (checklist §3/§19): per IP and per identifier
  const [byIp, byId] = await Promise.all([
    rateLimit(`login:ip:${ip}`, LIMITS.loginPerIp.max, LIMITS.loginPerIp.windowSeconds, true),
    rateLimit(`login:id:${idHash}`, LIMITS.loginPerIdentifier.max, LIMITS.loginPerIdentifier.windowSeconds, true),
  ]);
  if (!byIp.allowed || !byId.allowed) {
    const wait = Math.max(byIp.retryAfterSeconds, byId.retryAfterSeconds);
    await auditSystem("auth.login.rate_limited", { targetType: "identifier", targetId: idHash });
    return fail(`Too many sign-in attempts. Please wait ${Math.ceil(wait / 60)} minute${wait > 60 ? "s" : ""} and try again.`);
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) {
    if (process.env.NODE_ENV !== "production") {
      console.error("[signIn] failed:", error?.status, error?.message);
    }
    await auditSystem("auth.login.failed", { targetType: "identifier", targetId: idHash, meta: { status: error?.status ?? 0 } });
    if (error?.status === 429) {
      return fail("Too many sign-in attempts. Please wait a few minutes and try again.");
    }
    // Same message whether the account exists or not (no user enumeration)
    return fail(GENERIC_LOGIN_ERROR);
  }

  // Profile row → role, status, must_change_password
  const { data: profile } = await supabase
    .from("users")
    .select("role, status, must_change_password, deleted_at")
    .eq("id", data.user.id)
    .maybeSingle();

  if (!profile || profile.deleted_at || profile.status !== "active") {
    await supabase.auth.signOut();
    await auditSystem("auth.login.failed", { targetType: "identifier", targetId: idHash, meta: { reason: profile ? "inactive" : "no-profile" } });
    // Password was correct, so telling the user the account is disabled leaks nothing new
    return fail(profile ? "This account has been deactivated. Contact your hostel owner." : "Your account isn't set up yet. Contact your administrator.");
  }

  const role = profile.role as UserRole;
  await audit("auth.login.success", { targetType: "user", targetId: data.user.id, meta: { role } });

  // MFA step-up: a verified factor exists → the middleware sends them to /mfa; go there directly
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  const target = safeNext(next, role);
  if (aal?.nextLevel === "aal2" && aal.currentLevel !== "aal2") {
    redirect(`/mfa?next=${encodeURIComponent(target)}`);
  }
  if (profile.must_change_password) redirect("/change-password");
  redirect(target);
}

/** First-login forced change + regular self-service change (§4.9). */
export async function changePassword(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const parsed = changePasswordSchema.safeParse({
    currentPassword: (formData.get("currentPassword") as string | null) || undefined,
    password: formData.get("password"),
    confirm: formData.get("confirm"),
  });
  if (!parsed.success) {
    return fail("Please fix the errors below.", parsed.error.flatten().fieldErrors);
  }
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const rl = await rateLimit(`pwchange:${user.id}`, LIMITS.passwordChangePerUser.max, LIMITS.passwordChangePerUser.windowSeconds, true);
  if (!rl.allowed) return fail("Too many attempts. Please wait a few minutes and try again.");

  const supabase = await createClient();

  /**
   * Reauthentication (checklist §8): a *voluntary* change must prove the current password,
   * so a hijacked session (stolen cookie, unlocked laptop) cannot be used to lock the real
   * owner out. The forced first-login change is exempt — the user just authenticated with
   * the temporary password. Whether it is forced is read from the DB, never from the form.
   */
  if (!user.must_change_password) {
    if (!parsed.data.currentPassword) {
      return fail("Enter your current password.", { currentPassword: ["Enter your current password."] });
    }
    const { error: reauthError } = await supabase.auth.signInWithPassword({
      email: user.authEmail ?? "",
      password: parsed.data.currentPassword,
    });
    if (reauthError) {
      await audit("auth.password.reauth_failed", { targetType: "user", targetId: user.id });
      return fail("Your current password is incorrect.", { currentPassword: ["Your current password is incorrect."] });
    }
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    return fail(
      /same password|different from the old/i.test(error.message)
        ? "Choose a password different from your temporary one."
        : /weak|pwned|leaked|compromised/i.test(error.message)
          ? "That password is too weak or has appeared in a data breach — choose another."
          : errorMessage(error),
    );
  }

  // Clear the flag in DB (RLS allows self-update) and in app_metadata (admin API)
  await supabase.from("users").update({ must_change_password: false }).eq("id", user.id);
  try {
    await clearMustChangePassword(user.id);
  } catch {
    // Service role key not configured — DB flag is cleared; middleware falls back to it.
  }
  await audit("auth.password.changed", { targetType: "user", targetId: user.id, meta: { forced: user.must_change_password } });

  // Revoke every OTHER session (checklist §3): if the password was changed because it may
  // have leaked, any session an attacker still holds dies here. This session stays valid.
  try {
    await supabase.auth.signOut({ scope: "others" });
  } catch {
    /* best effort — the password is already rotated */
  }

  redirect(ROLE_HOME[user.role]);
}

/** Used by the change-password page to know whether this is a forced first-login change. */
export async function getPasswordChangeContext(): Promise<{ forced: boolean; role: UserRole } | null> {
  const user = await getSessionUser();
  if (!user) return null;
  return { forced: user.must_change_password, role: user.role };
}
