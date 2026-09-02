"use client";

import * as React from "react";
import { Check, Copy, Undo2 } from "lucide-react";
import { cn, formatDate, formatINR, formatPeriodMonth } from "@/lib/utils";

/**
 * The receipt shown after a successful payment. Pure presentation — every value
 * comes from what the server confirmed, none of it is computed here.
 *
 * The payment id is the student's proof if anything ever has to be traced with
 * the hostel or with Razorpay, so it is copyable rather than merely printed.
 *
 * ═══ REFUNDS ═══
 * The headline of this card is "Amount paid". A receipt that keeps announcing the
 * gross after part of it has gone back is not a stale receipt, it is a wrong one —
 * and it is the copy the resident keeps. So when a refund is known, it is stated
 * ABOVE the figure it qualifies, not filed under it.
 *
 * ONLY SETTLED REFUNDS. `public.payment_refunds.status` is a three-value lifecycle
 * (`pending` / `processed` / `failed`) and only `processed` means the money has
 * left — it is the one `rz_reverse_fee()` acts on. A pending refund is an
 * instruction; printing it as money returned would send a resident to a bank
 * statement that disagrees with this document. Callers pass the SETTLED figure, in
 * rupees; the table stores `amount_paise`, and that conversion belongs at the read,
 * not here.
 *
 * BOTH FIGURES, NEVER THEIR DIFFERENCE. `amountRupees` and `refundedRupees` are
 * each printed verbatim and neither is adjusted by the other. The net is not a
 * column anywhere in this schema, so this component does not state one — the same
 * rule the Flutter receipt follows (nivora_app/lib/features/payments/receipt.dart).
 *
 * The props are optional and the current callers in pay-rent-sheet.tsx pass
 * nothing: that sheet shows a receipt for a payment made seconds ago, which cannot
 * have been refunded yet. They are here for the history and dispute views that read
 * a settled payment back.
 */

const METHOD_LABEL: Record<string, string> = {
  upi: "UPI",
  card: "Card",
  netbanking: "Net banking",
  wallet: "Wallet",
  emi: "EMI",
  paylater: "Pay later",
};

function Row({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2.5">
      <span className="shrink-0 text-[13px] text-muted">{label}</span>
      <span className={cn("min-w-0 break-words text-right text-[13px] font-medium text-navy", mono && "font-mono text-[12px]")}>
        {value}
      </span>
    </div>
  );
}

export function PaymentReceipt({
  amountRupees,
  period,
  paymentId,
  method,
  hostelName,
  studentName,
  paidAt,
  refundedRupees,
  refundedAt,
  className,
}: {
  amountRupees: number;
  period: string;
  paymentId: string | null;
  method: string | null;
  hostelName?: string;
  studentName?: string;
  paidAt?: Date;
  /**
   * What came BACK, in rupees, and only from refunds whose status is `processed`.
   * Null/undefined/0 draws nothing — a zero refund is not one.
   */
  refundedRupees?: number | null;
  /** `processed_at`. Absent prints the notice without a date, never with a guessed one. */
  refundedAt?: Date | null;
  className?: string;
}) {
  const [copied, setCopied] = React.useState(false);
  const timer = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  React.useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  async function copyId() {
    if (!paymentId) return;
    try {
      await navigator.clipboard.writeText(paymentId);
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard blocked (insecure context / permission) — the id is still on screen */
    }
  }

  // > 0 rather than != null: `payment_refunds.amount_paise` carries a check constraint
  // saying it is positive, so a zero here is an absent value that arrived as a number, and
  // "Refunded ₹0" on a receipt is worse than no line at all.
  const refunded =
    typeof refundedRupees === "number" && Number.isFinite(refundedRupees) && refundedRupees > 0
      ? refundedRupees
      : null;

  return (
    <div className={cn("rounded-card border border-line bg-white/70 px-4 py-2", className)}>
      {refunded !== null ? (
        // Above the amount, not below it: this changes what the headline MEANS, and a
        // qualifier read after the figure has already been taken in arrives too late.
        //
        // sand-soft / sand-deep, which this app already uses for "worth knowing, nothing
        // has gone wrong" — it is the exact pairing on the "Payment received, it can take a
        // minute to show" panel in pay-rent-sheet.tsx. Not the error red: nobody did
        // anything wrong when money is returned. (The Flutter app reaches for its `info`
        // blue here; this palette has no blue, and sand is its nearest non-alarm tone.)
        <div className="mb-2 mt-2 flex items-start gap-2 rounded-[10px] bg-sand-soft px-3 py-2 text-sand-deep">
          <Undo2 className="mt-0.5 h-3.5 w-3.5 shrink-0" strokeWidth={2} aria-hidden="true" />
          <p className="text-[12px] font-medium">
            {formatINR(refunded)} of this payment was refunded
            {refundedAt ? ` on ${formatDate(refundedAt, "d MMM yyyy")}` : ""}.
          </p>
        </div>
      ) : null}
      <div className="divide-y divide-line">
        <Row label="Amount paid" value={<span className="text-[15px] font-bold">{formatINR(amountRupees)}</span>} />
        {refunded !== null ? <Row label="Refunded" value={formatINR(refunded)} /> : null}
        <Row label="For" value={`${formatPeriodMonth(period)} rent`} />
        {studentName ? <Row label="Resident" value={studentName} /> : null}
        {hostelName ? <Row label="Hostel" value={hostelName} /> : null}
        {method ? <Row label="Paid by" value={METHOD_LABEL[method] ?? method} /> : null}
        <Row label="Date" value={formatDate(paidAt ?? new Date(), "d MMM yyyy")} />
        {paymentId ? (
          <div className="flex items-center justify-between gap-3 py-2.5">
            <span className="shrink-0 text-[13px] text-muted">Payment ID</span>
            <button
              type="button"
              onClick={copyId}
              className="flex min-w-0 items-center gap-1.5 rounded-[10px] px-1.5 py-1 font-mono text-[12px] text-navy transition-colors hover:bg-navy/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30"
              aria-label={copied ? "Payment ID copied" : "Copy payment ID"}
            >
              <span className="truncate">{paymentId}</span>
              {copied ? (
                <Check className="h-3.5 w-3.5 shrink-0 text-teal" />
              ) : (
                <Copy className="h-3.5 w-3.5 shrink-0 text-muted" />
              )}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}
