"use client";

import * as React from "react";
import type { LiquidButtonHandle, LiquidButtonOptions } from "@avenra/liquid-glass";
import { cn } from "@/lib/utils";

/**
 * LiquidButton — a real <button> that upgrades itself with @avenra/liquid-glass.
 *
 * WHAT THIS FIXES vs. the drop-in version
 * ---------------------------------------
 * 1. The init effect had `[]` for deps while reading the `options` prop, so changing
 *    `bezelWidth`/`blur`/anything else after first paint silently did nothing. Fixed by
 *    keying the effect on a *value* signature of the options (see `optionsSignature`)
 *    rather than the object identity — an inline `options={{...}}` literal is a new object
 *    every render, so depending on identity would tear the glass down 60x a second.
 *
 * 2. It rendered an empty <button ref/> and passed the caption through `options.label`.
 *    The package writes that into `.lg-button-text` with `textContent`, which means the
 *    button is literally empty in server HTML and stays empty forever if the effect ever
 *    fails. Here the caption is `children`, rendered by React into the span the package
 *    looks for, so the button is complete before any JS runs. `label` is not accepted
 *    (see `LiquidButtonProps["options"]`) precisely so the two cannot fight over one node.
 *
 * 3. NOT fixed, because it is not broken: the teardown called `off(event)` with no handler.
 *    The package's emitter types that parameter as optional —
 *      `off<K extends keyof T>(event: K, fn?: AnyFn): this`
 *    — and the implementation clears the whole listener Set when it is omitted
 *    (node_modules/@avenra/liquid-glass/dist/liquid-glass.esm.js:26-34). It is a supported
 *    "remove all listeners for this event" call, not a no-op. It *is* redundant next to
 *    `destroy()`, which cancels the rAF loop, tears down the glass, and unbinds every DOM
 *    listener, so this teardown just calls `destroy()`.
 *
 * PERFORMANCE
 * -----------
 * The package is ~98 KB unminified. It is loaded with a dynamic `import()` inside the
 * effect, so webpack splits it into an async chunk: it is not in First Load JS, it never
 * blocks first paint, and a route that imports this button pays nothing until the button
 * mounts on the client.
 *
 * DEGRADATION
 * -----------
 * The effect is skipped, and the plain (already-correct) button is kept, when:
 *   - there is no 2D canvas — the package builds its displacement maps with
 *     `canvas.getContext('2d')` + `toDataURL()`, and `getContext` returning null throws
 *     inside the package;
 *   - the user asked for reduced motion — the whole effect is a spring loop that rescales
 *     the button on hover/press every frame, and the package exposes no way to still it;
 *   - the chunk fails to load, or `createLiquidButton` throws for any other reason.
 * In every one of those cases the caption, the click handler, focus ring, keyboard
 * activation and disabled state are untouched — it is a normal button that is not shiny.
 */

/** Options we forward to the package. `label` is excluded on purpose — see note 2 above. */
export type LiquidButtonGlassOptions = Omit<LiquidButtonOptions, "label">;

export interface LiquidButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Glass physics. Safe to pass as an inline literal; changes are picked up by value. */
  options?: LiquidButtonGlassOptions;
  /** Skip the glass when the user prefers reduced motion. Default `true`. */
  respectReducedMotion?: boolean;
  /** Extra classes for the inner caption span. */
  captionClassName?: string;
}

/**
 * Stable, order-independent signature of the options *values*.
 * `profile` may be a function (`ProfileFn`), which JSON.stringify would drop, so functions
 * are serialised by source — two structurally identical inline arrows compare equal, which
 * is the behaviour we want for a prop that is nearly always written inline.
 */
function optionsSignature(options: LiquidButtonGlassOptions | undefined): string {
  if (!options) return "";
  const keys = Object.keys(options).sort();
  const pairs = keys.map((k) => {
    const v = options[k as keyof LiquidButtonGlassOptions];
    return [k, typeof v === "function" ? String(v) : v] as const;
  });
  return JSON.stringify(pairs);
}

/** The package's map builder needs a 2D canvas; without one `createLiquidButton` throws. */
function canRasteriseGlass(): boolean {
  if (typeof document === "undefined") return false;
  try {
    const probe = document.createElement("canvas");
    probe.width = 1;
    probe.height = 1;
    return probe.getContext("2d") !== null;
  } catch {
    return false;
  }
}

function usePrefersReducedMotion(enabled: boolean): boolean {
  // Deliberately a local 6-line hook rather than motion's `useReducedMotion`: pulling the
  // animation library into this file would put it in the bundle of every route that has a
  // button, to answer one media query.
  const [reduced, setReduced] = React.useState(false);
  React.useEffect(() => {
    if (!enabled || typeof window === "undefined" || !window.matchMedia) return;
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const onChange = (e: MediaQueryListEvent) => setReduced(e.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [enabled]);
  return enabled && reduced;
}

/**
 * Layout the package's injected layers need. Normally these live in
 * `@avenra/liquid-glass/styles`, but that sheet is 16 KB of dark-theme rules for fifteen
 * widgets we do not use — importing it would ship all of it and fight the ivory tokens.
 * Only three rules actually matter, and `.lg-clone` is not among them: the package sets
 * `display:none` on it inline on both code paths (esm.js:397-411).
 */
const GLASS_LAYER_CLASSES = [
  "[&_.lg-inner]:pointer-events-none [&_.lg-inner]:absolute [&_.lg-inner]:inset-0",
  "[&_.lg-inner]:z-[3] [&_.lg-inner]:rounded-[inherit]",
  "[&_.lg-button-text]:relative [&_.lg-button-text]:z-[5]",
].join(" ");

const LiquidButton = React.forwardRef<HTMLButtonElement, LiquidButtonProps>(function LiquidButton(
  {
    options,
    respectReducedMotion = true,
    className,
    captionClassName,
    children,
    disabled,
    type = "button",
    ...props
  },
  forwardedRef,
) {
  const nodeRef = React.useRef<HTMLButtonElement | null>(null);
  const [glassOn, setGlassOn] = React.useState(false);
  const reducedMotion = usePrefersReducedMotion(respectReducedMotion);
  const signature = optionsSignature(options);

  // Keep the latest options reachable from the init effect without making the effect
  // depend on the object's identity. Declared first, so it has already run by the time the
  // init effect below runs in the same commit.
  const optionsRef = React.useRef(options);
  React.useEffect(() => {
    optionsRef.current = options;
  });

  const setRefs = React.useCallback(
    (node: HTMLButtonElement | null) => {
      nodeRef.current = node;
      if (typeof forwardedRef === "function") forwardedRef(node);
      else if (forwardedRef) forwardedRef.current = node;
    },
    [forwardedRef],
  );

  React.useEffect(() => {
    const el = nodeRef.current;
    if (!el || disabled || reducedMotion || !canRasteriseGlass()) return;

    let cancelled = false;
    let handle: LiquidButtonHandle | null = null;

    void import("@avenra/liquid-glass")
      .then(({ createLiquidButton }) => {
        if (cancelled || !nodeRef.current) return;
        handle = createLiquidButton(nodeRef.current, optionsRef.current ?? {});
        setGlassOn(true);
      })
      .catch((err: unknown) => {
        // A missing canvas, a blocked chunk, a stricter sandbox — all land here, and all
        // mean the same thing: keep the plain button, say why once, carry on.
        if (!cancelled && process.env.NODE_ENV !== "production") {
          console.warn("[LiquidButton] glass effect unavailable, rendering plain button:", err);
        }
      });

    return () => {
      cancelled = true;
      try {
        // `destroy()` cancels the rAF loop, removes the injected layers and unbinds every
        // DOM listener the package added. No `off()` needed — see note 3 at the top.
        handle?.destroy();
      } catch {
        // Teardown must never break unmount.
      }
      // The spring loop writes `transform` straight onto the element; leaving the last
      // frame's scale behind would stick if the element is reused after a re-init.
      el.style.transform = "";
      setGlassOn(false);
    };
  }, [disabled, reducedMotion, signature]);

  return (
    <button
      {...props}
      ref={setRefs}
      type={type}
      disabled={disabled}
      className={cn(
        "relative inline-flex h-12 select-none items-center justify-center gap-2 rounded-control px-6",
        "text-[15px] font-medium text-white transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30",
        "focus-visible:ring-offset-2 focus-visible:ring-offset-ivory",
        "disabled:pointer-events-none disabled:opacity-50",
        GLASS_LAYER_CLASSES,
        glassOn
          ? // The glass supplies the surface; a translucent navy lets the refraction read.
            "bg-navy/70 shadow-glass-lg"
          : // Fallback: the ordinary primary button from the design system.
            "bg-navy shadow-sm hover:bg-navy/90 active:scale-[0.98]",
        className,
      )}
    >
      {/*
        The package reuses `.lg-button-text` if it finds one and only appends its own span
        when it does not — so rendering it here keeps the caption a node React owns, and
        keeps it in the server HTML.
      */}
      <span className={cn("lg-button-text inline-flex items-center gap-2", captionClassName)}>
        {children}
      </span>
    </button>
  );
});

export { LiquidButton };
