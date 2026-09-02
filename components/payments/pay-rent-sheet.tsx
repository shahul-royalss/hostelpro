"use client";

import * as React from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { AlertTriangle, Clock, Info, Lock, ShieldCheck } from "lucide-react";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import {
  createRentOrder,
  getRentPaymentStatus,
  type RentPaymentState,
  type RentPaymentStatus,
} from "@/lib/actions/payments";
import { formatINR, formatPeriodMonth } from "@/lib/utils";
import { PaymentReceipt } from "./payment-receipt";
import {
  loadRazorpayCheckout,
  openRazorpayCheckout,
  paymentFailureReason,
  type RazorpayCheckoutInstance,
  type RazorpayCheckoutSuccess,
} from "./razorpay-checkout";

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
 *  route's chunk so the receipt printer's markup and CSS are fetched only after a
 *  payment has succeeded. The placeholder reserves the machine's height so the
 *  Done button does not jump when the chunk lands. */
const PaymentSuccessAnimation = dynamic(
  () => import("./payment-success-animation").then((m) => m.PaymentSuccessAnimation),
  { ssr: false, loading: () => <div className="h-[352px]" aria-hidden /> },
);

const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 45_000;

type Phase = "summary" | "starting" | "checkout" | "confirming" | "success" | "slow" | "error";

type VerifyOutcome =
  /** Razorpay really did produce this callback. Go and watch for settlement. */
  | { outcome: "verified"; state: RentPaymentState }
  /** It did not. Nothing was paid, and the student must not be told to wait. */
  | { outcome: "rejected"; error: string }
  /** We could not tell — our endpoint, not the payment. Fall through to polling. */
  | { outcome: "unknown" };

/**
 * Ask our own server whether Checkout's success callback is genuine.
 *
 * The callback runs in this browser, and this browser can be told anything, so it
 * is checked before the sheet shows the reassuring screen. The check is a real
 * HMAC over `order_id|payment_id`, done on the server with a secret that is not
 * here — see app/api/payments/verify/route.ts.
 *
 * What comes back does NOT decide whether the fee is paid. Only the signed
 * webhook does that; `state` here is the server reporting where settlement has
 * got to, and the sheet keeps polling for it either way.
 *
 * A network failure or a 5xx returns "unknown" ON PURPOSE. If our verifier is
 * down, the student's money has still moved and the webhook will still credit it;
 * stranding a real payment behind our own outage would be the worse bug of the
 * two. Only an explicit 4xx — a signature that did not verify, an order that is
 * not theirs — is allowed to say no.
 */
async function verifyCheckout(success: RazorpayCheckoutSuccess): Promise<VerifyOutcome> {
  try {
    const res = await fetch("/api/payments/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // Same-origin: the session cookie rides along, and the route refuses
      // anything with a foreign Origin.
      credentials: "same-origin",
      cache: "no-store",
      body: JSON.stringify({
        razorpay_order_id: success.razorpay_order_id,
        razorpay_payment_id: success.razorpay_payment_id,
        razorpay_signature: success.razorpay_signature,
      }),
    });

    const body: unknown = await res.json().catch(() => null);
    const payload = (body ?? {}) as { verified?: unknown; state?: unknown; error?: unknown };

    if (res.ok && payload.verified === true) {
      const state = typeof payload.state === "string" ? (payload.state as RentPaymentState) : "pending";
      return { outcome: "verified", state };
    }
    if (res.status >= 400 && res.status < 500 && res.status !== 429) {
      return {
        outcome: "rejected",
        error:
          typeof payload.error === "string" && payload.error.length > 0
            ? payload.error
            : "We couldn't confirm that payment. Nothing has been marked paid.",
      };
    }
    return { outcome: "unknown" };
  } catch {
    return { outcome: "unknown" };
  }
}

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
  /** A calm, non-alarming sentence for an outcome that is not a failure — the
   *  student closing the modal. An empty screen is not an answer (CLAUDE.md:
   *  every control must do something visible), and "error" would be a lie. */
  const [notice, setNotice] = React.useState<string | null>(null);
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
        setNotice(null);
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
    setNotice(null);
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
      checkout.current = await openRazorpayCheckout(
        {
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
              // The student closed the sheet themselves. That is a decision, not a
              // fault: say so in plain words and leave the Pay button ready.
              if (settled.current || !alive.current) return;
              setNotice("Payment cancelled — nothing has been charged. You can try again whenever you like.");
              setPhase("summary");
            },
          },
          handler: (success) => {
            // ADVISORY. This callback is JavaScript running in a browser; it is not
            // evidence of anything until the server has checked its signature, and
            // it never credits a fee — the signed webhook does that.
            settled.current = true;
            if (!alive.current) return;
            setPhase("confirming");
            void (async () => {
              const verdict = await verifyCheckout(success);
              if (!alive.current) return;

              if (verdict.outcome === "rejected") {
                // The triple did not verify. Do NOT fall through to polling: the
                // "still working on it" screen would be a false reassurance for a
                // payment that was never made.
                setError(verdict.error);
                setPhase("error");
                return;
              }

              // Verified, or unverifiable because our own endpoint is unreachable.
              // Either way the webhook is the thing that credits, so go and watch
              // the server until it says so.
              void poll(order.orderId);
            })();
          },
        },
        {
          // Registered before the modal opens — a card can be declined on the first
          // tap, before openRazorpayCheckout() has even resolved.
          "payment.failed": (payload: unknown) => {
            settled.current = true;
            if (!alive.current) return;
            const reason = paymentFailureReason(payload);
            setError(
              reason
                ? `${reason} Nothing has been charged — you can try again, or pay at the warden desk.`
                : "The payment did not go through. Nothing has been charged — you can try again, or pay at the warden desk.",
            );
            setPhase("error");
          },
        },
      );
      // `!settled.current` matters now that a handler can fire BEFORE this line.
      // A card declined on the first tap resolves through `payment.failed` while
      // openRazorpayCheckout() is still awaiting; without this guard the phase it
      // set would be overwritten by "checkout" and the student would be left
      // looking at "Payment window open…" over a modal that had already failed.
      if (alive.current && !settled.current) setPhase("checkout");
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

              {/* Cancelling is not failing, so it does not get the red treatment.
                  It does get said out loud — closing the modal used to drop the
                  student back here with no explanation at all. */}
              {phase === "summary" && notice ? (
                <p className="flex items-start gap-2 rounded-control bg-sand-soft px-3 py-2.5 text-[13px] text-sand-deep">
                  <Info className="mt-0.5 h-4 w-4 shrink-0" strokeWidth={2} />
                  <span>{notice}</span>
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
              <PaymentSuccessAnimation
                label={`${formatINR(status?.amountRupees ?? amount ?? 0)} paid`}
                amountRupees={status?.amountRupees ?? amount ?? 0}
                period={status?.period ?? period ?? null}
                paymentId={status?.paymentId ?? null}
                method={status?.method ?? null}
                hostelName={receiptFor?.hostelName}
                studentName={receiptFor?.studentName}
              />
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
