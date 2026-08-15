import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 flex items-center justify-between">
        <div className="space-y-2">
          <Skeleton className="h-7 w-56" />
          <Skeleton className="h-4 w-72" />
        </div>
        <Skeleton className="h-14 w-44 rounded-card" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5 lg:gap-6">
        {Array.from({ length: 5 }).map((_, i) => (
          <GlassCard key={i} className="space-y-3">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-9 w-28" />
            <Skeleton className="h-3 w-20" />
          </GlassCard>
        ))}
      </div>
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <GlassCard className="lg:col-span-2">
          <Skeleton className="mb-4 h-5 w-48" />
          <Skeleton className="h-[280px] w-full rounded-card" />
        </GlassCard>
        <div className="flex flex-col gap-6">
          <GlassCard className="space-y-3">
            <Skeleton className="h-5 w-32" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-5/6" />
            <Skeleton className="h-4 w-2/3" />
          </GlassCard>
          <GlassCard className="space-y-3">
            <Skeleton className="h-5 w-40" />
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-10 w-full" />
          </GlassCard>
        </div>
      </div>
    </div>
  );
}
