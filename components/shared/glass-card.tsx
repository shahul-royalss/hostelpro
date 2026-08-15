import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * Frosted translucent card — the core surface of the design language.
 * 20px radius, 65% white, 20px blur, soft wide shadow (DESIGN.md §1).
 */
export const GlassCard = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & { as?: "div" | "section" | "article"; padded?: boolean; strong?: boolean }
>(({ className, as: Tag = "div", padded = true, strong = false, ...props }, ref) => (
  <Tag
    ref={ref as never}
    className={cn(strong ? "glass-card-strong" : "glass-card", padded && "p-5 md:p-6", className)}
    {...props}
  />
));
GlassCard.displayName = "GlassCard";

export function GlassCardHeader({
  title,
  description,
  action,
  className,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("mb-4 flex items-start justify-between gap-3", className)}>
      <div className="min-w-0">
        <h2 className="text-card-title font-semibold text-navy">{title}</h2>
        {description ? <p className="mt-0.5 text-[13px] text-muted">{description}</p> : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}
