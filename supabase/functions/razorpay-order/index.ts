/**
 * POST /functions/v1/razorpay-order
 *
 * Opens a Razorpay ORDER for exactly what the signed-in student still owes this month, and
 * returns the three things a native Checkout sheet needs: the order id, the amount, and the
 * publishable key id.
 *
 * ═══ THE ONE RULE THIS FILE EXISTS TO ENFORCE ═══
 * THE REQUEST BODY IS NEVER READ. Not parsed, not inspected, not logged. There is no amount
 * parameter, no student parameter and no period parameter, because a parameter is a thing an
 * attacker can choose. Every one of those values is derived here, on the server, from the
 * caller's own identity:
 *
 *   who     = auth.getUser(bearer token) → the students row whose user_id is that uuid
 *   period  = the current month
 *   amount  = that student's own outstanding balance, read under their own RLS
 *
 * and then derived a SECOND time, independently, inside the database: rz_open_intent() recomputes
 * the expected amount from the same ledger under the same identity and REFUSES to write the
 * intent row if the figure this function passed disagrees with it. So even a bug here — a stale
 * read, a rounding slip, a future edit that trusts something it should not — cannot result in a
 * ₹1 order for a ₹9000 room: it results in a refusal and a message asking the student to retry.
 *
 * ═══ CREDENTIALS ═══
 *   RAZORPAY_KEY_SECRET is used here, in this process, and is never in a response body. The
 *   phone receives RAZORPAY_KEY_ID (publishable, `rzp_test_…` / `rzp_live_…`) and nothing else.
 *
 *   The SERVICE ROLE KEY IS NOT USED BY THIS FUNCTION AT ALL. It does not need to be:
 *   rz_open_intent is granted to `authenticated` precisely because it derives every sensitive
 *   value itself. Order creation therefore holds no RLS-bypassing credential, which is the
 *   property that keeps the blast radius of this endpoint to "one student, their own rent".
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy razorpay-order        (verify_jwt stays ON — see below)
 *
 * JWT verification is left ON, but it is NOT the authorisation check. The anon key is itself a
 * valid project JWT and would sail through platform verification; auth.getUser() below is what
 * turns "a valid token" into "a specific person", and an anon-key call fails it.
 */
import { callerClient } from "../_shared/supabase.ts";
import { dbError } from "../_shared/errors.ts";
import { HttpError, ok, preflight, toResponse } from "../_shared/http.ts";
import {
  createOrder,
  isConfigured,
  isLiveKey,
  keyId,
  MIN_ORDER_PAISE,
  NOT_CONFIGURED,
  RazorpayApiError,
  toPaise,
} from "../_shared/razorpay.ts";

/** How long an unpaid order is offered again instead of minting a new one. */
const REUSE_WINDOW_MS = 15 * 60 * 1000;

/**
 * The current month as 'YYYY-MM', on the hostel's clock (Asia/Kolkata).
 *
 * IST, not UTC, because that is the month the rest of the product names. rz_open_intent derives
 * the same month from `app.today()`, the app screen derives it from a handset that is in India,
 * and wd_record_payment already dated manual receipts this way. This function used to use UTC to
 * agree with an rz_open_intent that used `current_date`, and the old comment argued a mismatch
 * was harmless because the database would refuse the intent. It was not harmless: between 00:00
 * and 05:30 IST on the 1st, the screen showed one month, the server charged the other, and the
 * confirmation poll watched a month the payment had not been credited to — so a payment that
 * succeeded was reported to the resident as unconfirmed. See
 * db/migrations/2026-09-04-razorpay-ist-day-boundary.sql.
 *
 * en-CA gives ISO order (YYYY-MM-DD) from a formatter, which is the one locale that lets this be
 * a slice instead of three getters.
 */
function currentPeriodMonth(): string {
  const ist = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  return ist.slice(0, 7);
}

interface StudentRow {
  id: string;
  hostel_id: string;
  full_name: string;
  phone: string;
  email: string | null;
  monthly_fee: number | string;
}

interface FeeRow {
  amount_due: number | string | null;
  amount_paid: number | string | null;
}

/**
 * What is still owed this month, in rupees.
 *
 * A PORT OF summariseFee() IN lib/queries/student.ts, kept identical on purpose so the number
 * the phone is charged and the number the web portal shows cannot drift apart. Two rules that
 * look like edge cases and are not:
 *   • NO fee_payments row means nothing has been paid, so the whole monthly fee is due — the
 *     row is only created when money is first recorded.
 *   • A row's own amount_due wins when present, INCLUDING a legitimate 0 (a waived month).
 *     Only null falls back to monthly_fee.
 */
function outstandingRupees(fee: FeeRow | null, monthlyFee: number): number {
  if (!fee) return monthlyFee > 0 ? monthlyFee : 0;
  const due = fee.amount_due == null ? monthlyFee : Number(fee.amount_due);
  const paid = Number(fee.amount_paid ?? 0) || 0;
  if (!Number.isFinite(due) || due <= 0) return 0;
  return Math.max(0, due - paid);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();

  try {
    if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");

    // ── 0. Fail closed when the merchant account was never configured ─────────
    // Before any database work, and before the student is shown a spinner. An app that opens a
    // checkout it cannot complete teaches residents that it lies about money.
    if (!isConfigured()) throw new HttpError(503, NOT_CONFIGURED);

    // ── 1. Who is asking ──────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.toLowerCase().startsWith("bearer ")
      ? authHeader.slice(7).trim()
      : "";
    if (!jwt) throw new HttpError(401, "Please sign in again.");

    const supabase = callerClient(jwt);
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
    const user = userData?.user ?? null;
    // An anon-key "session" lands here: a structurally valid project JWT with no user behind it.
    if (userError || !user) throw new HttpError(401, "Please sign in again.");

    // ── 2. Their student record, read as them ────────────────────────────────
    // students_select admits `user_id = auth.uid()` and nothing else for a resident, so this is
    // RLS-scoped: it cannot return somebody else's row even if the filter were wrong.
    const { data: studentData, error: studentError } = await supabase
      .from("students")
      .select("id, hostel_id, full_name, phone, email, monthly_fee")
      .eq("user_id", user.id)
      .neq("status", "vacated")
      .maybeSingle();
    if (studentError) throw dbError(studentError);
    const student = studentData as StudentRow | null;
    if (!student) {
      throw new HttpError(404, "Your student record could not be found. Contact your warden.");
    }

    const period = currentPeriodMonth();

    // ── 3. THE AMOUNT. Derived here; re-derived by the database in step 6. ────
    const { data: feeData, error: feeError } = await supabase
      .from("fee_payments")
      .select("amount_due, amount_paid")
      .eq("student_id", student.id)
      .eq("period_month", period)
      .maybeSingle();
    if (feeError) throw dbError(feeError);

    const monthlyFee = Number(student.monthly_fee) || 0;
    const remaining = outstandingRupees(feeData as FeeRow | null, monthlyFee);
    if (remaining <= 0) throw new HttpError(409, "Your rent for this month is already settled.");

    const amountPaise = toPaise(remaining);
    if (amountPaise < MIN_ORDER_PAISE) {
      throw new HttpError(
        409,
        "The remaining balance is too small to pay online. Please settle it at the warden desk.",
      );
    }

    // The name Checkout puts at the top of the native sheet. st_hostel_contacts() is the
    // student-facing RPC for this (SECURITY DEFINER, scoped to the caller's own hostel) — a
    // direct select on public.hostels is not something a resident's policies allow.
    // A hostel with no readable contact row is not a reason to refuse a payment, so this
    // degrades to the product name rather than throwing.
    const { data: contactRow } = await supabase.rpc("st_hostel_contacts").maybeSingle();
    const hostelName =
      (contactRow as { hostel_name?: string } | null)?.hostel_name?.trim() || "NIVORA";

    // ── 4. Reuse an order the student already has open ───────────────────────
    // Dismissing the native sheet and tapping Pay again must not mint a new order every time.
    // An unpaid order for the same period and the same amount, minted minutes ago, is still
    // exactly the right thing to pay — and reusing it keeps the intent table honest instead of
    // filling it with abandoned rows that look like failed payments.
    // payment_intents_select scopes this read to the caller's own rows.
    const { data: openIntent } = await supabase
      .from("payment_intents")
      .select("razorpay_order_id")
      .eq("student_id", student.id)
      .eq("period_month", period)
      .eq("status", "created")
      .eq("amount_paise", amountPaise)
      .gte("created_at", new Date(Date.now() - REUSE_WINDOW_MS).toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    let orderId = (openIntent as { razorpay_order_id: string } | null)?.razorpay_order_id ?? null;

    if (!orderId) {
      // ── 5. Ask Razorpay for the order. The only use of the key SECRET. ─────
      let created: { id: string };
      try {
        created = await createOrder({
          amountPaise,
          // No PII: a truncated uuid is a lookup key for us and meaningless to anyone else.
          receipt: `rent_${period}_${student.id.slice(0, 8)}_${Date.now().toString(36)}`.slice(0, 40),
          // For a human reading the Razorpay dashboard. NOTHING on the settlement path reads
          // these — see the warning in _shared/razorpay.ts.
          notes: { purpose: "hostel_rent", period, channel: "mobile" },
        });
      } catch (e) {
        if (e instanceof RazorpayApiError) throw new HttpError(e.status, e.message);
        throw e;
      }
      orderId = created.id;

      // ── 6. The database's own opinion of the amount ───────────────────────
      // Called as the STUDENT, not as service_role. rz_open_intent takes no student and no
      // period; it reads both from auth.uid() and the server clock, recomputes the expected
      // paise from the same ledger, and raises P0001 if what we pass is not exactly that.
      //
      // If this raises, the Razorpay order exists with no intent row behind it. That is the
      // safe direction to fail: an order nobody can pay against (there is no row for
      // rz_record_capture to claim, so a capture would be refused and reconciled by a human)
      // and Razorpay expires unpaid orders on its own.
      const { error: intentError } = await supabase.rpc("rz_open_intent", {
        p_order_id: orderId,
        p_amount_paise: amountPaise,
      });
      if (intentError) throw dbError(intentError);
    }

    return ok({
      order_id: orderId,
      // The publishable key, read from the same environment as the secret that signed the
      // order — so a test order can never be paid with a live key, or the reverse.
      key_id: keyId(),
      amount_paise: amountPaise,
      amount_rupees: remaining,
      currency: "INR",
      period_month: period,
      hostel_name: hostelName,
      student_name: student.full_name,
      test_mode: !isLiveKey(),
      // The student's own contact details, going back to the student's own phone.
      prefill: {
        name: student.full_name,
        email: student.email ?? "",
        contact: student.phone,
      },
    });
  } catch (err) {
    return toResponse(err);
  }
});
