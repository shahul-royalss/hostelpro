import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerFinanceLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 flex items-end justify-between">
        <div className="space-y-2">
          <Skeleton className="h-7 w-48" />
          <Skeleton className="h-4 w-80" />
        </div>
        <Skeleton className="h-10 w-44 rounded-full" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 lg:gap-6">
        {Array.from({ length: 3 }).map((_, i) => (
          <GlassCard key={i} className="space-y-3">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-9 w-28" />
            <Skeleton className="h-3 w-32" />
          </GlassCard>
        ))}
      </div>
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-5">
        <GlassCard className="lg:col-span-2">
          <Skeleton className="mb-4 h-5 w-44" />
          <Skeleton className="mx-auto h-[200px] w-[200px] rounded-full" />
        </GlassCard>
        <GlassCard className="lg:col-span-3">
          <Skeleton className="mb-4 h-5 w-40" />
          <Skeleton className="h-[280px] w-full rounded-card" />
        </GlassCard>
      </div>
      <GlassCard className="mt-6 space-y-3">
        <Skeleton className="h-5 w-32" />
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-9 w-full" />
        ))}
      </GlassCard>
    </div>
  );
}
