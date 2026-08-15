import * as React from "react";
import type { LucideIcon } from "lucide-react";
import { Inbox } from "lucide-react";
import { cn } from "@/lib/utils";

/** Empty state: one-line message + single navy action (DESIGN.md §4). */
export function EmptyState({
  icon: Icon = Inbox,
  title,
  description,
  action,
  className,
  compact = false,
}: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
  compact?: boolean;
}) {
  return (
    <div className={cn("flex flex-col items-center justify-center text-center", compact ? "py-8" : "py-14", className)}>
      <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-navy/5 text-navy/60">
        <Icon className="h-5 w-5" strokeWidth={1.75} />
      </div>
      <p className="text-sm font-medium text-navy">{title}</p>
      {description ? <p className="mt-1 max-w-xs text-[13px] text-muted">{description}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
