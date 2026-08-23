"use client";

import * as React from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { AlertTriangle, Clock, Lock, ShieldCheck } from "lucide-react";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { createRentOrder, getRentPaymentStatus, type RentPaymentStatus } from "@/lib/actions/payments";
import { formatINR, formatPeriodMonth } from "@/lib/utils";
import { PaymentReceipt } from "./payment-receipt";
import { loadRazorpayCheckout, openRazorpayCheckout, type RazorpayCheckoutInstance } from "./razorpay-checkout";

/**
 * The rent payment sheet.
 *
 * Nothing on this screen decides what is charged. The Pay button calls a server
 * action that takes no arguments; the amount comes back from the server, having
 * been read from the student's own ledger and re-derived a second time inside the
 * database. `amountDueHint` below is a label for the collapsed button — the sheet
 * replaces it with the server's figure the moment the order exists, and the two
 * are never allowed to disagree silently.
 *
 * Confirmation is likewise not this component's to give. Checkout's success
 * callback only means "the browser was told it worked"; the fee is credited when
 * the signed webhook arrives, so the sheet polls a read-only action until the
 * server says `credited` and shows the receipt then, not before.
 */

/** Swappable success visual — see payment-success-animation.tsx. Kept out of the
 *  route's chunk so `motion` is fetched only after a payment has succeeded. */
const PaymentSuccessAnimation = dynamic(
  () => import("./payment-success-animation").then((m) => m.PaymentSuccessAnimation),
  { ssr: false, loading: () => <div className="h-[124px]" aria-hidden /> },
);

const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 45_000;

type Phase = "summary" | "starting" | "checkout" | "confirming" | "success" | "slow" | "error";

export function PayRentSheet({
  open,
  onOpenChange,
  amountDueHint,
  periodHint,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** display only, for the first paint before the server answers */
  amountDueHint?: number;
  /** YYYY-MM, display only */
  periodHint?: string;
}) {
  const router = useRouter();
  const [phase, setPhase] = React.useState<Phase>("summary");
  const [error, setError] = React.useState<string | null>(null);
  const [amount, setAmount] = React.useState<number | undefined>(amountDueHint);
  const [period, setPeriod] = React.useState<string | undefined>(periodHint);
  const [testMode, setTestMode] = React.useState(false);
  const [status, setStatus] = React.useState<RentPaymentStatus | null>(null);
  const [receiptFor, setReceiptFor] = React.useState<{ hostelName: string; studentName: string } | null>(null);

  // Polling must stop when the sheet closes or the component goes away.
  const alive = React.useRef(false);
  // Checkout fires `handler` and then closes, which also runs `ondismiss` in some
  // versions. Without this the sheet would snap back to the summary a beat after
  // showing "confirming".
  const settled = React.useRef(false);
  const checkout = React.useRef<RazorpayCheckoutInstance | null>(null);

  React.useEffect(() => {
    alive.current = open;
    if (!open) {
      // Reset for the next open, but only after the close animation.
      const t = setTimeout(() => {
        setPhase("summary");
        setError(null);
        setStatus(null);
        settled.current = false;
      }, 250);
      return () => clearTimeout(t);
    }
    return () => {
      alive.current = false;
    };
  }, [open]);

  React.useEffect(() => {
    setAmount(amountDueHint);
  }, [amountDueHint]);
  React.useEffect(() => {
    setPeriod(periodHint);
  }, [periodHint]);

  React.useEffect(
    () => () => {
      alive.current = false;
      try {
        checkout.current?.close();
      } catch {
        /* already closed */
      }
    },
    [],
  );

  const poll = React.useCallback(
    async (orderId: string) => {
      const deadline = Date.now() + POLL_TIMEOUT_MS;
      while (alive.current && Date.now() < deadline) {
        const res = await getRentPaymentStatus({ orderId });
        if (!alive.current) return;
        if (res.ok) {
          setStatus(res.data);
          if (res.data.state === "credited") {
            setPhase("success");
            router.refresh();
            return;
          }
          if (res.data.state === "failed") {
            setError(res.data.failureReason ?? "The payment did not go through. Nothing has been charged.");
            setPhase("error");
            return;
          }
        }
        await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
      }
      if (alive.current) {
        // Captured, not yet credited. The money is safe and recorded; the ledger
        // catches up when the webhook lands. Say exactly that.
        setPhase("slow");
        router.refresh();
      }
    },
    [router],
  );

  async function startPayment() {
    setError(null);
    setPhase("starting");
    settled.current = false;

    // Warm the third-party script while the order round trip is in flight, so the
    // two costs overlap instead of stacking. This is the FIRST time in the whole
    // session that checkout.js is fetched.
    void loadRazorpayCheckout().catch(() => {});

    const res = await createRentOrder();
    if (!alive.current) return;
    if (!res.ok) {
      setError(res.error);
      setPhase("error");
      return;
    }
    const order = res.data;
    setAmount(order.amountRupees);
    setPeriod(order.period);
    setTestMode(order.testMode);
    setReceiptFor({ hostelName: order.hostelName, studentName: order.studentName });

    try {
      checkout.current = await openRazorpayCheckout({
        key: order.keyId,
        order_id: order.orderId,
        amount: order.amountPaise,
        currency: order.currency,
        name: order.hostelName,
        description: `${formatPeriodMonth(order.period)} rent`,
        prefill: order.prefill,
        theme: { color: "#1C2B45" },
        retry: { enabled: false },
        modal: {
          confirm_close: true,
          ondismiss: () => {
            if (settled.current || !alive.current) return;
            setPhase("summary");
          },
        },
        handler: () => {
          // Advisory only — the payment is credited by the signed webhook, and the
          // sheet believes the server, not this callback.
          settled.current = true;
          if (!alive.current) return;
          setPhase("confirming");
          void poll(order.orderId);
        },
      });
      if (alive.current) setPhase("checkout");
    } catch (e) {
      if (!alive.current) return;
      setError(e instanceof Error ? e.message : "The payment window could not open. Please try again.");
      setPhase("error");
    }
  }

  const amountLabel = amount === undefined ? null : formatINR(amount);
  const periodLabel = period ? formatPeriodMonth(period) : "this month";

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>{phase === "success" ? "Payment received" : "Pay rent"}</SheetTitle>
          <SheetDescription>
            {phase === "success"
              ? "Your fee ledger has been updated."
              : `${periodLabel} · paid securely through Razorpay.`}
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 flex flex-col gap-4">
          {testMode && phase !== "success" ? (
            <p className="rounded-control bg-sand-soft px-3 py-2 text-[12px] font-medium text-sand-deep">
              Test mode — no real money will move.
            </p>
          ) : null}

          {(phase === "summary" || phase === "starting" || phase === "checkout" || phase === "error") && (
            <>
              <div className="rounded-card bg-white/70 px-4 py-4 text-center">
                <div className="label-caps">Amount due</div>
                <div className="mt-1 text-stat text-navy">{amountLabel ?? "—"}</div>
                <div className="mt-0.5 text-[12px] text-muted">{periodLabel} rent</div>
              </div>

              {phase === "error" && error ? (
                <p className="flex items-start gap-2 rounded-control bg-red-soft px-3 py-2.5 text-[13px] text-red">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" strokeWidth={2} />
                  <span>{error}</span>
                </p>
              ) : null}

              <Button
                size="xl"
                onClick={startPayment}
                loading={phase === "starting"}
                disabled={phase === "checkout"}
              >
                {phase === "checkout"
                  ? "Payment window open…"
                  : phase === "error"
                    ? "Try again"
                    : amountLabel
                      ? `Pay ${amountLabel} securely`
                      : "Pay securely"}
              </Button>

              <p className="flex items-center justify-center gap-1.5 text-[12px] text-muted">
                <Lock className="h-3.5 w-3.5" strokeWidth={2} />
                Card details are handled by Razorpay — never by this app.
              </p>
            </>
          )}

          {phase === "confirming" && (
            <div className="flex flex-col items-center gap-3 py-6 text-center">
              <span className="flex h-12 w-12 items-center justify-center rounded-full bg-teal-soft text-teal">
                <ShieldCheck className="h-6 w-6 animate-pulse" strokeWidth={1.75} />
              </span>
              <div>
                <p className="text-[15px] font-semibold text-navy">Confirming your payment</p>
                <p className="mt-0.5 text-[13px] text-muted">
                  We&apos;re waiting for the bank to confirm. Please keep this open for a moment.
                </p>
              </div>
            </div>
          )}

          {phase === "slow" && (
            <div className="flex flex-col gap-4">
              <div className="flex flex-col items-center gap-3 py-2 text-center">
                <span className="flex h-12 w-12 items-center justify-center rounded-full bg-sand-soft text-sand-deep">
                  <Clock className="h-6 w-6" strokeWidth={1.75} />
                </span>
                <div>
                  <p className="text-[15px] font-semibold text-navy">Payment received</p>
                  <p className="mt-0.5 text-[13px] text-muted">
                    It can take a minute to show on your fee ledger. Nothing more is needed from you — if it
                    still says unpaid in a while, show your warden the payment ID below.
                  </p>
                </div>
              </div>
              {status ? (
                <PaymentReceipt
                  amountRupees={status.amountRupees}
                  period={status.period}
                  paymentId={status.paymentId}
                  method={status.method}
                  hostelName={receiptFor?.hostelName}
                  studentName={receiptFor?.studentName}
                />
              ) : null}
              <Button size="xl" variant="secondary" onClick={() => onOpenChange(false)}>
                Done
              </Button>
            </div>
          )}

          {phase === "success" && (
            <div className="flex flex-col gap-4">
              <PaymentSuccessAnimation label={`${formatINR(status?.amountRupees ?? amount ?? 0)} paid`} />
              <PaymentReceipt
                amountRupees={status?.amountRupees ?? amount ?? 0}
                period={status?.period ?? period ?? ""}
                paymentId={status?.paymentId ?? null}
                method={status?.method ?? null}
                hostelName={receiptFor?.hostelName}
                studentName={receiptFor?.studentName}
              />
              <Button size="xl" onClick={() => onOpenChange(false)}>
                Done
              </Button>
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}
