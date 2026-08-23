import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function ManagerExpensesLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-4 w-80" />
      </div>

      {/* Add expense card */}
      <GlassCard>
        <div className="mb-4 space-y-2">
          <Skeleton className="h-5 w-32" />
          <Skeleton className="h-3.5 w-96" />
        </div>
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1fr_1fr_minmax(220px,0.9fr)]">
          <div className="grid gap-4 lg:col-span-3 lg:grid-cols-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="flex flex-col gap-1.5">
                <Skeleton className="h-3 w-20" />
                <Skeleton className="h-10 w-full" />
              </div>
            ))}
            <div className="flex flex-col gap-1.5 lg:col-span-3">
              <Skeleton className="h-3 w-12" />
              <Skeleton className="h-[72px] w-full" />
            </div>
          </div>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Skeleton className="h-3 w-16" />
              <Skeleton className="h-[132px] w-full" />
              <Skeleton className="h-3 w-44" />
            </div>
            <Skeleton className="mt-auto h-10 w-full" />
          </div>
        </div>
      </GlassCard>

      {/* This month table */}
      <GlassCard padded={false} className="mt-6">
        <div className="p-5 pb-0 md:p-6 md:pb-0">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div className="space-y-2">
              <Skeleton className="h-5 w-28" />
              <Skeleton className="h-3.5 w-48" />
            </div>
            <Skeleton className="h-9 w-44 rounded-full" />
          </div>
          <Skeleton className="mb-4 h-8 w-80 rounded-full" />
        </div>
        <div className="space-y-4 px-5 pb-5 md:px-6">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="flex items-center gap-4">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-6 w-20 rounded-full" />
              <Skeleton className="h-4 w-20" />
              <Skeleton className="hidden h-4 w-48 md:block" />
              <Skeleton className="ml-auto h-8 w-16" />
            </div>
          ))}
        </div>
        <div className="flex flex-col gap-3 border-t border-line/70 p-5 sm:flex-row sm:items-center sm:justify-between md:px-6">
          <div className="space-y-2">
            <Skeleton className="h-3 w-32" />
            <Skeleton className="h-7 w-28" />
          </div>
          <Skeleton className="h-10 w-32" />
        </div>
      </GlassCard>
    </div>
  );
}
