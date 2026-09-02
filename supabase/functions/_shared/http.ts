/**
 * HTTP envelope shared by every NIVORA Edge Function.
 *
 * The response shape is deliberately identical to the web app's `ActionResult<T>`
 * (lib/types.ts) so a Dart client and a React client read the same JSON:
 *
 *   { "ok": true,  "data": {...}, "message": "..." }
 *   { "ok": false, "error": "...", "fieldErrors": { "email": ["..."] } }
 *
 * Every response carries `Cache-Control: no-store`. Two of these endpoints return a
 * one-time temporary password in the body; nothing on the path back to the phone —
 * proxy, CDN or HTTP cache — may keep a copy of it.
 */

export const CORS_HEADERS: Record<string, string> = {
  // The Flutter app sends no Origin at all (native HTTP, not a browser). "*" is here so the
  // same endpoints can also be called from the Next.js app during a migration. No cookies are
  // read or set by these functions, so there is nothing for a cross-site caller to ride on:
  // authorisation comes from a bearer token the caller must already hold.
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const BASE_HEADERS: Record<string, string> = {
  ...CORS_HEADERS,
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, private",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export type FieldErrors = Record<string, string[]>;

/** An error that already knows the HTTP status and the message a person should see. */
export class HttpError extends Error {
  readonly status: number;
  readonly fieldErrors?: FieldErrors;
  /** Extra top-level keys merged into the failure body (used by the rollback report). */
  readonly extra?: Record<string, unknown>;
  /**
   * Response headers this failure needs on the wire. Added for `Retry-After` on a 429: a
   * throttle that only says "wait" in prose is unreadable to anything but a human, and the
   * status line is the half of the answer that generic HTTP tooling understands.
   */
  readonly headers?: Record<string, string>;

  constructor(
    status: number,
    message: string,
    opts: { fieldErrors?: FieldErrors; extra?: Record<string, unknown>; headers?: Record<string, string> } = {},
  ) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.fieldErrors = opts.fieldErrors;
    this.extra = opts.extra;
    this.headers = opts.headers;
  }
}

export function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, ...headers } });
}

export function ok<T>(data: T, message?: string): Response {
  return jsonResponse({ ok: true, data, message }, 200);
}

export function fail(
  error: string,
  status = 400,
  opts: { fieldErrors?: FieldErrors; extra?: Record<string, unknown>; headers?: Record<string, string> } = {},
): Response {
  return jsonResponse({ ok: false, error, fieldErrors: opts.fieldErrors, ...(opts.extra ?? {}) }, status, opts.headers ?? {});
}

export function preflight(): Response {
  return new Response("ok", { headers: CORS_HEADERS });
}

/** Reject anything that is not a POST of JSON, before any work is done. */
export async function readJsonBody(req: Request, maxBytes = 12 * 1024 * 1024): Promise<Record<string, unknown>> {
  if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new HttpError(413, "That request is too large.");
  let raw: string;
  try {
    raw = await req.text();
  } catch {
    throw new HttpError(400, "Could not read the request.");
  }
  if (raw.length > maxBytes) throw new HttpError(413, "That request is too large.");
  if (!raw.trim()) return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
    return parsed as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "Could not read the request.");
  }
}

/**
 * Single exit point for every handler. Known errors keep their message; anything else
 * becomes a generic message and is logged server-side only (checklist §18 — the client is
 * never told which internal thing broke).
 */
export function toResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return fail(err.message, err.status, { fieldErrors: err.fieldErrors, extra: err.extra, headers: err.headers });
  }
  console.error("[nivora] unhandled:", err instanceof Error ? `${err.name}: ${err.message}` : String(err).slice(0, 500));
  return fail("Something went wrong. Please try again.", 500);
}
