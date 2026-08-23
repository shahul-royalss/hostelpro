"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertRole, assertWritableContext, errorMessage } from "@/lib/permissions";
import { audit } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { fail, ok, type ActionResult } from "@/lib/types";
import { getMyFeeForPeriod, getMyStudent, summariseFee } from "@/lib/queries/student";
import {
  isLiveKey,
  isRazorpayConfigured,
  MIN_ORDER_PAISE,
  razorpayClient,
  razorpayKeyId,
  toPaise,
} from "@/lib/razorpay";
import { toPeriodMonth } from "@/lib/utils";

/**
 * Student rent payment — the two actions a browser is allowed to call.
 *
 * EVERY export in a `"use server"` file is a live HTTP endpoint that anyone who
 * can reach the app may invoke with arguments of their choosing. That is why the
 * settlement code — the part that actually credits a fee — is NOT in this file.
 * It lives inside app/api/webhooks/razorpay/route.ts as module-local functions
 * that nothing can call except a delivery whose HMAC signature has verified.
 *
 * The two actions here are, deliberately, unable to move money:
 *
 *   createRentOrder()      takes NO arguments at all. The student is the session,
 *                          the period is the current month, and the amount is
 *                          this server's reading of that student's own balance —
 *                          re-derived a second time inside rz_open_intent() before
 *                          the row is written. There is no parameter to tamper with.
 *   getRentPaymentStatus() a read. RLS scopes it to the caller's own rows.
 *
 * Order id → Razorpay is the only thing that flows outward, and the key SECRET
 * stays behind lib/razorpay.ts's `server-only` import in every case.
 */

const NOT_CONFIGURED = "Online payment isn't set up yet. You can still pay at the warden desk.";
const ORDER_ID_RE = /^order_[A-Za-z0-9]{6,30}$/;

/** How long an unpaid order is offered again instead of minting a new one. */
const REUSE_WINDOW_MS = 15 * 60 * 1000;

export interface RentOrder {
  orderId: string;
  /** publishable key id — the only Razorpay credential a browser ever sees */
  keyId: string;
  amountPaise: number;
  amountRupees: number;
  currency: "INR";
  /** YYYY-MM */
  period: string;
  hostelName: string;
  studentName: string;
  /** true when the merchant is on test keys — the sheet says so out loud */
  testMode: boolean;
  prefill: { name: string; email: string; contact: string };
}

export type RentPaymentState = "pending" | "captured" | "credited" | "failed";

export interface RentPaymentStatus {
  state: RentPaymentState;
  paymentId: string | null;
  method: string | null;
  amountRupees: number;
  period: string;
  failureReason: string | null;
}

/**
 * Open a Razorpay order for exactly what this student still owes this month.
 *
 * Takes nothing. Returns everything Checkout needs, and nothing it does not.
 */
export async function createRentOrder(): Promise<ActionResult<RentOrder>> {
  try {
    // Role + hostel + Hard rule §4.4 (expired subscription ⇒ read-only).
    const { user, ctx } = await assertWritableContext("student");

    if (!isRazorpayConfigured()) return fail(NOT_CONFIGURED);

    const rl = await rateLimit(`payments:order:${user.id}`, 8, 900);
    if (!rl.allowed) {
      return fail(`Too many payment attempts. Please try again in ${rl.retryAfterSeconds} seconds.`);
    }

    const supabase = await createClient();
    const period = toPeriodMonth();

    // RLS-scoped: students_select lets a student read their own row and no other.
    const student = await getMyStudent(supabase, user.id);
    if (!student) return fail("Your student record could not be found. Contact your warden.");

    // THE AMOUNT. Derived here from the student's own ledger, using the same
    // summariseFee() the fee card on their home screen renders from, so the number
    // they were shown and the number they are charged cannot drift apart.
    const summary = summariseFee(await getMyFeeForPeriod(supabase, student.id, period), Number(student.monthly_fee));
    if (summary.remaining <= 0) return fail("Your rent for this month is already settled.");

    const amountPaise = toPaise(summary.remaining);
    if (amountPaise < MIN_ORDER_PAISE) {
      return fail("The remaining balance is too small to pay online. Please settle it at the warden desk.");
    }

    // Dismissing the Checkout modal and tapping Pay again should not mint a new
    // order every time. An unpaid order for the same period and the same amount,
    // minted minutes ago, is still exactly the right thing to pay.
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
      const order = await razorpayClient().orders.create({
        amount: amountPaise,
        currency: "INR",
        // ≤ 40 chars, unique. No PII: a truncated student uuid is a lookup key for
        // us and meaningless to anyone else.
        receipt: `rent_${period}_${student.id.slice(0, 8)}_${Date.now().toString(36)}`.slice(0, 40),
        // Notes are echoed back on the webhook. They are for a human reading the
        // Razorpay dashboard — NOTHING on the settlement path ever reads them,
        // because a note is attacker-influencable metadata, not a source of truth.
        notes: { purpose: "hostel_rent", period },
      });
      orderId = String(order.id);
      if (!ORDER_ID_RE.test(orderId)) return fail("Payment provider returned an unexpected order.");

      // Second, independent derivation of the same amount — this time inside the
      // database, from the same ledger, under the caller's own identity. If the
      // two disagree (a warden banked cash in between) the row is refused and the
      // student is asked to start again rather than being charged a stale figure.
      const { error } = await supabase.rpc("rz_open_intent", {
        p_order_id: orderId,
        p_amount_paise: amountPaise,
      });
      if (error) return fail(errorMessage(error));

      await audit("payment.order.created", {
        targetType: "student",
        targetId: student.id,
        hostelId: ctx.hostel.id,
        meta: { orderId, period, amountPaise },
      });
    }

    return ok({
      orderId,
      keyId: razorpayKeyId(),
      amountPaise,
      amountRupees: summary.remaining,
      currency: "INR" as const,
      period,
      hostelName: ctx.hostel.name,
      studentName: student.full_name,
      testMode: !isLiveKey(),
      // The student's own contact details, going back to the student's own browser.
      prefill: {
        name: student.full_name,
        email: student.email ?? "",
        contact: student.phone ?? "",
      },
    });
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/**
 * Where a payment has got to. Polled by the sheet after Checkout closes.
 *
 * A read and only a read: nothing here can advance a payment's state. The state
 * advances when the signed webhook says so, and this action reports what it finds.
 */
export async function getRentPaymentStatus(input: { orderId: string }): Promise<ActionResult<RentPaymentStatus>> {
  const orderId = typeof input?.orderId === "string" ? input.orderId.trim() : "";
  if (!ORDER_ID_RE.test(orderId)) return fail("We couldn't find that payment.");

  try {
    const user = await assertRole("student");

    // Polling is cheap but not free; a stuck client must not be able to spin.
    const rl = await rateLimit(`payments:status:${user.id}`, 120, 300);
    if (!rl.allowed) return fail("Please wait a moment before checking again.");

    const supabase = await createClient();
    // payment_intents_select scopes this to student_id = app.current_student_id().
    // A student cannot read another student's payment by guessing an order id.
    const { data, error } = await supabase
      .from("payment_intents")
      .select("status, credited_at, razorpay_payment_id, method, amount_paise, period_month, failure_reason")
      .eq("razorpay_order_id", orderId)
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    if (!data) return fail("We couldn't find that payment.");

    const row = data as {
      status: "created" | "captured" | "failed" | "expired";
      credited_at: string | null;
      razorpay_payment_id: string | null;
      method: string | null;
      amount_paise: number;
      period_month: string;
      failure_reason: string | null;
    };

    const state: RentPaymentState =
      row.credited_at ? "credited" : row.status === "captured" ? "captured" : row.status === "failed" ? "failed" : "pending";

    if (state === "credited") {
      // The ledger moved. Refresh the surfaces that show a fee balance. The client
      // stops polling on this state, so this runs once per payment.
      revalidatePath("/student");
      revalidatePath("/warden/fees");
      revalidatePath("/warden");
      revalidatePath("/owner");
      revalidatePath("/owner/students");
    }

    return ok({
      state,
      paymentId: row.razorpay_payment_id,
      method: row.method,
      amountRupees: Math.round(Number(row.amount_paise)) / 100,
      period: row.period_month,
      failureReason: row.failure_reason,
    });
  } catch (e) {
    return fail(errorMessage(e));
  }
}
