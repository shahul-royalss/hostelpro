"use client";

import * as React from "react";
import { AnimatePresence, motion, useAnimationControls, useReducedMotion } from "motion/react";
import { cn } from "@/lib/utils";

/**
 * OtpInput — one real <input> under a row of animated slots.
 *
 * The single input is the field: it carries `name`, `autoComplete="one-time-code"`,
 * `inputMode="numeric"`, `maxLength` and the value the form posts. That is deliberate over
 * the six-separate-inputs shape — one field is one accessible name to announce, one target
 * for platform one-tap autofill of an SMS/authenticator code, and one value in the
 * FormData. The boxes above it are `aria-hidden` decoration, which is also what lets each
 * digit be an animated element instead of a native input's untouchable text node.
 *
 * Design tokens only (DESIGN.md §1): ivory/white glass surfaces, `border-input` hairlines,
 * navy for focus and filled state, red for the invalid state.
 */

export interface OtpInputProps
  extends Omit<
    React.InputHTMLAttributes<HTMLInputElement>,
    "value" | "defaultValue" | "onChange" | "type" | "size" | "maxLength" | "children"
  > {
  /** Number of slots. Default 6. */
  length?: number;
  /** Controlled value. Omit for uncontrolled. */
  value?: string;
  /** Initial value when uncontrolled. */
  defaultValue?: string;
  /** Fires on every change with the whole code. */
  onChange?: (value: string) => void;
  /** Fires once when the last slot is filled — wire your submit here. */
  onComplete?: (value: string) => void;
  /** Paints the slots red and shakes the row. */
  invalid?: boolean;
  /** Change this to replay the shake for a repeated error (same `invalid` value). */
  shakeKey?: string | number;
  /** Extra classes for the slot row. */
  className?: string;
  /** Extra classes for one slot. */
  slotClassName?: string;
}

/** Digits only — TOTP and SMS codes in this app are numeric. */
const sanitise = (raw: string, length: number) => raw.replace(/\D/g, "").slice(0, length);

const SPRING = { type: "spring", stiffness: 520, damping: 32, mass: 0.6 } as const;

const OtpInput = React.forwardRef<HTMLInputElement, OtpInputProps>(function OtpInput(
  {
    length = 6,
    value: controlledValue,
    defaultValue = "",
    onChange,
    onComplete,
    invalid = false,
    shakeKey,
    disabled,
    className,
    slotClassName,
    autoFocus,
    name,
    id,
    "aria-label": ariaLabel = "Verification code",
    ...inputProps
  },
  forwardedRef,
) {
  const inputRef = React.useRef<HTMLInputElement | null>(null);
  const [uncontrolled, setUncontrolled] = React.useState(() => sanitise(defaultValue, length));
  const [focused, setFocused] = React.useState(false);
  const reducedMotion = useReducedMotion();
  const shake = useAnimationControls();

  const isControlled = controlledValue !== undefined;
  const value = sanitise(isControlled ? controlledValue : uncontrolled, length);
  const completedRef = React.useRef<string | null>(null);

  const setRefs = React.useCallback(
    (node: HTMLInputElement | null) => {
      inputRef.current = node;
      if (typeof forwardedRef === "function") forwardedRef(node);
      else if (forwardedRef) forwardedRef.current = node;
    },
    [forwardedRef],
  );

  const commit = React.useCallback(
    (raw: string) => {
      const next = sanitise(raw, length);
      if (!isControlled) setUncontrolled(next);
      onChange?.(next);
      if (next.length === length) {
        // Guard so a re-render, or re-typing the same code, cannot double-submit.
        if (completedRef.current !== next) {
          completedRef.current = next;
          onComplete?.(next);
        }
      } else {
        completedRef.current = null;
      }
    },
    [isControlled, length, onChange, onComplete],
  );

  /** The caret is drawn, not native, so it must always sit at the end of the value. */
  const caretToEnd = React.useCallback(() => {
    const el = inputRef.current;
    if (!el) return;
    const end = el.value.length;
    if (el.selectionStart !== end || el.selectionEnd !== end) el.setSelectionRange(end, end);
  }, []);

  React.useEffect(() => {
    if (!invalid || reducedMotion) return;
    void shake.start({
      x: [0, -7, 6, -4, 3, 0],
      transition: { duration: 0.4, ease: "easeInOut" },
    });
  }, [invalid, shakeKey, reducedMotion, shake]);

  const activeIndex = Math.min(value.length, length - 1);
  const slots = Array.from({ length }, (_, i) => value[i] ?? "");

  return (
    <div className="relative">
      <motion.div
        animate={shake}
        aria-hidden="true"
        className={cn("flex items-center gap-2 sm:gap-2.5", className)}
      >
        {slots.map((digit, i) => {
          const isActive = focused && !disabled && i === activeIndex;
          const isFilled = digit !== "";
          return (
            <motion.div
              key={i}
              animate={reducedMotion ? undefined : { scale: isActive ? 1.04 : 1 }}
              transition={SPRING}
              className={cn(
                "relative flex h-14 w-full min-w-0 max-w-[3.25rem] flex-1 items-center justify-center",
                "rounded-control border bg-white/70 text-2xl font-semibold tabular-nums text-navy",
                "shadow-glass transition-colors",
                isFilled ? "border-navy/40" : "border-input",
                isActive && "border-navy ring-1 ring-navy",
                invalid && "border-red bg-red-soft/50 text-red ring-1 ring-red/30",
                disabled && "cursor-not-allowed opacity-50",
                slotClassName,
              )}
            >
              <AnimatePresence initial={false} mode="popLayout">
                {isFilled ? (
                  <motion.span
                    key={`${i}-${digit}`}
                    initial={reducedMotion ? false : { opacity: 0, y: 8, scale: 0.7 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={reducedMotion ? { opacity: 0 } : { opacity: 0, y: -8, scale: 0.7 }}
                    transition={SPRING}
                  >
                    {digit}
                  </motion.span>
                ) : null}
              </AnimatePresence>

              {isActive && !isFilled ? (
                <motion.span
                  className="absolute h-6 w-px bg-navy"
                  initial={{ opacity: 1 }}
                  animate={reducedMotion ? { opacity: 1 } : { opacity: [1, 1, 0, 0, 1] }}
                  transition={
                    reducedMotion
                      ? undefined
                      : { duration: 1.1, repeat: Infinity, ease: "linear", times: [0, 0.45, 0.5, 0.95, 1] }
                  }
                />
              ) : null}
            </motion.div>
          );
        })}
      </motion.div>

      {/*
        The actual field. Transparent rather than hidden so it keeps a focus ring target,
        stays in the accessibility tree, and still receives paste, autofill and IME input.
      */}
      <input
        {...inputProps}
        ref={setRefs}
        id={id}
        name={name}
        type="text"
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern={`\\d{${length}}`}
        maxLength={length}
        value={value}
        disabled={disabled}
        autoFocus={autoFocus}
        aria-label={ariaLabel}
        aria-invalid={invalid || undefined}
        className="absolute inset-0 h-full w-full cursor-default rounded-control bg-transparent text-transparent caret-transparent opacity-0 outline-none"
        onChange={(e) => commit(e.target.value)}
        onFocus={(e) => {
          setFocused(true);
          caretToEnd();
          inputProps.onFocus?.(e);
        }}
        onBlur={(e) => {
          setFocused(false);
          inputProps.onBlur?.(e);
        }}
        onSelect={(e) => {
          caretToEnd();
          inputProps.onSelect?.(e);
        }}
        onClick={(e) => {
          caretToEnd();
          inputProps.onClick?.(e);
        }}
        onKeyDown={(e) => {
          // Arrow keys would move an invisible caret away from the end, desyncing the
          // drawn caret from where the next keystroke actually lands.
          if (e.key === "ArrowLeft" || e.key === "ArrowRight" || e.key === "ArrowUp" || e.key === "ArrowDown") {
            e.preventDefault();
            caretToEnd();
          }
          inputProps.onKeyDown?.(e);
        }}
        onPaste={(e) => {
          inputProps.onPaste?.(e);
          if (e.defaultPrevented) return;
          // "Your code is 481920" pastes cleanly: sanitise() keeps the digits and drops
          // the rest, and maxLength alone would have truncated the wrong end.
          const pasted = e.clipboardData.getData("text");
          if (!pasted) return;
          e.preventDefault();
          commit(pasted);
        }}
      />
    </div>
  );
});

export { OtpInput };
