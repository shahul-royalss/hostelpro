"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { audit } from "@/lib/audit";
import { assertHostelContext, errorMessage, requireUser, type SessionUser } from "@/lib/permissions";
import { rateLimit } from "@/lib/rate-limit";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { fail, ok, type ActionResult } from "@/lib/types";

/**
 * Account and data deletion requests — the in-app half of Google Play's account-deletion
 * requirement. The public half, which a reviewer must be able to reach signed out, is
 * `/legal/account-deletion`.
 *
 * WHY THIS IS A REQUEST AND NOT A DELETE BUTTON. Accounts here are not self-service: the
 * Warden registers a student, the Owner creates staff, and `db/rls-policies.sql` gives no
 * role a DELETE policy on `students` or `users` — deliberately. `fee_payments` cascades from
 * `students`, so a resident who could erase their own row would take the hostel's fee ledger
 * with them, free a bed that is still occupied, and destroy records the operator has a
 * statutory duty to keep (`docs/data-retention-and-privacy.md` §5.2). Identity also has to be
 * verified out of band, because "erase my data" sent by somebody else is a denial of service
 * against the person it names.
 *
 * So the user files a request, the people who can action it are notified, and the request
 * itself lands in `audit_log` as durable proof that it was made. Fulfilment is the manual
 * runbook in `docs/account-deletion.md`.
 */

/** A request stays "on file" for this long — it de-duplicates repeat taps and drives the UI. */
const REQUEST_WINDOW_DAYS = 30;
/** Per user, per day. One request is enough; this only stops a stuck button flooding inboxes. */
const REQUEST_LIMIT = { max: 3, windowSeconds: 24 * 60 * 60 };
/** Free text is trimmed hard before it is copied into a staff notification body. */
const REASON_IN_NOTIFICATION = 200;

export interface DeletionRequestState {
  /** Timestamp of the request now on file, read back from `audit_log` — never a local guess. */
  requestedAt: string;
  /** true when a request was already on file, so this call added nothing. */
  alreadyPending: boolean;
  /**
   * How many staff inboxes the request was delivered to. Meaningful only when
   * `alreadyPending` is false: 0 then means the notification write failed and a human has to
   * be told directly.
   */
  notifiedCount: number;
}

const requestAccountDeletionSchema = z.object({
  // errorMap, not `message`: zod 3 only routes `message` to invalid_type / required, so a
  // literal mismatch would fall back to "Invalid literal value, expected true" — which is
  // what a user would have seen.
  confirm: z.literal(true, {
    errorMap: () => ({ message: "Please confirm that you want your account and data deleted." }),
  }),
  reason: z.string().trim().max(500, "Keep the reason under 500 characters").optional().or(z.literal("")),
});

/**
 * File a deletion request for the signed-in user's own account.
 * Notifies the people who can action it and records the request in the audit trail.
 */
export async function requestAccountDeletion(input: {
  confirm: boolean;
  reason?: string;
}): Promise<ActionResult<DeletionRequestState>> {
  const parsed = requestAccountDeletionSchema.safeParse(input);
  if (!parsed.success) {
    // The confirmation is a checkbox the UI always sets, so the only failure a real user can
    // reach is an over-long reason — surface that rather than a generic "confirm" message.
    const fieldErrors = parsed.error.flatten().fieldErrors;
    return fail(fieldErrors.reason?.[0] ?? "Please confirm before sending the request.", fieldErrors);
  }
  const reason = parsed.data.reason?.trim() ?? "";

  try {
    // Deliberately assertHostelContext(), NOT assertWritableContext(): a data-subject request
    // must not be refused because the hostel's subscription lapsed (Hard rule §4.4 gates
    // *hostel* writes). A read-only tenant still owes its residents this path, and a deletion
    // route that fails on an expired plan is, for Play's purposes, no route at all.
    const { user, ctx } = await assertHostelContext("student", "warden", "manager", "owner");

    const rl = await rateLimit(`account:deletion:${user.id}`, REQUEST_LIMIT.max, REQUEST_LIMIT.windowSeconds);
    if (!rl.allowed) return fail("You have already sent this request. Your warden and hostel owner can see it.");

    const already = await latestRequestAt(user.id);
    if (already) {
      return ok(
        { requestedAt: already, alreadyPending: true, notifiedCount: 0 },
        "Your deletion request is already on file.",
      );
    }

    // The student row (when there is one) gives the owner a deep link straight to the record
    // that has to be actioned, and gives the runbook the id to work from.
    const studentId = await myStudentId(user);
    const recipients = await recipientsFor(user, ctx.hostel.id, ctx.hostel.owner_user_id);

    let notifiedCount = 0;
    if (recipients.length) {
      try {
        const body =
          user.full_name +
          " asked for their HostelPro account and personal data to be deleted." +
          (reason ? ' Reason: "' + reason.slice(0, REASON_IN_NOTIFICATION) + '"' : "") +
          " Verify who they are in person before acting.";
        const { error } = await createAdminClient()
          .from("notifications")
          .insert(
            recipients.map((r) => ({
              hostel_id: ctx.hostel.id,
              user_id: r.id,
              type: "system" as const,
              title: "Account deletion requested",
              body,
              link: linkFor(r.role, studentId),
            })),
          );
        if (error) throw error;
        notifiedCount = recipients.length;
      } catch (e) {
        // Not fatal: the audit record below is the authoritative one, and the caller is told
        // to speak to a human when nothing was delivered.
        console.error(
          "[hostelpro] deletion request: notification delivery failed:",
          e instanceof Error ? `${e.name}: ${e.message}` : String(e),
        );
      }
    }

    // NOTE: the free-text reason is deliberately NOT copied into audit meta. `audit_log` is
    // kept for 365 days and is readable by the hostel owner and the Super Admin; the reason is
    // the requester's own words and is only needed by the person actioning it, so it stays in
    // the notification and out of the long-lived security trail (data minimisation —
    // `docs/data-retention-and-privacy.md` §8).
    await audit("account.deletion.requested", {
      targetType: "user",
      targetId: user.id,
      hostelId: ctx.hostel.id,
      meta: {
        requesterRole: user.role,
        studentId: studentId ?? null,
        notified: notifiedCount,
        hasReason: reason.length > 0,
      },
    });

    // audit() never throws — it swallows a missing service-role key or a dead RPC so that it
    // can never break the action it is recording. That is right everywhere else and wrong
    // here, because the audit row IS the request. Read it back, and refuse to report success
    // without it.
    const requestedAt = await latestRequestAt(user.id);
    if (!requestedAt) {
      return fail(
        "We could not record your request just now. Please tell your warden or hostel owner directly, or use the email address on the account deletion page.",
      );
    }

    revalidatePath("/student/profile");
    return ok(
      { requestedAt, alreadyPending: false, notifiedCount },
      notifiedCount > 0
        ? "Deletion request sent. Your warden and hostel owner have been notified."
        : "Deletion request recorded. Please also tell your warden or hostel owner directly.",
    );
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/**
 * The signed-in user's own pending request, for the profile card.
 * Returns null when nothing has been filed in the last REQUEST_WINDOW_DAYS.
 */
export async function getMyDeletionRequest(): Promise<{ requestedAt: string } | null> {
  const user = await requireUser();
  const at = await latestRequestAt(user.id);
  return at ? { requestedAt: at } : null;
}

/* ───────────────────────── internals ───────────────────────── */

/**
 * Most recent request by this user inside the window, or null.
 *
 * Service role on purpose: the `audit_log` select policy is Super Admin / hostel owner only,
 * so a student cannot read even their own rows. The filter is pinned to the caller's own
 * `actor_user_id`, so no other person's trail is reachable through here.
 */
async function latestRequestAt(userId: string): Promise<string | null> {
  try {
    const since = new Date(Date.now() - REQUEST_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await createAdminClient()
      .from("audit_log")
      .select("at")
      .eq("action", "account.deletion.requested")
      .eq("actor_user_id", userId)
      .gte("at", since)
      .order("at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    return (data as { at: string } | null)?.at ?? null;
  } catch (e) {
    // No service-role key configured (local dev) or the query failed: report "nothing on file"
    // rather than blocking the screen. requestAccountDeletion() turns this into an honest
    // failure message, because it read-checks its own write.
    console.error(
      "[hostelpro] deletion request lookup failed:",
      e instanceof Error ? `${e.name}: ${e.message}` : String(e),
    );
    return null;
  }
}

/** The caller's own active student row id, when they are a resident. */
async function myStudentId(user: SessionUser): Promise<string | null> {
  if (user.role !== "student") return null;
  try {
    // RLS client, deliberately: students_select allows `user_id = auth.uid()`, so a resident can
    // read their own row under their own session. Reaching for the service role here would be
    // privilege this function does not need.
    const supabase = await createClient();
    const { data } = await supabase
      .from("students")
      .select("id")
      .eq("user_id", user.id)
      .neq("status", "vacated")
      .maybeSingle();
    return (data as { id: string } | null)?.id ?? null;
  } catch {
    return null;
  }
}

interface Recipient {
  id: string;
  role: "owner" | "warden" | "super_admin";
}

/**
 * Who can actually action this request.
 *  • student          → the hostel's warden(s) and its owner (the warden vacates, the owner signs off)
 *  • warden / manager → the owner, who created the account and is the only one who can remove it
 *  • owner            → the Super Admin; nobody inside the tenant is above them
 *
 * Mirrors `app.complaints_after_change()`: wardens are matched on `users.hostel_id`, the owner
 * on `hostels.owner_user_id` (an owner with several hostels may carry a different `hostel_id`).
 * The requester is never notified about their own request.
 */
async function recipientsFor(user: SessionUser, hostelId: string, ownerUserId: string): Promise<Recipient[]> {
  const admin = createAdminClient();
  const out: Recipient[] = [];

  if (user.role === "owner") {
    const { data } = await admin
      .from("users")
      .select("id")
      .eq("role", "super_admin")
      .eq("status", "active")
      .is("deleted_at", null);
    for (const r of (data ?? []) as { id: string }[]) out.push({ id: r.id, role: "super_admin" });
  } else {
    if (user.role === "student") {
      const { data } = await admin
        .from("users")
        .select("id")
        .eq("role", "warden")
        .eq("hostel_id", hostelId)
        .eq("status", "active")
        .is("deleted_at", null);
      for (const r of (data ?? []) as { id: string }[]) out.push({ id: r.id, role: "warden" });
    }
    const { data: owner } = await admin
      .from("users")
      .select("id")
      .eq("id", ownerUserId)
      .eq("status", "active")
      .is("deleted_at", null)
      .maybeSingle();
    if (owner) out.push({ id: (owner as { id: string }).id, role: "owner" });
  }

  const seen = new Set<string>([user.id]);
  return out.filter((r) => {
    if (seen.has(r.id)) return false;
    seen.add(r.id);
    return true;
  });
}

/** Where the recipient goes to act on it — a real route inside their own role group. */
function linkFor(role: Recipient["role"], studentId: string | null): string {
  if (role === "super_admin") return "/super-admin/hostels";
  if (role === "owner") return studentId ? `/owner/students/${studentId}` : "/owner/staff";
  // A warden vacates a resident from the room detail screen (components/warden/room-detail.tsx).
  return "/warden/rooms";
}
