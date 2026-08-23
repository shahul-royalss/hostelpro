"use client";

import * as React from "react";
import { Check } from "lucide-react";
import { ReceiptPrinter, type ReceiptPrinterProps } from "./receipt-printer";

/**
 * THE SUCCESS VISUAL — and nothing else.
 *
 * This file is still the seam it always was: it holds no payment state, calls no
 * action, starts nothing and can undo nothing. It is handed values the server has
 * already confirmed and draws a confirmation of them. pay-rent-sheet.tsx renders
 * it through a `next/dynamic` import and never looks inside.
 *
 * What it draws now is the user's thermal receipt dispenser (receipt-printer.tsx
 * + receipt-printer.module.css), ported from the stand-alone prototype in
 * `reciept animation/`. It is loaded dynamically for the same two reasons the
 * spring-and-checkmark version was:
 *   • the machine's CSS and markup are dead weight on every route that never
 *     opens the pay sheet, and this app's navigation budget was fought for;
 *   • it is only ever rendered after a payment has already succeeded, the one
 *     moment in the flow where a chunk fetch costs nothing.
 *
 * DECORATION OVER A COMPLETED TRANSACTION. By the time this renders, the money
 * has moved and the ledger has been credited by a signed webhook — the sheet
 * polls the server and does not believe Checkout's callback. So the printer is
 * wrapped in an error boundary and every prop below is optional: if the machine
 * throws for any reason, the student still sees an unambiguous "paid", and the
 * receipt card underneath it (payment-receipt.tsx) still carries the copyable
 * payment id. A broken ornament must never read as a failed payment.
 */

export interface PaymentSuccessAnimationProps extends ReceiptPrinterProps {
  /** Plain-language headline. Also the whole of the fallback, so it should be
   *  true on its own without the receipt: "₹4,500 paid". */
  label?: string;
}

/**
 * Static, motionless, dependency-free. This is what a student sees if the
 * printer throws — the same fact, drawn the boring way.
 */
function SuccessFallback({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center gap-3 py-2">
      <span className="flex h-[72px] w-[72px] items-center justify-center rounded-full bg-teal text-white shadow-glass-lg">
        <Check className="h-9 w-9" strokeWidth={3} aria-hidden />
      </span>
      <p className="text-[17px] font-semibold text-navy">{label}</p>
    </div>
  );
}

class ReceiptBoundary extends React.Component<
  { fallback: React.ReactNode; children: React.ReactNode },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(error: unknown) {
    // Swallowed on purpose. There is no recovery to attempt and nothing the
    // student can do about it: the payment is already credited, and this
    // component only ever drew a picture of that fact. Logged, not surfaced.
    if (process.env.NODE_ENV !== "production") {
      console.error("[payment-success] receipt printer failed to render:", error);
    }
  }

  render() {
    return this.state.failed ? this.props.fallback : this.props.children;
  }
}

export function PaymentSuccessAnimation({
  label = "Payment successful",
  ...receipt
}: PaymentSuccessAnimationProps) {
  return (
    <div className="flex flex-col items-center py-1">
      {/*
        The announcement is deliberately short and separate from the slip. The
        printed receipt below is real text and a screen reader can read every
        line of it in browse mode, but a live region should say one thing when
        it appears, not recite a whole document — and the receipt card further
        down the sheet repeats these values anyway.
      */}
      <p className="sr-only" role="status" aria-live="polite">
        {label}
      </p>

      <ReceiptBoundary fallback={<SuccessFallback label={label} />}>
        <ReceiptPrinter {...receipt} />
      </ReceiptBoundary>
    </div>
  );
}
