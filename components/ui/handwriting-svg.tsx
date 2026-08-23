"use client";

import * as React from "react";
import { motion, useReducedMotion } from "motion/react";
import {
  HANDWRITING_PATHS,
  type HandwritingPath,
  type HandwritingPathKey,
} from "@/lib/handwriting-paths";
import { cn } from "@/lib/utils";

/**
 * HandwritingSvg — draws a pre-traced word as if it were being written.
 *
 * WHY IT LOOKS NOTHING LIKE THE DROP-IN VERSION
 * ---------------------------------------------
 * The version this replaces did two things that cannot work here:
 *
 *   1. It fetched a TTF from raw.githubusercontent.com on mount. `lib/security-headers.ts`
 *      pins `connect-src` to 'self' plus the Supabase origin, so that request is blocked
 *      outright in production — the component would have rendered nothing, and "fixing" it
 *      would have meant widening the CSP for decoration.
 *   2. It parsed that font in the browser with opentype.js — ~3.6 MB on disk, ~528 KB for
 *      the dist bundle alone — to trace six glyphs that never change.
 *
 * Both moved to `scripts/gen-handwriting-path.mjs`, which runs on a developer machine,
 * downloads the font once to a gitignored cache under `node_modules/.cache/`, verifies it
 * against a pinned SHA-256, and writes `lib/handwriting-paths.ts` as plain exported
 * strings. This component imports those strings. No font request, no opentype.js in the
 * browser, no CSP change.
 *
 * The animation is motion's `pathLength`: motion normalises the path to `pathLength="1"`
 * and animates `stroke-dashoffset`, so the outline is traced regardless of its real length.
 *
 * REDUCED MOTION
 * --------------
 * `prefers-reduced-motion: reduce` renders the finished mark — filled, undashed, no
 * animation at all, not a faster one.
 *
 * NOTE ON FIRST PAINT
 * -------------------
 * While animating, the mark starts invisible (`pathLength: 0`, `fillOpacity: 0`) and is
 * drawn after hydration. That is right for decorative branding but wrong for anything
 * load-bearing — pass `animate={false}` there and it renders finished immediately.
 */

type HandwritingSource =
  | {
      /** A key from `lib/handwriting-paths.ts` — the generated, committed set. */
      name: HandwritingPathKey;
      d?: never;
      viewBox?: never;
    }
  | {
      name?: never;
      /** Raw SVG path data, when you are passing your own traced outline. */
      d: string;
      /** Required alongside `d` — the artwork has no intrinsic size without it. */
      viewBox: string;
    };

export type HandwritingSvgProps = HandwritingSource & {
  /**
   * Accessible name. Defaults to the generated entry's text when `name` is used.
   * Pass `null` to mark the mark decorative (`aria-hidden`) — do that when adjacent text
   * already says the same word.
   */
  label?: string | null;
  /** Seconds to trace the outline. Default 2. */
  duration?: number;
  /** Seconds to wait before starting. Default 0. */
  delay?: number;
  /** Stroke width in viewBox units (the outlines are traced at em size 100). Default 1.5. */
  strokeWidth?: number;
  /** Flood the glyphs after the trace lands. Default `true`. */
  fill?: boolean;
  /** Force the finished state without animating. Default `true` (animate). */
  animate?: boolean;
  className?: string;
  /** Change to replay the animation. */
  replayKey?: string | number;
};

function resolve(props: HandwritingSvgProps): Pick<HandwritingPath, "d" | "viewBox" | "text"> {
  if (props.name !== undefined) return HANDWRITING_PATHS[props.name];
  return { d: props.d, viewBox: props.viewBox, text: "" };
}

export function HandwritingSvg(props: HandwritingSvgProps) {
  const {
    label,
    duration = 2,
    delay = 0,
    strokeWidth = 1.5,
    fill = true,
    animate = true,
    className,
    replayKey,
  } = props;

  const { d, viewBox, text } = resolve(props);
  const reducedMotion = useReducedMotion();
  const isStatic = !animate || reducedMotion === true;

  // `label === null` is an explicit "this is decoration"; `undefined` falls back to the
  // word the generator traced, which is the only honest default for a wordmark.
  const decorative = label === null;
  const accessibleName = decorative ? undefined : (label ?? text) || undefined;

  const shared = {
    d,
    fill: "currentColor",
    stroke: "currentColor",
    strokeWidth,
    strokeLinecap: "round",
    strokeLinejoin: "round",
  } as const;

  return (
    <svg
      viewBox={viewBox}
      xmlns="http://www.w3.org/2000/svg"
      preserveAspectRatio="xMidYMid meet"
      role={decorative ? "presentation" : "img"}
      aria-hidden={decorative || undefined}
      aria-label={accessibleName}
      // Height-driven by default: the viewBox gives the intrinsic ratio, so width follows.
      className={cn("h-16 w-auto text-navy", className)}
    >
      {accessibleName ? <title>{accessibleName}</title> : null}

      {isStatic ? (
        <path {...shared} fillOpacity={fill ? 1 : 0} />
      ) : (
        <motion.path
          key={replayKey}
          {...shared}
          initial={{ pathLength: 0, fillOpacity: 0 }}
          animate={{ pathLength: 1, fillOpacity: fill ? 1 : 0 }}
          transition={{
            pathLength: { duration, delay, ease: "easeInOut" },
            // The ink lands just before the pen finishes, which reads as writing rather
            // than as two separate effects.
            fillOpacity: { duration: Math.max(duration * 0.35, 0.3), delay: delay + duration * 0.7 },
          }}
        />
      )}
    </svg>
  );
}
