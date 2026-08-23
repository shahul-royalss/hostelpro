import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

const DAYS = 7;
const MEALS = 4;

export default function ManagerMenuLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-56" />
        <Skeleton className="h-4 w-72" />
      </div>

      <GlassCard padded={false} className="overflow-hidden">
        {/* Desktop / tablet day x meal grid */}
        <div className="hidden md:block">
          <div className="grid grid-cols-[120px_repeat(4,minmax(0,1fr))] border-b border-line/70 bg-white/40">
            <div className="px-5 py-3">
              <Skeleton className="h-3 w-10" />
            </div>
            {Array.from({ length: MEALS }).map((_, i) => (
              <div key={i} className="space-y-1.5 px-3 py-3">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-3 w-20" />
              </div>
            ))}
          </div>
          <div className="divide-y divide-line/60">
            {Array.from({ length: DAYS }).map((_, d) => (
              <div key={d} className="grid grid-cols-[120px_repeat(4,minmax(0,1fr))] items-start gap-x-3 px-2 py-3">
                <div className="px-3 pt-2">
                  <Skeleton className="h-4 w-20" />
                </div>
                {Array.from({ length: MEALS }).map((_, m) => (
                  <div key={m} className="px-1">
                    <Skeleton className="h-16 w-full" />
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>

        {/* Mobile: one stacked card per day */}
        <div className="divide-y divide-line/60 md:hidden">
          {Array.from({ length: DAYS }).map((_, d) => (
            <section key={d} className="p-4">
              <Skeleton className="mb-3 h-4 w-24" />
              <div className="space-y-3">
                {Array.from({ length: MEALS }).map((_, m) => (
                  <div key={m} className="space-y-1">
                    <Skeleton className="h-3 w-32" />
                    <Skeleton className="h-16 w-full" />
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      </GlassCard>

      {/* Sticky save/reset footer */}
      <div className="sticky bottom-0 z-20 mt-4 pb-4">
        <div className="glass-card-strong flex flex-col gap-3 rounded-card px-4 py-3 sm:flex-row sm:items-center sm:justify-between md:px-5">
          <Skeleton className="h-4 w-56" />
          <div className="flex shrink-0 items-center gap-2">
            <Skeleton className="h-10 w-28" />
            <Skeleton className="h-10 w-36" />
          </div>
        </div>
      </div>
    </div>
  );
}
