import { Skeleton } from "@/components/ui/misc";

/** Rows per <DetailSection>: Personal, Guardian, Address, ID proof, Room & fee. */
const SECTION_ROWS = [2, 2, 1, 1, 4];

export default function StudentProfileLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        {/* Header card */}
        <div className="glass-card-strong flex flex-col items-center rounded-card p-6">
          <Skeleton className="h-20 w-20 rounded-full" />
          <Skeleton className="mt-3 h-5 w-40" />
          <Skeleton className="mt-2 h-4 w-32" />
          <div className="mt-3 flex items-center gap-2">
            <Skeleton className="h-5 w-16 rounded-full" />
            <Skeleton className="h-4 w-28" />
          </div>
        </div>

        {/* Detail sections */}
        {SECTION_ROWS.map((rows, s) => (
          <div key={s} className="glass-card">
            <Skeleton className="mx-5 mt-4 h-3 w-20" />
            <div className="divide-y divide-line px-5">
              {Array.from({ length: rows }).map((_, r) => (
                <div key={r} className="flex items-center justify-between gap-4 py-3.5">
                  <Skeleton className="h-3.5 w-24 shrink-0" />
                  <Skeleton className="h-4 w-32" />
                </div>
              ))}
            </div>
          </div>
        ))}

        <Skeleton className="mx-auto h-3 w-56" />

        {/* Change password link */}
        <div className="glass-card flex items-center gap-3 p-4">
          <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
          <Skeleton className="h-4 flex-1" />
          <Skeleton className="h-5 w-5 shrink-0" />
        </div>

        {/* Delete account card */}
        <div className="glass-card border border-red/20 p-5 md:p-6">
          <div className="flex items-start gap-3">
            <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-5 w-52" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-4/5" />
            </div>
          </div>
          <Skeleton className="mt-4 h-10 w-44" />
        </div>

        {/* Log out */}
        <Skeleton className="h-12 w-full" />
      </div>
    </div>
  );
}
