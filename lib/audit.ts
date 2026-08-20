import "server-only";
import { createHash } from "crypto";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { getClientIp, getUserAgent } from "@/lib/rate-limit";

/**
 * Audit trail for privileged / security-relevant events (checklist §27, §30).
 * Written through the audit_event() RPC so the actor is always auth.uid() (unspoofable).
 * Never throws — auditing must not break the primary action.
 *
 *   await audit("staff.create", { targetType: "user", targetId, hostelId, meta: { role } });
 */
export type AuditAction =
  | "auth.login.success" | "auth.login.failed" | "auth.login.rate_limited" | "auth.logout"
  | "auth.password.changed" | "auth.password.reauth_failed"
  | "auth.mfa.enrolled" | "auth.mfa.unenrolled" | "auth.mfa.verified" | "auth.mfa.failed"
  | "sa.owner_hostel.create" | "sa.subscription.renew" | "sa.hostel.status" | "sa.owner.password_reset" | "sa.hostel.structure"
  | "owner.staff.create" | "owner.staff.password_reset" | "owner.staff.status"
  | "owner.announcement.create" | "owner.announcement.delete" | "owner.hostel.rules"
  | "owner.task.create" | "owner.task.update" | "owner.task.delete"
  | "warden.student.register" | "warden.student.vacate" | "warden.student.reassign" | "warden.payment.record" | "warden.room.update"
  | "warden.leave.decide" | "warden.visitor.log" | "warden.visitor.checkout"
  | "manager.expense.create" | "manager.expense.update" | "manager.expense.delete"
  | "manager.revenue.create" | "manager.revenue.update" | "manager.revenue.delete"
  | "manager.task.status" | "manager.menu.save"
  | "staff.complaint.status"
  | "authz.denied";

export interface AuditOptions {
  targetType?: string;
  targetId?: string | null;
  hostelId?: string | null;
  meta?: Record<string, unknown>;
}

/**
 * Record an event as the current signed-in user.
 *
 * The write goes through the SERVICE ROLE, not the user's session: audit_event() is not
 * executable by `authenticated`, otherwise any signed-in user could call it directly via
 * PostgREST and inject rows into another tenant's (owner-visible) trail or flood the table.
 * The actor is taken from the session this server already verified with getUser(), so it
 * still cannot be spoofed by the client.
 */
export async function audit(action: AuditAction, opts: AuditOptions = {}): Promise<void> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();
    const [ip, ua] = await Promise.all([getClientIp(), getUserAgent()]);
    let actorRole: string | null = null;
    let actorHostelId: string | null = null;
    if (user) {
      const { data } = await supabase.from("users").select("role, hostel_id").eq("id", user.id).maybeSingle();
      actorRole = (data as { role?: string } | null)?.role ?? null;
      actorHostelId = (data as { hostel_id?: string | null } | null)?.hostel_id ?? null;
    }
    await createAdminClient().rpc("audit_event", {
      p_action: action,
      p_target_type: opts.targetType ?? null,
      p_target_id: opts.targetId ?? null,
      // Default to the actor's own hostel. Authentication events (login, logout, password
      // change, MFA) pass no hostelId, so they were all written with hostel_id NULL — and the
      // owner's read policy is scoped by hostel_id, so an owner could not see login activity
      // for their own staff. The audit trail existed but was invisible to the person it is for.
      p_hostel_id: opts.hostelId ?? actorHostelId,
      p_meta: sanitizeMeta(opts.meta),
      p_ip: ip,
      p_user_agent: ua,
      p_actor_user_id: user?.id ?? null,
      p_actor_role: actorRole,
    });
  } catch {
    /* never block the primary action */
  }
}

/** Record an event with no user session (failed logins, rate limits) — service role. */
export async function auditSystem(action: AuditAction, opts: AuditOptions = {}): Promise<void> {
  try {
    const admin = createAdminClient();
    const [ip, ua] = await Promise.all([getClientIp(), getUserAgent()]);
    await admin.from("audit_log").insert({
      actor_user_id: null,
      actor_role: null,
      action,
      target_type: opts.targetType ?? null,
      target_id: opts.targetId ?? null,
      hostel_id: opts.hostelId ?? null,
      ip,
      user_agent: ua,
      meta: sanitizeMeta(opts.meta),
    });
  } catch {
    /* never block the primary action */
  }
}

/** Identifiers (emails/phones) are stored hashed — enough to correlate, not to read. */
export function hashIdentifier(id: string): string {
  return createHash("sha256").update(id.trim().toLowerCase()).digest("hex").slice(0, 24);
}

const SECRET_KEYS = /pass|secret|token|key|otp|code|authorization|cookie/i;
function sanitizeMeta(meta: Record<string, unknown> | undefined): Record<string, unknown> {
  if (!meta) return {};
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(meta)) {
    if (SECRET_KEYS.test(k)) continue; // never persist credentials or codes
    out[k] = typeof v === "string" ? v.slice(0, 200) : v;
  }
  return out;
}
