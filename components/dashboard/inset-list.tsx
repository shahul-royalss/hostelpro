import * as React from "react";
import Link from "next/link";
import { ChevronRight, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { cx } from "./cx";

/**
 * Apple's grouped inset list.
 *
 * One material surface per group, `rounded-card`, rows separated by hairlines
 * that are **inset to the text column** — the detail that makes an iOS table
 * view read as a table view rather than a stack of divs.
 *
 * The group is the material (docs/design-system.md §3: never nest a material
 * inside a material), so an InsetList is a sibling of a GlassCard, never a
 * child of one.
 */

export function ListSectionHeader({
  title,
  action,
  className,
}: {
  title: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("mb-2 flex items-end justify-between gap-3 px-1", className)}>
      <h2 className="label-caps text-label-secondary">{title}</h2>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}

/** "See all ›" — the standard trailing link for a group header. */
export function SeeAll({ href, children = "See all" }: { href: string; children?: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="-my-1 inline-flex items-center gap-0.5 rounded-control px-1 py-1 text-footnote font-medium text-ink-navy transition-opacity duration-quick ease-sys hover:opacity-70"
    >
      {children}
      <ChevronRight className="h-3.5 w-3.5" strokeWidth={2.25} aria-hidden />
    </Link>
  );
}

export function InsetList({
  children,
  className,
  ...rest
}: React.HTMLAttributes<HTMLElement> & { children: React.ReactNode }) {
  return (
    <section className={cn("material-regular overflow-hidden rounded-card squircle", className)} {...rest}>
      {children}
    </section>
  );
}

export type RowTone = "default" | "teal" | "red" | "sand" | "sage" | "navy";

const iconTone: Record<RowTone, string> = {
  default: "bg-fill-quaternary text-label-secondary",
  navy: "bg-navy/10 text-ink-navy",
  teal: "bg-teal-soft text-ink-teal",
  red: "bg-red-soft text-ink-red",
  sand: "bg-sand-soft text-ink-sand",
  sage: "bg-sage-soft text-ink-sage",
};

const valueTone: Record<RowTone, string> = {
  default: "text-label",
  navy: "text-ink-navy",
  teal: "text-ink-teal",
  red: "text-ink-red",
  sand: "text-ink-sand",
  sage: "text-ink-sage",
};

/**
 * One row. `href` makes the whole row a link (44pt minimum target, keyboard
 * reachable, system focus ring); without it the row is static content.
 *
 * The hairline lives on the *inner* column so it starts where the text starts,
 * the way UITableView insets its separators.
 */
export function InsetRow({
  href,
  icon: Icon,
  leading,
  title,
  subtitle,
  value,
  valueCaption,
  tone = "default",
  trailing,
  className,
}: {
  href?: string;
  icon?: LucideIcon;
  /** Custom leading element, used instead of `icon` (e.g. an avatar or a rank). */
  leading?: React.ReactNode;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  value?: React.ReactNode;
  valueCaption?: React.ReactNode;
  tone?: RowTone;
  trailing?: React.ReactNode;
  className?: string;
}) {
  const lead =
    leading ??
    (Icon ? (
      <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-md squircle", iconTone[tone])} aria-hidden>
        <Icon className="h-4 w-4" strokeWidth={1.9} />
      </span>
    ) : null);

  const body = (
    <div className="flex min-h-[44px] flex-1 items-center gap-3 border-t border-separator py-2.5 group-first/row:border-t-0">
      <div className="min-w-0 flex-1">
        <div className="truncate text-callout font-medium text-label">{title}</div>
        {subtitle ? <div className="mt-0.5 truncate text-footnote text-label-secondary">{subtitle}</div> : null}
      </div>
      {value !== undefined || valueCaption !== undefined ? (
        <div className="shrink-0 text-right">
          {value !== undefined ? <div className={cx("text-callout font-semibold tabular", valueTone[tone])}>{value}</div> : null}
          {valueCaption !== undefined ? <div className="mt-0.5 text-caption-1 text-label-secondary tabular">{valueCaption}</div> : null}
        </div>
      ) : null}
      {trailing}
      {href ? <ChevronRight className="h-4 w-4 shrink-0 text-label-tertiary" aria-hidden /> : null}
    </div>
  );

  const inner = (
    <>
      {lead ? <div className="flex shrink-0 items-center py-2.5">{lead}</div> : null}
      {body}
    </>
  );

  const shell = "group/row flex w-full items-stretch gap-3 px-4 text-left";

  if (!href) return <div className={cn(shell, className)}>{inner}</div>;

  return (
    <Link
      href={href}
      className={cn(
        shell,
        "transition-colors duration-quick ease-sys hover:bg-fill-quaternary active:bg-fill-tertiary",
        className,
      )}
    >
      {inner}
    </Link>
  );
}

/**
 * Empty state for a group — always says what to do next, never just "No data".
 * `action` is the thing to do; `hint` is why it is worth doing.
 */
export function InsetEmpty({
  icon: Icon,
  title,
  hint,
  action,
}: {
  icon: LucideIcon;
  title: string;
  hint: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center px-6 py-8 text-center">
      <span className="mb-3 flex h-10 w-10 items-center justify-center rounded-full bg-fill-quaternary text-label-tertiary" aria-hidden>
        <Icon className="h-4 w-4" strokeWidth={1.75} />
      </span>
      <p className="text-callout font-medium text-label">{title}</p>
      <p className="mt-1 max-w-[34ch] text-footnote text-label-secondary">{hint}</p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
