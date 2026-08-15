import Link from "next/link";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export interface QuickTile {
  href: string;
  label: string;
  icon: LucideIcon;
  tone?: "navy" | "teal" | "sand" | "red" | "sage";
}

const iconTone = {
  navy: "bg-navy/10 text-navy",
  teal: "bg-teal-soft text-teal",
  sand: "bg-sand-soft text-sand-deep",
  red: "bg-red-soft text-red",
  sage: "bg-sage-soft text-sage",
};

/** 2×2 quick-action grid of frosted tiles (ST-1). */
export function QuickGrid({ tiles, className }: { tiles: QuickTile[]; className?: string }) {
  return (
    <div className={cn("grid grid-cols-2 gap-4", className)}>
      {tiles.map((t) => {
        const Icon = t.icon;
        return (
          <Link
            key={t.href}
            href={t.href}
            className="glass-card flex min-h-[112px] flex-col items-center justify-center gap-3 p-4 text-center transition-all active:scale-[0.97] hover:bg-white/80"
          >
            <span className={cn("flex h-11 w-11 items-center justify-center rounded-full", iconTone[t.tone ?? "navy"])}>
              <Icon className="h-5 w-5" strokeWidth={1.75} />
            </span>
            <span className="text-sm font-medium text-navy">{t.label}</span>
          </Link>
        );
      })}
    </div>
  );
}
