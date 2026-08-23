"use client";

import * as React from "react";
import { IndianRupee } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatINR } from "@/lib/utils";
import { PayRentSheet } from "./pay-rent-sheet";

/**
 * Drop-in entry point for the student's fees view.
 *
 *   <PayRentButton amountDue={fee.remaining} period={period} />
 *
 * That is the whole integration. Both props are DISPLAY HINTS for the collapsed
 * button — the sheet asks the server for the real figure the moment it opens an
 * order, and the server derives it from the student's own ledger without reading
 * anything the browser sent. Passing a wrong number here changes the label and
 * nothing else; it cannot change what is charged.
 *
 * Renders nothing when there is nothing to pay, so it is safe to place
 * unconditionally.
 *
 * Nothing third-party is fetched by mounting this. checkout.razorpay.com is
 * requested for the first time when someone taps Pay inside the sheet.
 */
export function PayRentButton({
  amountDue,
  period,
  variant = "default",
  className,
  label,
}: {
  amountDue?: number | null;
  /** YYYY-MM */
  period?: string;
  variant?: "default" | "secondary";
  className?: string;
  label?: string;
}) {
  const [open, setOpen] = React.useState(false);

  if (amountDue !== undefined && amountDue !== null && amountDue <= 0) return null;

  const due = amountDue ?? undefined;

  return (
    <>
      <Button variant={variant} size="xl" className={className} onClick={() => setOpen(true)}>
        <IndianRupee className="h-4 w-4" strokeWidth={2} />
        {label ?? (due ? `Pay ${formatINR(due)} now` : "Pay rent online")}
      </Button>
      <PayRentSheet open={open} onOpenChange={setOpen} amountDueHint={due} periodHint={period} />
    </>
  );
}
