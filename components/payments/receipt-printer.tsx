"use client";

import * as React from "react";
import { formatDate, formatINR, formatPeriodMonth } from "@/lib/utils";
import styles from "./receipt-printer.module.css";

/**
 * The dispenser.
 *
 * A port of the user's stand-alone prototype (`reciept animation/`) into the
 * payment flow: the same metallic hood, dark slit, 3D roll-out, serrated cutter
 * teeth, blade flash, paper grain and cast shadow — printing the real payment
 * instead of a demo invoice, with no controls, because there is nothing here for
 * anyone to press. The slip feeds out on mount and the auto-cutter fires when it
 * stops, which is what a thermal printer actually does; the prototype's Print /
 * Tear buttons only existed so a visitor could replay the animation.
 *
 * Everything it draws is decoration over a transaction that has ALREADY been
 * credited by a signed webhook. Nothing here is load-bearing: every prop is
 * optional, every value is formatted behind a guard, and the caller wraps this
 * in an error boundary (payment-success-animation.tsx). A receipt that fails to
 * draw must never look like a payment that failed to land.
 *
 * prefers-reduced-motion: the finished receipt is rendered on the first paint.
 * No roll, no hum, no blade flash — not merely a shortened animation.
 */

/** Matches the source-of-truth timing in receipt-printer.module.css. */
const ROLL_MS = 2500;
const FLASH_MS = 350;

/** Razorpay's method codes, spelled the way a person reads them. Mirrors the
 *  table in payment-receipt.tsx — deliberately a copy, so this file can be
 *  deleted or swapped without reaching into the receipt card. */
const METHOD_LABEL: Record<string, string> = {
  upi: "UPI",
  card: "Card",
  netbanking: "Net banking",
  wallet: "Wallet",
  emi: "EMI",
  paylater: "Pay later",
};

export interface ReceiptPrinterProps {
  /** Rupees, as the server credited them. */
  amountRupees?: number | null;
  /** YYYY-MM, the fee period this settles. */
  period?: string | null;
  /** Razorpay payment id — the student's proof if anything is ever traced. */
  paymentId?: string | null;
  /** Razorpay method code: upi | card | netbanking | wallet | emi | paylater. */
  method?: string | null;
  studentName?: string | null;
  hostelName?: string | null;
  paidAt?: Date | null;
}

/** Reads the OS setting once, synchronously, on the first client render. This
 *  component is only ever mounted through a `ssr: false` dynamic import, so
 *  there is no server pass to disagree with and no hydration mismatch to cause. */
function readsReducedMotion(): boolean {
  try {
    return typeof window !== "undefined" && typeof window.matchMedia === "function"
      ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
      : false;
  } catch {
    return false;
  }
}

/** Formatting must not be able to take the sheet down with it. */
function guard(produce: () => string, fallback: string): string {
  try {
    const value = produce();
    return typeof value === "string" && value.trim().length > 0 ? value : fallback;
  } catch {
    return fallback;
  }
}

export function ReceiptPrinter({
  amountRupees,
  period,
  paymentId,
  method,
  studentName,
  hostelName,
  paidAt,
}: ReceiptPrinterProps) {
  const [reduced] = React.useState(readsReducedMotion);
  const [rolling, setRolling] = React.useState(false);
  const [settled, setSettled] = React.useState(reduced);
  const [cutting, setCutting] = React.useState(false);

  React.useEffect(() => {
    if (reduced) return;

    // One frame in the retracted state first, so the browser has something to
    // animate FROM. Starting the keyframes on the same paint that mounts the
    // element makes the first 100ms of the roll disappear.
    const raf = requestAnimationFrame(() => setRolling(true));

    const feed = setTimeout(() => {
      setRolling(false);
      setSettled(true);
      setCutting(true);
    }, ROLL_MS);

    const blade = setTimeout(() => setCutting(false), ROLL_MS + FLASH_MS);

    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(feed);
      clearTimeout(blade);
    };
  }, [reduced]);

  const amount = typeof amountRupees === "number" && Number.isFinite(amountRupees) ? amountRupees : 0;
  const money = guard(() => formatINR(amount), "₹0");
  const periodLabel = period ? guard(() => formatPeriodMonth(period), period) : null;
  const dateLabel = guard(() => formatDate(paidAt ?? new Date(), "d MMM yyyy"), "");
  const methodLabel = method ? (METHOD_LABEL[method] ?? method) : null;

  const paperState = settled ? styles.paperPrinted : rolling ? styles.paperPrinting : styles.paperRetracted;
  const hum = rolling ? ` ${styles.humming}` : "";

  return (
    <div className={styles.stage} style={{ "--nv-roll-ms": `${ROLL_MS}ms` } as React.CSSProperties}>
      {/* Machine chrome: pixels, not information. */}
      <div className={styles.hoodTop + hum} aria-hidden>
        <div className={styles.hoodHighlight} />
      </div>
      <div className={styles.slit + hum} aria-hidden />
      <div
        className={cutting ? `${styles.cutterFlash} ${styles.cutterFlashActive}` : styles.cutterFlash}
        aria-hidden
      />
      <div className={styles.hoodBottom + hum} aria-hidden>
        <div className={styles.hoodShadow} />
      </div>

      <div className={styles.viewport}>
        <div className={`${styles.paper} ${paperState}`}>
          {/* Plain text in plain elements — a screen reader reads the slip in
              order, and the machine around it announces nothing. */}
          <div className={styles.content}>
            <div className={styles.head}>
              <div className={styles.brand}>
                <div className={styles.brandName}>NIVORA</div>
                <div className={styles.brandSub}>
                  {hostelName ? `${hostelName} · Rent receipt` : "Rent receipt"}
                </div>
              </div>
              <div className={styles.mark} aria-hidden>
                N
              </div>
            </div>

            <div className={styles.amount}>{money}</div>
            <div className={styles.meta}>
              {dateLabel ? `${dateLabel} · ` : ""}
              Rent paid
            </div>

            <div className={styles.rule} aria-hidden />

            <div className={styles.lines}>
              <div className={styles.line}>
                <span className={styles.lineLabel}>{periodLabel ? `${periodLabel} rent` : "Rent"}</span>
                <span className={styles.lineValue}>{money}</span>
              </div>
              {studentName ? (
                <div className={styles.line}>
                  <span className={styles.lineLabel}>Resident</span>
                  <span className={styles.lineValue}>{studentName}</span>
                </div>
              ) : null}
              {methodLabel ? (
                <div className={styles.line}>
                  <span className={styles.lineLabel}>Paid by</span>
                  <span className={styles.lineValue}>{methodLabel}</span>
                </div>
              ) : null}
            </div>

            <div className={styles.grand}>
              <span>TOTAL PAID</span>
              <span>{money}</span>
            </div>

            <div className={styles.foot}>
              <div className={styles.footMsg}>THANK YOU</div>
              <div className={styles.barcode}>
                <div className={styles.barcodeLines} aria-hidden />
                {paymentId ? <div className={styles.barcodeNum}>{paymentId}</div> : null}
              </div>
            </div>
          </div>

          <div className={styles.tearMargin} aria-hidden />
        </div>
      </div>
    </div>
  );
}
