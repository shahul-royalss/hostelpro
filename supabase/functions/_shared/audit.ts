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
