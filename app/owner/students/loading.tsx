import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function OwnerStudentsLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-36" />
        <Skeleton className="h-4 w-96" />
      </div>
      <GlassCard padded={false}>
        <div className="flex items-center justify-between gap-3 border-b border-line/70 p-4">
          <Skeleton className="h-10 w-72" />
          <Skeleton className="h-9 w-64 rounded-full" />
        </div>
        <div className="space-y-3 p-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="flex items-center gap-4">
              <Skeleton className="h-8 w-8 rounded-full" />
              <Skeleton className="h-4 w-40" />
              <Skeleton className="h-4 w-16" />
              <Skeleton className="h-4 w-28" />
              <Skeleton className="ml-auto h-6 w-16 rounded-full" />
            </div>
          ))}
        </div>
      </GlassCard>
    </div>
  );
}
