import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function SuperAdminHostelsLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div className="space-y-2">
          <Skeleton className="h-7 w-32" />
          <Skeleton className="h-4 w-96" />
        </div>
        <Skeleton className="h-10 w-52 shrink-0" />
      </div>

      <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <Skeleton className="h-10 w-full max-w-md rounded-full" />
        <Skeleton className="h-10 w-full md:w-72" />
      </div>

      <GlassCard padded={false}>
        <div className="flex items-center gap-4 border-b border-line/70 px-6 py-3">
          <Skeleton className="h-3 w-24" />
          <Skeleton className="h-3 w-20" />
          <Skeleton className="hidden h-3 w-24 lg:block" />
          <Skeleton className="ml-auto h-3 w-20" />
        </div>
        <div className="divide-y divide-line/70">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="flex items-center gap-4 px-6 py-3.5">
              <Skeleton className="h-4 w-40" />
              <Skeleton className="h-4 w-32" />
              <Skeleton className="hidden h-2 w-40 rounded-full lg:block" />
              <Skeleton className="hidden h-4 w-12 lg:block" />
              <Skeleton className="h-6 w-20 rounded-full" />
              <Skeleton className="ml-auto h-8 w-8 rounded-full" />
            </div>
          ))}
        </div>
      </GlassCard>
    </div>
  );
}
