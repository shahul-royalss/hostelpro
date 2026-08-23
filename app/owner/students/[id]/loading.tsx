import { Skeleton } from "@/components/ui/misc";
import { GlassCard } from "@/components/shared/glass-card";

/** Rows per read-only section of <StudentProfile>: Stay, Guardian, ID proof. */
const SECTION_ROWS = [3, 2, 1];

export default function OwnerStudentDetailLoading() {
  return (
    <div aria-busy="true" aria-label="Loading">
      <div className="mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div className="space-y-2">
          <Skeleton className="h-3 w-28" />
          <Skeleton className="h-7 w-56" />
          <Skeleton className="h-4 w-80" />
        </div>
        <Skeleton className="h-9 w-32 shrink-0" />
      </div>

      <div className="mx-auto max-w-2xl">
        <GlassCard>
          <div className="space-y-6">
            {/* Avatar header */}
            <div className="flex flex-col items-center">
              <Skeleton className="h-24 w-24 rounded-full" />
              <Skeleton className="mt-3 h-6 w-48" />
              <Skeleton className="mt-1.5 h-4 w-36" />
              <Skeleton className="mt-1.5 h-3.5 w-52" />
              <div className="mt-2 flex items-center gap-2">
                <Skeleton className="h-6 w-20 rounded-full" />
                <Skeleton className="h-6 w-24 rounded-full" />
              </div>
            </div>

            {/* Room + fee tiles */}
            <div className="grid grid-cols-2 gap-3">
              {Array.from({ length: 2 }).map((_, i) => (
                <div key={i} className="space-y-1.5 rounded-control border border-line/70 bg-white/60 px-3.5 py-3">
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="h-6 w-24" />
                  <Skeleton className="h-3 w-20" />
                </div>
              ))}
            </div>

            {/* Stay / Guardian / ID proof */}
            {SECTION_ROWS.map((rows, s) => (
              <section key={s}>
                <Skeleton className="mb-2 h-3 w-20" />
                <div className="divide-y divide-line/60 rounded-control border border-line/70 bg-white/60 px-3.5">
                  {Array.from({ length: rows }).map((_, r) => (
                    <div key={r} className="flex items-center justify-between gap-3 py-2.5">
                      <Skeleton className="h-4 w-24" />
                      <Skeleton className="h-4 w-32" />
                    </div>
                  ))}
                </div>
              </section>
            ))}

            {/* Address */}
            <section>
              <Skeleton className="mb-2 h-3 w-20" />
              <div className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-2/3" />
              </div>
            </section>
          </div>
        </GlassCard>
      </div>
    </div>
  );
}
