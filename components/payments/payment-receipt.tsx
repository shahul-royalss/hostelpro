"use client";

import * as React from "react";
import { Check, Copy } from "lucide-react";
import { cn, formatDate, formatINR, formatPeriodMonth } from "@/lib/utils";

/**
 * The receipt shown after a successful payment. Pure presentation — every value
 * comes from what the server confirmed, none of it is computed here.
 *
 * The payment id is the student's proof if anything ever has to be traced with
 * the hostel or with Razorpay, so it is copyable rather than merely printed.
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
  className,
}: {
  amountRupees: number;
  period: string;
  paymentId: string | null;
  method: string | null;
  hostelName?: string;
  studentName?: string;
  paidAt?: Date;
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

  return (
    <div className={cn("rounded-card border border-line bg-white/70 px-4 py-2", className)}>
      <div className="divide-y divide-line">
        <Row label="Amount paid" value={<span className="text-[15px] font-bold">{formatINR(amountRupees)}</span>} />
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
