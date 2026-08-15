import * as React from "react";
import type { LucideIcon } from "lucide-react";
import { HelpCircle, Sparkles, Users, UtensilsCrossed, Wifi, Wrench } from "lucide-react";
import type { ComplaintCategory } from "@/lib/types";
import { cn } from "@/lib/utils";

/** category → lucide icon (OW-1 / OW-2 list rows) */
export const COMPLAINT_ICON: Record<ComplaintCategory, LucideIcon> = {
  food: UtensilsCrossed,
  cleaning: Sparkles,
  maintenance: Wrench,
  wifi: Wifi,
  roommate: Users,
  other: HelpCircle,
};

export function ComplaintCategoryIcon({ category, className, size = "md" }: { category: ComplaintCategory; className?: string; size?: "sm" | "md" }) {
  const Icon = COMPLAINT_ICON[category] ?? HelpCircle;
  return (
    <span
      className={cn(
        "flex shrink-0 items-center justify-center rounded-full bg-navy/5 text-navy/70",
        size === "sm" ? "h-8 w-8" : "h-10 w-10",
        className,
      )}
      aria-hidden
    >
      <Icon className={size === "sm" ? "h-3.5 w-3.5" : "h-4 w-4"} strokeWidth={1.75} />
    </span>
  );
}
