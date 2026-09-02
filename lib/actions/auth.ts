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
   * THE PASSWORD IN HAND IS REQUIRED ON BOTH PATHS, AND SUPABASE IS THE ONE WHO DECIDED THAT.
   *
   * This block used to exempt the forced first-login change on the reasoning that the user had
   * just authenticated with the temporary password. Measured against the live project on
   * 2026-09-01:
   *
   *     PUT /auth/v1/user {"password":"…"}                        -> 400 current_password_required
   *     PUT /auth/v1/user {"password":"…","current_password":"…"} -> 200
   *
   * GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD is on for this project, so the
   * exempt path could not complete a single password change — and every account this platform
   * creates is redirected to /change-password before it can reach anything else.
   *
   * What `must_change_password` still decides is REAUTHENTICATION (checklist §8): a voluntary
   * change spends a throttled password grant first, so a hijacked session — a stolen cookie, an
   * unlocked laptop — cannot be used to lock the real owner out. A forced change does not,
   * because GoTrue is about to check the very same password one call below and a second grant
   * would only widen the guessing oracle. Which case applies is read from the DB, never from
   * the form.
   */
  if (!parsed.data.currentPassword) {
    const label = user.must_change_password
      ? "Enter the temporary password you were given."
      : "Enter your current password.";
    return fail(label, { currentPassword: [label] });
  }
  if (!user.must_change_password) {
    const { error: reauthError } = await supabase.auth.signInWithPassword({
      email: user.authEmail ?? "",
      password: parsed.data.currentPassword,
    });
    if (reauthError) {
      await audit("auth.password.reauth_failed", { targetType: "user", targetId: user.id });
      return fail("Your current password is incorrect.", { currentPassword: ["Your current password is incorrect."] });
    }
  }

  const { error } = await supabase.auth.updateUser({
    password: parsed.data.password,
    // What turns the call above from a 400 into a 200. GoTrue verifies it against the stored
    // hash, which on the forced path is the only check the password gets. Snake-case because
    // that is what @supabase/auth-js names the field on UserAttributes (types.d.ts:423) —
    // gotrue-dart spells the same wire field `currentPassword`.
    current_password: parsed.data.currentPassword,
  });
  if (error) {
    // Matched on the CODE for the two current-password verdicts, because GoTrue's message is
    // wrong for one of them: a *wrong* current password answers `current_password_invalid` with
    // the text "Current password required when setting new password.", which tells somebody who
    // typed it that they did not. Both get a sentence about the field they can see.
    const code = (error as { code?: string }).code;
    if (code === "current_password_invalid" || code === "current_password_required") {
      const label = user.must_change_password
        ? "That temporary password is not right. Use the one you were given, exactly as it was written."
        : "Your current password is incorrect.";
      return fail(label, { currentPassword: [label] });
    }
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
