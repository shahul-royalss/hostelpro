/**
 * Audit trail. Writes go through public.audit_event(), which is granted to service_role only.
 *
 * Inside an Edge Function auth.uid() is NULL on the service connection, so the actor is passed
 * explicitly — taken from the profile row requireCaller() already verified against the
 * database, never from the request body. audit_event() also strips password/token-ish keys out
 * of meta before inserting, so a future caller cannot persist a credential by accident.
 *
 * Auditing must never break the operation it is recording: every failure here is swallowed.
 */
import type { Caller } from "./caller.ts";
import { serviceClient } from "./supabase.ts";

export interface AuditOptions {
  targetType?: string;
  targetId?: string | null;
  hostelId?: string | null;
  meta?: Record<string, unknown>;
}

export async function audit(action: string, actor: Caller, opts: AuditOptions = {}): Promise<void> {
  try {
    await serviceClient().rpc("audit_event", {
      p_action: action,
      p_target_type: opts.targetType ?? null,
      p_target_id: opts.targetId ?? null,
      p_hostel_id: opts.hostelId ?? actor.hostelId ?? null,
      p_meta: opts.meta ?? {},
      p_ip: actor.ip,
      p_user_agent: actor.userAgent,
      p_actor_user_id: actor.id,
      p_actor_role: actor.role,
    });
  } catch (e) {
    console.error("[nivora] audit write failed:", e instanceof Error ? e.message : String(e));
  }
}

/**
 * An event with NO verified actor — a sign-in that failed, or one that was throttled before
 * any credential was checked.
 *
 * There is deliberately no user lookup here. Resolving the typed identifier to a user id
 * would turn the trail into a record of which accounts exist, and would make the audit write
 * itself an enumeration oracle timing-wise. The identifier is stored HASHED
 * ([hashIdentifier]) as target_id: enough to correlate twenty attempts against one account,
 * not enough to read back the phone number that was probed.
 *
 * This is the shape app.detect_suspicious_activity() is written against: with
 * actor_user_id NULL it counts `auth.login.failed` rows BY IP, which is why `ip` matters more
 * here than anywhere else in the trail. Port of auditSystem() in lib/audit.ts, except that it
 * goes through audit_event() rather than inserting directly, so the RPC's own secret-key
 * stripping applies.
 */
export async function auditSystem(
  action: string,
  opts: AuditOptions & { ip?: string | null; userAgent?: string | null } = {},
): Promise<void> {
  try {
    await serviceClient().rpc("audit_event", {
      p_action: action,
      p_target_type: opts.targetType ?? null,
      p_target_id: opts.targetId ?? null,
      p_hostel_id: opts.hostelId ?? null,
      p_meta: opts.meta ?? {},
      p_ip: opts.ip ?? null,
      p_user_agent: opts.userAgent ?? null,
      p_actor_user_id: null,
      p_actor_role: null,
    });
  } catch (e) {
    console.error("[nivora] audit write failed:", e instanceof Error ? e.message : String(e));
  }
}

/**
 * Identifiers (emails, phone-derived logins) are stored hashed — enough to correlate, not to
 * read. Byte-for-byte the same digest as hashIdentifier() in lib/audit.ts, so an attack that
 * hits the web app and the phone app produces rows that correlate to the SAME target_id
 * instead of looking like two unrelated events.
 */
export async function hashIdentifier(id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id.trim().toLowerCase()));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 24);
}
