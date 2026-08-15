import Link from "next/link";
import { cn } from "@/lib/utils";

/** WD-6 shared top segmented control: Leaves | Visitors (route links). */
export function LeavesVisitorsTabs({ active, counts }: { active: "leaves" | "visitors"; counts?: { leaves?: number; visitors?: number } }) {
  const tabs = [
    { key: "leaves" as const, href: "/warden/leaves", label: "Leaves", count: counts?.leaves },
    { key: "visitors" as const, href: "/warden/visitors", label: "Visitors", count: counts?.visitors },
  ];
  return (
    <nav aria-label="Leaves and visitors" className="flex rounded-full border border-white/70 bg-white/60 p-1 backdrop-blur-md">
      {tabs.map((t) => {
        const isActive = t.key === active;
        return (
          <Link
            key={t.key}
            href={t.href}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "flex flex-1 items-center justify-center gap-1.5 rounded-full py-2 text-sm font-medium transition-all",
              isActive ? "bg-navy text-white shadow-sm" : "text-muted hover:text-navy",
            )}
          >
            {t.label}
            {typeof t.count === "number" && t.count > 0 ? (
              <span className={cn("rounded-full px-1.5 py-0.5 text-[10px] font-semibold tabular", isActive ? "bg-white/20" : "bg-navy/5 text-navy")}>{t.count}</span>
            ) : null}
          </Link>
        );
      })}
    </nav>
  );
}
