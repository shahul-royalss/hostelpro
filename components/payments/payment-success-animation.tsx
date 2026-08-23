"use client";

import * as React from "react";
import { motion, useReducedMotion } from "motion/react";

/**
 * THE SUCCESS VISUAL — and nothing else.
 *
 * This file is the seam. It holds no payment state, imports no action, knows no
 * order id: it is handed a label and draws a confirmation. Replacing it with a
 * Lottie file, a video, a hand-drawn SVG or a brand animation is a matter of
 * rewriting this one component's body — pay-rent-sheet.tsx renders it through a
 * `next/dynamic` import and never looks inside.
 *
 * Two reasons it is loaded dynamically rather than imported directly:
 *   • `motion` is otherwise unused in this app, so a static import would pull the
 *     animation runtime into the shared chunk for every route, to be evaluated by
 *     everyone who never pays anything;
 *   • it is only ever rendered after a payment has already succeeded, which is the
 *     one moment in the flow where a few hundred milliseconds of chunk fetch costs
 *     nothing.
 *
 * Respects prefers-reduced-motion: the same mark is drawn, statically.
 */
export function PaymentSuccessAnimation({ label = "Payment successful" }: { label?: string }) {
  const reduced = useReducedMotion();

  const spring = { type: "spring" as const, stiffness: 220, damping: 18 };

  return (
    <div className="flex flex-col items-center gap-3 py-2" role="status" aria-live="polite">
      <div className="relative flex h-24 w-24 items-center justify-center">
        {/* Halo — a single soft pulse outward, then gone. */}
        {!reduced && (
          <motion.span
            aria-hidden
            className="absolute inset-0 rounded-full bg-teal/20"
            initial={{ scale: 0.6, opacity: 0.9 }}
            animate={{ scale: 1.5, opacity: 0 }}
            transition={{ duration: 0.9, ease: "easeOut" }}
          />
        )}

        <motion.span
          className="relative flex h-[72px] w-[72px] items-center justify-center rounded-full bg-teal text-white shadow-glass-lg"
          initial={reduced ? false : { scale: 0.4, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={reduced ? { duration: 0 } : spring}
        >
          <svg viewBox="0 0 40 40" className="h-9 w-9" fill="none" aria-hidden>
            <motion.path
              d="M11 20.5 L17.5 27 L29 14"
              stroke="currentColor"
              strokeWidth={3.2}
              strokeLinecap="round"
              strokeLinejoin="round"
              initial={reduced ? false : { pathLength: 0 }}
              animate={{ pathLength: 1 }}
              transition={reduced ? { duration: 0 } : { duration: 0.4, delay: 0.16, ease: "easeOut" }}
            />
          </svg>
        </motion.span>
      </div>

      <motion.p
        className="text-[17px] font-semibold text-navy"
        initial={reduced ? false : { opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={reduced ? { duration: 0 } : { duration: 0.28, delay: 0.3 }}
      >
        {label}
      </motion.p>
    </div>
  );
}
