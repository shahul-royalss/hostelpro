/**
 * POST /functions/v1/email-verification   { "action": "status" }
 *
 * ONE ACTION. It answers "has this account proved its address?", and — because it is the only
 * thing standing where the answer can be turned into a row — it also RECORDS the proof when it
 * finds one.
 *
 * ═══ WHY THIS FUNCTION SHRANK ═══
 *
 * It used to have three actions: `send` mailed a 6-digit code, `check` verified it, `status`
 * reported. `send` and `check` are gone as of 2026-09-01, and the reason is the failure the
 * owner photographed: "The Nivora server did not answer".
 *
 * That sentence is the phone's 15s deadline expiring on THIS function. The sending path was
 * app -> here -> GoTrue -> mail, and this instance is a free-tier NANO that flips PostgREST and
 * Auth to Unhealthy at ~72% RAM. So the feature that proves an address was unavailable exactly
 * when the platform was least healthy — and it was unavailable because we had put our own
 * service in the middle of a path that did not need one.
 *
 * A confirmation LINK is composed and sent by GoTrue. The app calls /auth/v1/otp directly, the
 * user clicks in their mail app, and GoTrue verifies the token itself. app -> GoTrue -> mail:
 * one fewer hop, and the hop removed is the one that kept failing.
 *
 * ═══ SO WHY IS THERE STILL A SERVER HERE AT ALL ═══
 *
 * Because `public.users.email_verified_at` is written by the service role and by nothing else —
 * app.users_update_guard raises 42501 for every other writer, including the account holder and
 * the super admin. Something that has SEEN GoTrue accept the link has to be the thing that
 * writes it, and that something cannot be the phone. See confirmEmailFromLink() and
 * public.email_link_proof().
 *
 * This function is no longer on the critical path of anything. If it does not answer, no mail
 * is lost and no link stops working: the click is already recorded in GoTrue's own tables, and
 * the next `status` — the app sends one every time it returns to the foreground — picks it up.
 * That is the difference between a hop that can fail and a hop that must not.
 *
 * ═══ THE ADDRESS IS NEVER TAKEN FROM THE BODY ═══
 *
 * There is no `email` parameter and no `userId` parameter. Everything is read from the caller's
 * own profile row, resolved with the service client after GoTrue verified the bearer token.
 *
 * ═══ WHY requireSession AND NOT requireCaller ═══
 *
 * requireCaller refuses a caller who still owes a forced password change. Both orders of
 * "change your password" and "verify your address" are legitimate and the router today does the
 * password first, but gating verification behind the password change would mean that if the
 * order is ever reversed the door locks with the key behind it — the same trap requireSession
 * was split out to avoid for the second factor. The role gate is not wanted here either: every
 * role verifies the same way.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy email-verification        (verify_jwt stays ON)
 *
 * ONE PROJECT SETTING MUST BE RIGHT OR NO LINK EVER ARRIVES — see docs/edge-functions.md:
 * the Magic Link email template must contain {{ .ConfirmationURL }}. That is Supabase's STOCK
 * template, so the default is correct; it is listed because this project's previous, code-based
 * flow asked the owner to put {{ .Token }} in that template, and a template edited to show only
 * the code would now send mail with nothing to click.
 */
import { requireSession } from "../_shared/caller.ts";
import { fail, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { confirmEmailFromLink, isReachableAddress } from "../_shared/verification.ts";

/** The body carries one short string and nothing else. */
const MAX_BODY_BYTES = 4 * 1024;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();

  try {
    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const action = body["action"];
    // The session is resolved BEFORE the action is dispatched, so an unauthenticated caller
    // gets the same 401 whichever action they name and cannot probe for which ones exist.
    const { caller } = await requireSession(req);

    switch (action) {
      case "status": {
        // Cheap, and side-effect free for anyone already verified. For anyone who is not, it
        // asks GoTrue's own tables whether the link has been opened and stamps the column if it
        // has — which is what makes the banner disappear when the user comes back from their
        // mail app without them having to find a button.
        const { verified, verifiedAt } = await confirmEmailFromLink(caller);
        return ok({
          email: caller.email,
          verified,
          verifiedAt,
          required: isReachableAddress(caller.email) && !verified,
        });
      }

      default:
        // Named actions, so an old build calling `send` or `check` gets a sentence instead of a
        // silent 400. Those two moved to GoTrue; there is nothing here to route them to.
        return fail(
          "Unknown action. This version of Nivora verifies email addresses with a link — update the app.",
          400,
        );
    }
  } catch (err) {
    return toResponse(err);
  }
});
