import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerStaffLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-44" />
        <Skeleton className="h-4 w-96" />
      </div>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {Array.from({ length: 2 }).map((_, i) => (
          <GlassCard key={i} className="space-y-4">
            <Skeleton className="h-3 w-20" />
            <div className="flex gap-4">
              <Skeleton className="h-20 w-20 rounded-full" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-6 w-48" />
                <Skeleton className="h-4 w-36" />
                <Skeleton className="h-4 w-56" />
              </div>
            </div>
            <Skeleton className="h-8 w-64" />
          </GlassCard>
        ))}
      </div>
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <GlassCard className="space-y-4 lg:col-span-2">
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-16 w-full rounded-card" />
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </GlassCard>
        <GlassCard className="space-y-4">
          <Skeleton className="h-5 w-32" />
          <Skeleton className="h-[180px] w-full" />
        </GlassCard>
      </div>
    </div>
  );
}
