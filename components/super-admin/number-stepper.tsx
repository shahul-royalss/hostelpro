"use client";

import { Minus, Plus } from "lucide-react";

/** −/+ stepper input (SA-2 "Number of floors / rooms", SA-4 "Edit structure"). */
export function NumberStepper({
  id,
  value,
  onChange,
  onBlur,
  min,
  max,
  disabled,
}: {
  id: string;
  value: number;
  onChange: (v: number) => void;
  onBlur?: () => void;
  min: number;
  max: number;
  disabled?: boolean;
}) {
  const n = Number.isFinite(value) ? value : min;
  const clamp = (v: number) => Math.min(max, Math.max(min, v));
  return (
    <div className="flex h-10 items-stretch overflow-hidden rounded-control border border-input bg-white/70 focus-within:border-navy focus-within:ring-1 focus-within:ring-navy">
      <button
        type="button"
        aria-label="Decrease"
        className="flex w-10 shrink-0 items-center justify-center text-navy transition-colors hover:bg-navy/5 disabled:opacity-40"
        onClick={() => onChange(clamp(n - 1))}
        disabled={disabled || n <= min}
      >
        <Minus className="h-4 w-4" />
      </button>
      <input
        id={id}
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        disabled={disabled}
        value={Number.isFinite(value) ? value : ""}
        onChange={(e) => onChange(e.target.value === "" ? Number.NaN : Number(e.target.value))}
        onBlur={() => {
          if (!Number.isFinite(value)) onChange(min);
          else onChange(clamp(Math.round(value)));
          onBlur?.();
        }}
        className="w-full min-w-0 border-x border-input bg-transparent text-center text-sm font-semibold text-navy tabular outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
      />
      <button
        type="button"
        aria-label="Increase"
        className="flex w-10 shrink-0 items-center justify-center text-navy transition-colors hover:bg-navy/5 disabled:opacity-40"
        onClick={() => onChange(clamp(n + 1))}
        disabled={disabled || n >= max}
      >
        <Plus className="h-4 w-4" />
      </button>
    </div>
  );
}
