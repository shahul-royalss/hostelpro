import * as React from "react";
import Link from "next/link";
import { ChevronRight, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { cx } from "./cx";

/**
 * One obvious primary action per dashboard.
 *
 * Every one of these screens previously offered four to six equal-weight tiles,
 * which is the same as offering none. This is a single filled control, sized to
 * Apple's 50pt prominent-button height, with the spring press feedback from the
 * motion tokens (docs/design-system.md §4 — the curve is paired with its own
 * duration, or the overshoot lands in the wrong place).
 *
 * `hint` says *why* now, so the action is not a bare verb.
 */
export function PrimaryAction({
  href,
  label,
  hint,
  icon: Icon,
  disabled = false,
  disabledHint,
  className,
}: {
  href: string;
  label: string;
  hint?: React.ReactNode;
  icon?: LucideIcon;
  disabled?: boolean;
  disabledHint?: React.ReactNode;
  className?: string;
}) {
  const body = (
    <>
      {Icon ? (
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-control squircle bg-white/15" aria-hidden>
          <Icon className="h-5 w-5" strokeWidth={2} />
        </span>
      ) : null}
      <span className="min-w-0 flex-1">
        <span className="block text-headline">{label}</span>
        {hint || disabledHint ? <span className="mt-0.5 block text-footnote text-white/70">{disabled ? disabledHint : hint}</span> : null}
      </span>
      {!disabled ? <ChevronRight className="h-5 w-5 shrink-0 text-white/60" aria-hidden /> : null}
    </>
  );

  const shell = cn(
    "flex min-h-[50px] w-full items-center gap-3 rounded-control-lg squircle bg-navy px-4 py-3 text-white shadow-elev-2",
    className,
  );

  if (disabled) {
    return (
      <div className={cn(shell, "opacity-50")} aria-disabled>
        {body}
      </div>
    );
  }

  return (
    <Link
      href={href}
      className={cn(shell, "transition-transform duration-snappy ease-snappy hover:bg-navy-deep active:scale-[0.985]")}
    >
      {body}
    </Link>
  );
}

/**
 * Secondary actions — a row of tinted, low-weight controls that must not
 * compete with the primary. Only for destinations the bottom nav does not
 * already offer; a tile that repeats a nav item is duplicate chrome.
 */
export function ActionRow({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn("grid grid-cols-2 gap-3", className)}>{children}</div>;
}

export function SecondaryAction({
  href,
  label,
  icon: Icon,
  disabled = false,
}: {
  href: string;
  label: string;
  icon?: LucideIcon;
  disabled?: boolean;
}) {
  // `text-subhead` and `text-label` in one string: cx keeps both, cn would not.
  const shell =
    "flex min-h-[44px] items-center gap-2.5 rounded-control-lg squircle border border-separator bg-fill-quaternary px-3.5 py-2.5 text-subhead font-medium text-label";
  const inner = (
    <>
      {Icon ? <Icon className="h-4 w-4 shrink-0 text-label-secondary" strokeWidth={1.9} aria-hidden /> : null}
      <span className="min-w-0 truncate">{label}</span>
    </>
  );
  if (disabled) {
    return (
      <div className={cx(shell, "opacity-50")} aria-disabled>
        {inner}
      </div>
    );
  }
  return (
    <Link href={href} className={cx(shell, "transition-colors duration-quick ease-sys hover:bg-fill-tertiary active:bg-fill-secondary")}>
      {inner}
    </Link>
  );
}
