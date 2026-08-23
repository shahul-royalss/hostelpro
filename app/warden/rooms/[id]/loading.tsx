import { Skeleton } from "@/components/ui/misc";

/** Mirrors <RoomDetailView>: room summary card then one card per bed. */
export default function WardenRoomDetailLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        {/* Summary */}
        <div className="glass-card p-5 md:p-6">
          <div className="mb-3 flex items-start justify-between gap-3">
            <div>
              <Skeleton className="h-5 w-32" />
              <Skeleton className="mt-1.5 h-3.5 w-44" />
            </div>
            <div className="flex items-center gap-1">
              <Skeleton className="h-5 w-16 rounded-full" />
              <Skeleton className="h-9 w-9 rounded-full" />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i}>
                <Skeleton className="h-3 w-16" />
                <Skeleton className="mt-1.5 h-8 w-12" />
              </div>
            ))}
          </div>
        </div>

        <Skeleton className="ml-1 h-6 w-48" />

        {/* Bed cards */}
        <ul className="flex flex-col gap-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <li key={i} className="glass-card p-4">
              <div className="mb-3 flex items-center justify-between gap-2">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-5 w-16 rounded-full" />
              </div>
              <div className="flex items-center gap-3">
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                <div className="min-w-0 flex-1">
                  <Skeleton className="h-4 w-36" />
                  <Skeleton className="mt-1.5 h-3 w-44" />
                </div>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
