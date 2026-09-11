/**
 * POST /functions/v1/push-send   { "notification_ids": ["uuid", ...] }
 *
 * Turns rows of public.notifications into banners on phones, through Firebase Cloud Messaging.
 *
 * ═══ WHO CALLS THIS ═══
 * app.notifications_dispatch_push(), an AFTER INSERT ... FOR EACH STATEMENT trigger on
 * public.notifications, via pg_net. One call per insert statement, ids batched 200 at a time,
 * and only for users who actually have a device registered — a PG where nobody has opened the
 * app yet makes no calls at all. pg_net queues inside the transaction and sends after it
 * commits, so a rolled-back payment cannot produce a push.
 *
 * ═══ WHY THERE IS NO SHARED SECRET ═══
 * The obvious design gives the trigger a secret this function checks. That secret would have to
 * live in two places (Postgres and the function environment) and be rotated in both. It is not
 * needed, because REPLAY IS ALREADY IMPOSSIBLE: the first thing this does is CLAIM the rows —
 *
 *     update notifications set pushed_at = now() where id in (...) and pushed_at is null
 *
 * — and only the rows that update are sent. A second call with the same ids claims nothing and
 * sends nothing. The worst an attacker who guesses a uuid can do is make one notification reach
 * the person it was already addressed to, once, and only within the freshness window below.
 *
 * FRESHNESS. Rows older than 15 minutes are never sent, so a leaked id cannot be replayed
 * tomorrow, and a backlog that built up while FCM was unconfigured does not arrive in one burst
 * the moment somebody sets the key.
 *
 * ═══ IT IS A NO-OP UNTIL FIREBASE EXISTS ═══
 * FCM_SERVICE_ACCOUNT is the JSON of a Firebase service-account key. Until it is set this
 * returns 200 with { skipped: "not_configured" } and claims nothing, so the notifications are
 * still written, still visible in the app, and still sendable later. The database trigger never
 * looks at the response.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy push-send
 *   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
 */
import { createClient } from "npm:@supabase/supabase-js@2";

/** Rows older than this are never pushed. See the header. */
const FRESH_SECONDS = 15 * 60;

/** How many FCM requests are in flight at once. FCM v1 has no multicast in the REST API. */
const CONCURRENCY = 20;

/**
 * The channel the Android client creates at startup. It MUST match, or Android 8+ drops the
 * notification silently — no error, no banner, nothing in logcat that names the cause.
 */
const ANDROID_CHANNEL = "nivora_default";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

interface NotificationRow {
  id: string;
  user_id: string;
  title: string;
  body: string | null;
  link: string | null;
  type: string;
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw || raw.trim().length === 0) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.client_email || !parsed.private_key || !parsed.project_id) return null;
    return parsed;
  } catch {
    console.error("[nivora] FCM_SERVICE_ACCOUNT is set but is not valid JSON");
    return null;
  }
}

function admin() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("NIVORA_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / service-role key missing from the environment.");
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GOOGLE OAUTH — a service-account JWT exchanged for an access token
// ─────────────────────────────────────────────────────────────────────────────

let cachedToken: { value: string; expiresAt: number } | null = null;

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** PEM (PKCS#8) → a CryptoKey that can sign RS256. */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // 60s of slack: a token that expires mid-flight fails the send rather than being refreshed.
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = base64url(new TextEncoder().encode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    await importPrivateKey(sa.private_key),
    new TextEncoder().encode(header + "." + claim),
  ));
  const assertion = header + "." + claim + "." + base64url(signature);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.access_token) {
    throw new Error("Google refused the service account: " + res.status + " " + JSON.stringify(json).slice(0, 300));
  }
  cachedToken = { value: json.access_token as string, expiresAt: now + Number(json.expires_in ?? 3600) };
  return cachedToken.value;
}

// ─────────────────────────────────────────────────────────────────────────────
// SENDING
// ─────────────────────────────────────────────────────────────────────────────

/** Whether FCM's refusal means this token is dead and should be forgotten. */
function tokenIsDead(status: number, payload: string): boolean {
  if (status === 404) return true; // UNREGISTERED
  if (status === 403) return true; // SENDER_ID_MISMATCH — the token belongs to another project
  return status === 400 && /registration token|INVALID_ARGUMENT/i.test(payload);
}

async function sendOne(
  token: string,
  row: NotificationRow,
  sa: ServiceAccount,
  bearer: string,
): Promise<{ token: string; ok: boolean; dead: boolean }> {
  const res = await fetch(
    "https://fcm.googleapis.com/v1/projects/" + sa.project_id + "/messages:send",
    {
      method: "POST",
      headers: { Authorization: "Bearer " + bearer, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: row.title, body: row.body ?? "" },
          // The DATA half is what the app routes on when the person taps. Every value must be
          // a string: FCM v1 rejects a data payload with any other JSON type.
          data: {
            link: row.link ?? "",
            type: row.type,
            notification_id: row.id,
          },
          android: {
            priority: "HIGH",
            notification: { channel_id: ANDROID_CHANNEL },
          },
          apns: {
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  if (res.ok) return { token, ok: true, dead: false };
  const text = await res.text().catch(() => "");
  const dead = tokenIsDead(res.status, text);
  if (!dead) console.error("[nivora] FCM " + res.status + ": " + text.slice(0, 300));
  return { token, ok: false, dead };
}

/** Run `jobs` with at most [CONCURRENCY] in flight. */
async function pooled<T>(jobs: (() => Promise<T>)[]): Promise<T[]> {
  const out: T[] = [];
  let i = 0;
  const workers = Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, async () => {
    while (i < jobs.length) {
      const mine = i++;
      out[mine] = await jobs[mine]();
    }
  });
  await Promise.all(workers);
  return out;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });

  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed." }, 405);

  try {
    const body = await req.json().catch(() => ({})) as { notification_ids?: unknown };
    const ids = Array.isArray(body.notification_ids)
      ? body.notification_ids.filter((v): v is string => typeof v === "string").slice(0, 500)
      : [];
    if (ids.length === 0) return json({ ok: true, sent: 0 });

    const sa = serviceAccount();
    if (!sa) {
      // Nothing is claimed, so these can still be sent once Firebase exists.
      return json({ ok: true, sent: 0, skipped: "not_configured" });
    }

    const db = admin();

    // CLAIM FIRST. `pushed_at is null` makes this the only call that can send these rows.
    const cutoff = new Date(Date.now() - FRESH_SECONDS * 1000).toISOString();
    const { data: claimed, error: claimError } = await db
      .from("notifications")
      .update({ pushed_at: new Date().toISOString() })
      .in("id", ids)
      .is("pushed_at", null)
      .gte("created_at", cutoff)
      .select("id, user_id, title, body, link, type");
    if (claimError) throw new Error("claim failed: " + claimError.message);

    const rows = (claimed ?? []) as NotificationRow[];
    if (rows.length === 0) return json({ ok: true, sent: 0, claimed: 0 });

    const { data: devices, error: deviceError } = await db
      .from("push_devices")
      .select("token, user_id")
      .in("user_id", Array.from(new Set(rows.map((r) => r.user_id))));
    if (deviceError) throw new Error("device lookup failed: " + deviceError.message);

    const byUser = new Map<string, string[]>();
    for (const d of (devices ?? []) as { token: string; user_id: string }[]) {
      const list = byUser.get(d.user_id) ?? [];
      list.push(d.token);
      byUser.set(d.user_id, list);
    }

    const bearer = await accessToken(sa);
    const jobs: (() => Promise<{ token: string; ok: boolean; dead: boolean }>)[] = [];
    for (const row of rows) {
      for (const token of byUser.get(row.user_id) ?? []) {
        jobs.push(() => sendOne(token, row, sa, bearer));
      }
    }

    const results = await pooled(jobs);
    const sent = results.filter((r) => r.ok).length;
    const dead = Array.from(new Set(results.filter((r) => r.dead).map((r) => r.token)));

    if (dead.length) {
      // A token FCM has disowned will never work again; keeping it means paying for a failed
      // request on every future notification to that person.
      await db.from("push_devices").delete().in("token", dead);
    }

    return json({ ok: true, claimed: rows.length, sent, pruned: dead.length });
  } catch (e) {
    console.error("[nivora] push-send:", e instanceof Error ? e.message : String(e));
    // 200, deliberately. The caller is a database trigger that cannot act on a failure, and a
    // non-2xx only fills net._http_response with noise.
    return json({ ok: false, error: "push failed" });
  }
});
