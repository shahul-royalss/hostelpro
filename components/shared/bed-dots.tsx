import * as React from "react";
import { cn } from "@/lib/utils";

/** Bed-dot occupancy indicator: filled navy = occupied, sage outline = free (WD-3). */
export function BedDots({
  capacity,
  occupied,
  className,
  size = "md",
}: {
  capacity: number;
  occupied: number;
  className?: string;
  size?: "sm" | "md";
}) {
  const dot = size === "sm" ? "h-2 w-2" : "h-3 w-3";
  return (
    <div className={cn("flex flex-wrap items-center gap-1.5", className)} aria-label={`${occupied} of ${capacity} beds occupied`}>
      {Array.from({ length: Math.max(0, capacity) }, (_, i) => (
        <span
          key={i}
          className={cn(
            "rounded-full",
            dot,
            i < occupied ? "bg-navy" : "border-[1.5px] border-sage bg-transparent",
          )}
        />
      ))}
    </div>
  );
}
