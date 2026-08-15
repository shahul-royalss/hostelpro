import * as React from "react";
import { cn, titleCase } from "@/lib/utils";

/**
 * Status pills — full pills with soft tint + matching text (DESIGN.md §1):
 *   paid/success/resolved/active/approved/done  → teal
 *   pending/partial/expiring/in_progress/on_leave → sand
 *   unpaid/overdue/open/expired/rejected/suspended → red
 *   free/available → sage
 *   full/occupied/navy → navy
 */
export type PillTone = "teal" | "sand" | "red" | "sage" | "navy" | "muted";

const toneClass: Record<PillTone, string> = {
  teal: "bg-teal-soft text-teal",
  sand: "bg-sand-soft text-sand-deep",
  red: "bg-red-soft text-red",
  sage: "bg-sage-soft text-sage",
  navy: "bg-navy/10 text-navy",
  muted: "bg-stone text-muted",
};

export const STATUS_TONE: Record<string, PillTone> = {
  // fees
  paid: "teal", partial: "sand", unpaid: "red",
  // complaints / tasks / leaves
  open: "red", in_progress: "sand", resolved: "teal",
  pending: "sand", done: "teal", approved: "teal", rejected: "red",
  // subscription / hostel / user
  active: "teal", expiring: "sand", expired: "red", readonly: "sand", suspended: "red", inactive: "muted",
  // beds / students
  free: "sage", occupied: "navy", full: "navy", on_leave: "sand", vacated: "muted",
  // audiences
  all: "navy", manager: "teal", warden: "sand", students: "sage",
};

export const STATUS_LABEL: Record<string, string> = {
  in_progress: "In progress",
  on_leave: "On leave",
  readonly: "Read-only",
  all: "Everyone",
};

export function StatusPill({
  status,
  tone,
  label,
  className,
  size = "md",
  dot = false,
}: {
  status?: string | null;
  tone?: PillTone;
  label?: React.ReactNode;
  className?: string;
  size?: "sm" | "md";
  dot?: boolean;
}) {
  const t: PillTone = tone ?? (status ? STATUS_TONE[status] ?? "muted" : "muted");
  const text = label ?? (status ? STATUS_LABEL[status] ?? titleCase(status) : "");
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full font-semibold leading-none",
        size === "sm" ? "px-2 py-1 text-[10px] uppercase tracking-wider" : "px-2.5 py-1.5 text-xs",
        toneClass[t],
        className,
      )}
    >
      {dot ? <span className="h-1.5 w-1.5 rounded-full bg-current" /> : null}
      {text}
    </span>
  );
}

/** Small tinted chip for secondary info like "Room 204" */
export function Chip({ children, className, tone = "muted" }: { children: React.ReactNode; className?: string; tone?: PillTone }) {
  return (
    <span className={cn("inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium", toneClass[tone], className)}>
      {children}
    </span>
  );
}
