import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerUpdatesLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-40" />
        <Skeleton className="h-4 w-80" />
      </div>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        <GlassCard className="space-y-4 lg:col-span-3">
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-9 w-72 rounded-full" />
          <Skeleton className="h-[200px] w-full" />
          <Skeleton className="ml-auto h-11 w-40" />
        </GlassCard>
        <GlassCard className="space-y-4 lg:col-span-2">
          <Skeleton className="h-5 w-32" />
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="space-y-2">
              <Skeleton className="h-3 w-40" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-3 w-5/6" />
            </div>
          ))}
        </GlassCard>
      </div>
    </div>
  );
}
