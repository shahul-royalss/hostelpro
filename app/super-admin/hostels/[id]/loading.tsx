import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function SuperAdminHostelDetailLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div className="space-y-2">
          <Skeleton className="h-3 w-20" />
          <Skeleton className="h-7 w-44" />
          <Skeleton className="h-4 w-96" />
        </div>
        <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
      </div>

      {/* Header card */}
      <GlassCard>
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div className="flex min-w-0 items-start gap-4">
            <Skeleton className="h-14 w-14 shrink-0 rounded-card" />
            <div className="min-w-0 space-y-2">
              <div className="flex items-center gap-2.5">
                <Skeleton className="h-6 w-56" />
                <Skeleton className="h-6 w-20 rounded-full" />
              </div>
              <div className="flex flex-wrap gap-x-5 gap-y-1.5">
                <Skeleton className="h-4 w-36" />
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-48" />
              </div>
              <div className="flex flex-wrap gap-x-5 gap-y-1.5">
                <Skeleton className="h-4 w-64" />
                <Skeleton className="h-4 w-52" />
              </div>
            </div>
          </div>
          <div className="flex shrink-0 flex-col items-start gap-3 lg:items-end">
            <div className="flex items-center gap-3">
              <div className="space-y-1.5">
                <Skeleton className="h-3 w-32" />
                <Skeleton className="h-5 w-28" />
              </div>
              <Skeleton className="h-7 w-20 rounded-full" />
            </div>
            <Skeleton className="h-10 w-52" />
          </div>
        </div>
      </GlassCard>

      {/* Stat cards */}
      <div className="mt-6 grid grid-cols-2 gap-4 md:gap-6 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <GlassCard key={i} className="flex h-full flex-col justify-between">
            <div className="mb-2 flex items-start justify-between gap-2">
              <Skeleton className="h-3 w-24" />
              <Skeleton className="h-5 w-5 shrink-0 rounded-full" />
            </div>
            <div className="mt-auto space-y-2">
              <Skeleton className="h-9 w-24" />
              <Skeleton className="h-3 w-28" />
            </div>
          </GlassCard>
        ))}
      </div>

      {/* Charts */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        {Array.from({ length: 2 }).map((_, i) => (
          <GlassCard key={i}>
            <div className="mb-4 space-y-2">
              <Skeleton className="h-5 w-48" />
              <Skeleton className="h-3.5 w-56" />
            </div>
            <Skeleton className="h-[260px] w-full rounded-card" />
          </GlassCard>
        ))}
      </div>

      {/* Staff + structure + subscription history */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6">
          <GlassCard>
            <div className="mb-4 space-y-2">
              <Skeleton className="h-5 w-20" />
              <Skeleton className="h-3.5 w-56" />
            </div>
            <div className="space-y-3">
              {Array.from({ length: 2 }).map((_, i) => (
                <div key={i} className="flex items-center gap-3 rounded-card border border-line/70 bg-white/50 p-3.5">
                  <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                  <div className="min-w-0 flex-1 space-y-2">
                    <Skeleton className="h-4 w-32" />
                    <Skeleton className="h-3 w-40" />
                  </div>
                </div>
              ))}
            </div>
          </GlassCard>
          <GlassCard>
            <div className="mb-4 flex items-start justify-between gap-3">
              <div className="space-y-2">
                <Skeleton className="h-5 w-24" />
                <Skeleton className="h-3.5 w-52" />
              </div>
              <Skeleton className="h-9 w-24 shrink-0" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="space-y-1.5 rounded-control bg-white/50 px-3 py-2">
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="h-4 w-12" />
                </div>
              ))}
            </div>
          </GlassCard>
        </div>

        <GlassCard className="lg:col-span-2">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div className="space-y-2">
              <Skeleton className="h-5 w-44" />
              <Skeleton className="h-3.5 w-64" />
            </div>
            <Skeleton className="h-9 w-36 shrink-0" />
          </div>
          <div className="space-y-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="flex items-start gap-3">
                <Skeleton className="h-8 w-8 shrink-0 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-4 w-56" />
                  <Skeleton className="h-3 w-40" />
                </div>
                <Skeleton className="h-4 w-20 shrink-0" />
              </div>
            ))}
          </div>
        </GlassCard>
      </div>
    </div>
  );
}
