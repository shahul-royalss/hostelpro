import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function Loading() {
  return (
    <div aria-busy="true" aria-live="polite">
      <div className="mb-6 flex items-end justify-between">
        <div className="space-y-2">
          <Skeleton className="h-7 w-48" />
          <Skeleton className="h-4 w-72" />
        </div>
        <Skeleton className="h-10 w-40" />
      </div>
      <div className="grid grid-cols-2 gap-4 md:grid-cols-3 md:gap-6 xl:grid-cols-6">
        {Array.from({ length: 6 }).map((_, i) => (
          <GlassCard key={i} className="space-y-3">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-9 w-20" />
            <Skeleton className="h-3 w-28" />
          </GlassCard>
        ))}
      </div>
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <GlassCard className="space-y-4 lg:col-span-2">
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-64 w-full rounded-card" />
        </GlassCard>
        <GlassCard className="space-y-4">
          <Skeleton className="h-4 w-40" />
          <Skeleton className="mx-auto h-48 w-48 rounded-full" />
        </GlassCard>
      </div>
      <GlassCard className="mt-6 space-y-3">
        <Skeleton className="h-4 w-40" />
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </GlassCard>
    </div>
  );
}
