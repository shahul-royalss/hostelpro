import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * Sticky bottom action bar for mobile pages (thumb-reachable CTAs).
 *  • bottom="nav"        → sits above the 76px bottom nav (pages that keep the nav)
 *  • bottom="nav-hidden" → sits at the very bottom (pages rendered with hideNav)
 */
export function StickyBar({
  children,
  bottom = "nav",
  className,
}: {
  children: React.ReactNode;
  bottom?: "nav" | "nav-hidden";
  className?: string;
}) {
  return (
    <div
      className={cn(
        "glass-bar fixed inset-x-0 z-30 mx-auto flex max-w-[480px] items-center gap-3 border-t px-4 py-3",
        bottom === "nav" ? "bottom-[92px] rounded-t-card" : "bottom-0 pb-safe",
        className,
      )}
    >
      {children}
    </div>
  );
}
