/**
 * POST /functions/v1/storage-erasure
 *
 * Drains app.storage_erasures — the queue of files that must actually leave the buckets.
 *
 * ═══ WHY A QUEUE NEEDED A DRAINER AT ALL ═══
 *
 * Supabase installs `storage.protect_delete()` as a BEFORE DELETE trigger on storage.objects:
 * "Direct deletion from storage tables is not allowed. Use the Storage API instead." So SQL —
 * including app.apply_retention(), which runs as a plain pg_cron job — physically cannot remove
 * a file. It can only record the intention.
 *
 * That is what 2026-09-02-retention-and-erasure.sql does: when a complaint ages out, or a
 * departed resident's month elapses, the ROW goes and the object's key is enqueued here. Which
 * means that until something drains this queue, an erasure is only half done — the record is
 * gone and the resident's government ID scan is still sitting in `student-docs`. A privacy
 * promise that deletes the index and keeps the evidence is worse than no promise, because
 * everyone downstream now believes the data is gone.
 *
 * This endpoint is the missing half. It runs with the service role, which is the only identity
 * the Storage API will accept for a private bucket, and it is idempotent: a key already gone is
 * a success, not a failure, so a retry after a partial run cannot get stuck.
 *
 * ═══ WHO MAY CALL IT ═══
 *
 * The service role and nobody else. This deletes files permanently and takes no ownership
 * argument, so a warden or an owner reaching it would be able to erase another tenant's
 * evidence. requireServiceRole() below compares the bearer token against the project's service
 * key exactly as _shared/caller.ts:77 does for the same purpose.
 *
 * ═══ FAILURE IS RECORDED, NOT SWALLOWED ═══
 *
 * A key that will not delete increments `attempts` and stores `last_error`. After
 * MAX_ATTEMPTS it stops being retried and stays visible in the table — an erasure that cannot
 * complete is an incident someone has to look at, not a row to hide. Nothing is ever deleted
 * from this queue: `purged_at` is the record that the promise was kept, and it is the only
 * evidence of it.
 */

import { HttpError, ok, preflight, toResponse } from "../_shared/http.ts";
import { serviceClient, serviceRoleKey } from "../_shared/supabase.ts";

/** How many rows one invocation will attempt. Bounded so a huge backlog cannot time the
 *  function out and lose the whole run — the next tick picks up where this one stopped. */
const BATCH = 200;

/** After this many failures a key is left alone for a human. See the header. */
const MAX_ATTEMPTS = 5;

/**
 * The caller must present a SERVICE-ROLE JWT.
 *
 * Checked by CLAIM, not by string equality against the key in this function's environment.
 * Comparing key copies looked tidier and was wrong: the deployed secret is
 * NIVORA_SERVICE_ROLE_KEY (the platform refuses secrets named SUPABASE_*), so any drift between
 * that value and the one the caller holds turns a legitimate cron run into a refusal — and the
 * first version of this function did exactly that, on every invocation.
 *
 * The signature is already verified by the functions gateway before this code runs (the
 * function is deployed with verify_jwt on), so decoding the payload here is a claim check, not
 * a trust decision. `role` is set by Supabase when it mints the key and cannot be self-assigned
 * by an ordinary user session.
 */
function requireServiceRole(req: Request): void {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  const parts = token.split(".");
  let role: unknown = null;
  if (parts.length === 3) {
    try {
      // base64url -> base64, then pad. atob is available in the Deno runtime.
      const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
      const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
      role = (JSON.parse(atob(padded)) as Record<string, unknown>).role;
    } catch {
      role = null;
    }
  }
  if (role !== "service_role") {
    console.error("[nivora] storage-erasure: caller role was", JSON.stringify(role));
    throw new HttpError(403, "This endpoint is for the platform itself.");
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") {
    return toResponse(new HttpError(405, "Use POST."));
  }

  try {
    requireServiceRole(req);
    const db = serviceClient();

    // Through public RPCs, NOT .schema("app"): PostgREST only exposes `public`, and the app
    // schema is deliberately not published. The first version of this called .schema("app")
    // and returned 500 on every invocation — a drainer that cannot read its own queue fails
    // exactly like a drainer with nothing to do.
    const { data: pending, error: readErr } = await db.rpc("storage_erasures_pending", {
      p_limit: BATCH,
      p_max_attempts: MAX_ATTEMPTS,
    });

    if (readErr) {
      throw new HttpError(500, `The erasure queue could not be read: ${readErr.message}`);
    }
    if (!pending || pending.length === 0) {
      return ok({ scanned: 0, purged: 0, failed: 0 }, "Nothing to erase.");
    }

    // Grouped per bucket: the Storage API removes many keys in one call, and a resident's
    // erasure is typically a photo and an ID proof in the same bucket.
    const byBucket = new Map<string, { id: number; path: string }[]>();
    for (const row of pending) {
      const list = byBucket.get(row.bucket) ?? [];
      list.push({ id: row.id as number, path: row.object_path as string });
      byBucket.set(row.bucket, list);
    }

    let purged = 0;
    let failed = 0;

    for (const [bucket, rows] of byBucket) {
      const paths = rows.map((r) => r.path);
      const { error } = await db.storage.from(bucket).remove(paths);

      if (error) {
        // The whole batch is marked, not silently dropped. A bucket that has gone away, a
        // permission change, a transient 5xx — all look the same from here and all deserve to
        // be retried and then surfaced.
        failed += rows.length;
        await db.rpc("storage_erasures_mark", {
          p_ids: rows.map((r) => r.id),
          p_error: error.message,
        });
        continue;
      }

      // `remove` does not fail on a key that is already absent, which is exactly the behaviour
      // this needs: a retry after a half-finished run completes rather than jamming.
      const { error: markErr } = await db.rpc("storage_erasures_mark", {
        p_ids: rows.map((r) => r.id),
        p_error: null,
      });

      if (markErr) {
        // The files ARE gone; only the bookkeeping failed. Say so loudly — the next run will
        // try the same keys, find them absent, and succeed, so this is recoverable but must
        // not be reported as a clean purge.
        failed += rows.length;
        continue;
      }
      purged += rows.length;
    }

    return ok(
      { scanned: pending.length, purged, failed, batch: BATCH },
      failed === 0
        ? `Erased ${purged} object(s).`
        : `Erased ${purged}, ${failed} still pending — see last_error.`,
    );
  } catch (err) {
    return toResponse(err);
  }
});
