import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerComplaintsLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-4 w-40" />
      </div>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(300px,400px)_1fr]">
        <GlassCard padded={false}>
          <div className="space-y-3 border-b border-line/70 p-4">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-8 w-72 rounded-full" />
          </div>
          <div className="space-y-4 p-4">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="h-8 w-8 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-4 w-3/4" />
                  <Skeleton className="h-3 w-1/2" />
                </div>
              </div>
            ))}
          </div>
        </GlassCard>
        <GlassCard className="space-y-4">
          <Skeleton className="h-6 w-2/3" />
          <Skeleton className="h-14 w-full" />
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-32 w-full" />
        </GlassCard>
      </div>
    </div>
  );
}
