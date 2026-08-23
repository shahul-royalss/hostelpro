"use client";

/**
 * Usage examples for <LiquidButton />. Not routed and not imported by the app — it exists
 * so the public API is exercised by `tsc --noEmit`, `next build` and `eslint`.
 */

import * as React from "react";
import { ArrowRight } from "lucide-react";
import { LiquidButton } from "@/components/ui/liquid-button";

export function LiquidButtonDemo() {
  const [count, setCount] = React.useState(0);
  const [thick, setThick] = React.useState(false);

  return (
    <div className="flex flex-col items-start gap-6 p-8">
      {/* Plain: children are the caption, click is an ordinary React onClick. */}
      <LiquidButton onClick={() => setCount((n) => n + 1)}>
        Pay rent
        <ArrowRight className="size-4" />
      </LiquidButton>
      <p className="text-sm text-muted">Pressed {count}x</p>

      {/*
        Options as an inline literal. This is the case the drop-in version got wrong: with
        `[]` deps it read `options` once and never again, so this toggle did nothing. The
        component keys its effect on the option *values*, so flipping this rebuilds the
        glass — while re-renders that do not change any value leave it alone.
      */}
      <LiquidButton
        options={{ bezelWidth: thick ? 40 : 20, refractiveIndex: 2.1, blur: 0.6 }}
        onClick={() => setThick((v) => !v)}
      >
        {thick ? "Thick bezel" : "Thin bezel"}
      </LiquidButton>

      {/* Disabled skips the effect entirely and keeps the plain disabled button. */}
      <LiquidButton disabled>Unavailable</LiquidButton>

      {/* Submits a form — it is a real <button type="submit">, so Enter works too. */}
      <form action="/mfa" className="flex items-center gap-3">
        <LiquidButton type="submit" className="w-full sm:w-auto">
          Continue
        </LiquidButton>
      </form>

      {/* Opt out of the reduced-motion skip when the caller has its own answer for it. */}
      <LiquidButton respectReducedMotion={false} captionClassName="tracking-wide">
        Always glassy
      </LiquidButton>
    </div>
  );
}
