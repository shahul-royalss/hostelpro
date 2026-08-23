import { Skeleton } from "@/components/ui/misc";

/** Mirrors <FeesView>: month chips, collected/pending strip, filters, ledger. */
export default function WardenFeesLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        {/* Month chips */}
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-9 w-24 shrink-0 rounded-full" />
          ))}
        </div>

        {/* Collected / pending */}
        <div className="grid grid-cols-2 gap-3">
          {Array.from({ length: 2 }).map((_, i) => (
            <div key={i} className="glass-card p-4">
              <div className="flex items-start justify-between gap-2">
                <Skeleton className="h-3 w-20" />
                <Skeleton className="h-4 w-4 shrink-0 rounded-full" />
              </div>
              <Skeleton className="mt-2 h-8 w-24" />
              <Skeleton className="mt-1.5 h-3 w-28" />
            </div>
          ))}
        </div>

        <Skeleton className="h-8 w-full rounded-full" />
        <Skeleton className="h-10 w-full" />

        {/* Ledger */}
        <ul className="flex flex-col gap-2.5">
          {Array.from({ length: 6 }).map((_, i) => (
            <li key={i} className="glass-card flex items-center gap-3 p-3.5">
              <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
              <div className="min-w-0 flex-1">
                <Skeleton className="h-4 w-32" />
                <Skeleton className="mt-1.5 h-3 w-40" />
              </div>
              <div className="flex shrink-0 flex-col items-end gap-1">
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-5 w-14 rounded-full" />
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
