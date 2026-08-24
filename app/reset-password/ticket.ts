import { createHmac, timingSafeEqual } from "crypto";
import { cookies } from "next/headers";

/**
 * DO NOT ADD `import "server-only"` HERE. It looks like it belongs — this module derives a key
 * from the service-role secret — and it breaks the build.
 *
 * Why: this file lives under app/, so webpack compiles it in the RSC layer, but
 * lib/actions/password-reset.ts imports it and is itself reachable from a client component, so
 * the same file is also pulled into the client-reference graph. `server-only` resolves to its
 * poisoned entry point there, and the module comes out empty — which surfaces as
 * `TypeError: Cannot read properties of undefined (reading 'call')` while prerendering
 * /forgot-password, a page whose source mentions none of this. Verified by bisection.
 *
 * Nothing is lost. `next/headers` above is the same guard by other means: it throws outright if
 * this module is ever bundled for the browser, which is exactly what `server-only` is for.
 */

/**
 * The "this session came from a recovery email" ticket.
 *
 * WHY THIS EXISTS. Once the callback below exchanges a recovery link, the visitor holds an
 * ordinary Supabase session — indistinguishable, to every later request, from one obtained by
 * typing a password. If /reset-password accepted any signed-in user it would become a
 * documented bypass of the control changePassword() enforces on purpose: a *voluntary* change
 * must re-prove the current password, so a stolen cookie or an unlocked phone cannot be used
 * to lock the real owner out (lib/actions/auth.ts, SECURITY.md §8). An attacker holding a
 * session would simply skip /change-password and use /reset-password instead.
 *
 * So the reset form is gated on a second thing the recovery link is the only way to obtain: a
 * short-lived cookie, issued ONLY when Supabase itself reports the redirect type as
 * `recovery`, bound to the user id it was issued for and signed so it cannot be minted by the
 * client. Holding a session is necessary but no longer sufficient.
 *
 * Not stored server-side, deliberately: adding a table would mean a migration, and db/ is
 * outside this change. The signature plus the embedded expiry give the same two properties a
 * row would (unforgeable, short-lived) without one. It is single-use in practice because the
 * action clears it on success.
 */
export const RESET_TICKET_COOKIE = "hp_pwreset";

/** 15 minutes: long enough to choose a password, short enough that a shared phone is not a hole. */
const TICKET_TTL_SECONDS = 15 * 60;

/**
 * A key DERIVED from the service-role key rather than the key itself — same secret material,
 * different purpose, so a signature can never be confused with (or used as) a credential.
 * Throws when the secret is missing: an unsigned ticket is a forgeable ticket, and the callers
 * treat the throw as "no ticket", which fails closed.
 */
function ticketKey(): Buffer {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret) throw new Error("password-reset ticket: SUPABASE_SERVICE_ROLE_KEY is not set");
  return createHmac("sha256", secret).update("nivora/password-reset-ticket/v1").digest();
}

function sign(payload: string): string {
  return createHmac("sha256", ticketKey()).update(payload).digest("base64url");
}

function cookieOptions() {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    // Scoped to the one route that may act on it. The reset form posts its Server Action to
    // /reset-password, so this path covers the page load and the submit and nothing else.
    path: "/reset-password",
  };
}

/** Route Handler only — Server Components cannot write cookies. */
export async function issueResetTicket(userId: string): Promise<void> {
  const exp = Math.floor(Date.now() / 1000) + TICKET_TTL_SECONDS;
  const payload = `${userId}.${exp}`;
  const store = await cookies();
  store.set(RESET_TICKET_COOKIE, `${payload}.${sign(payload)}`, { ...cookieOptions(), maxAge: TICKET_TTL_SECONDS });
}

/**
 * The user id this ticket was issued for, or null if there is no ticket, it is expired, or the
 * signature does not hold. Callers must still check that it matches the *session* user — the
 * ticket proves how the session was created, the session proves who it belongs to.
 */
export async function resetTicketHolder(): Promise<string | null> {
  try {
    const raw = (await cookies()).get(RESET_TICKET_COOKIE)?.value;
    if (!raw) return null;
    const lastDot = raw.lastIndexOf(".");
    if (lastDot < 0) return null;
    const payload = raw.slice(0, lastDot);
    const presented = Buffer.from(raw.slice(lastDot + 1));
    const expected = Buffer.from(sign(payload));
    // Length check first: timingSafeEqual throws on a length mismatch, and the length of an
    // HMAC is not a secret.
    if (presented.length !== expected.length || !timingSafeEqual(presented, expected)) return null;
    const [userId, exp] = payload.split(".");
    if (!userId || !exp) return null;
    if (Number(exp) * 1000 <= Date.now()) return null;
    return userId;
  } catch {
    return null; // missing secret, malformed cookie — treat as "no ticket"
  }
}

/** Server Action / Route Handler only. Called on success so the ticket cannot be replayed. */
export async function clearResetTicket(): Promise<void> {
  const store = await cookies();
  store.set(RESET_TICKET_COOKIE, "", { ...cookieOptions(), maxAge: 0 });
}
