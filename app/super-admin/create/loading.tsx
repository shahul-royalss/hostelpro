import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

export default function CreateOwnerHostelLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-64" />
        <Skeleton className="h-4 w-full max-w-xl" />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        {/* Wizard card */}
        <GlassCard className="flex flex-col p-0" padded={false}>
          <div className="border-b border-line/70 px-6 pt-6 pb-5 md:px-8">
            <div className="flex items-center">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="flex flex-1 items-center last:flex-none">
                  <div className="flex flex-col items-center gap-1.5">
                    <Skeleton className="h-8 w-8 rounded-full" />
                    <Skeleton className="h-3 w-16" />
                  </div>
                  {i < 3 ? <Skeleton className="mx-3 mb-5 h-px flex-1 rounded-none" /> : null}
                </div>
              ))}
            </div>
          </div>

          <div className="flex-1 px-6 py-6 md:px-8">
            <Skeleton className="h-6 w-48" />
            <Skeleton className="mb-6 mt-2 h-4 w-full max-w-lg" />
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="flex flex-col gap-1.5">
                  <Skeleton className="h-3 w-24" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ))}
            </div>
          </div>

          <div className="flex items-center justify-between gap-3 border-t border-line/70 px-6 py-4 md:px-8">
            <Skeleton className="h-10 w-24" />
            <Skeleton className="h-10 w-32" />
          </div>
        </GlassCard>

        {/* Summary panel */}
        <div className="space-y-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <GlassCard key={i} className="p-5">
              <div className="mb-3 flex items-center gap-2">
                <Skeleton className="h-4 w-4 rounded-full" />
                <Skeleton className="h-4 w-32" />
              </div>
              <div className="space-y-2.5">
                {Array.from({ length: 3 }).map((_, r) => (
                  <div key={r} className="flex items-center justify-between gap-3">
                    <Skeleton className="h-3 w-20" />
                    <Skeleton className="h-3 w-24" />
                  </div>
                ))}
              </div>
            </GlassCard>
          ))}
          <GlassCard className="p-5">
            <div className="mb-2 flex items-center gap-2">
              <Skeleton className="h-4 w-4 rounded-full" />
              <Skeleton className="h-4 w-20" />
            </div>
            <div className="space-y-2">
              <Skeleton className="h-3.5 w-full" />
              <Skeleton className="h-3.5 w-full" />
              <Skeleton className="h-3.5 w-2/3" />
            </div>
          </GlassCard>
        </div>
      </div>
    </div>
  );
}
