import { Skeleton } from "@/components/ui/misc";

/** Mobile skeleton shown while any /student route streams in. */
export default function StudentLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <div className="glass-card p-5">
          <div className="flex items-start gap-3">
            <Skeleton className="h-11 w-11 rounded-control" />
            <div className="flex-1">
              <Skeleton className="mb-2 h-3 w-16" />
              <Skeleton className="mb-2 h-6 w-48" />
              <Skeleton className="h-3 w-28" />
            </div>
          </div>
          <Skeleton className="mt-4 h-14 w-full rounded-control" />
        </div>
        <div className="glass-card p-5">
          <Skeleton className="mb-4 h-4 w-36" />
          <div className="flex flex-col gap-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="h-8 w-8 rounded-full" />
                <div className="flex-1">
                  <Skeleton className="mb-2 h-4 w-3/4" />
                  <Skeleton className="h-3 w-full" />
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-[112px] rounded-card" />
          ))}
        </div>
      </div>
    </div>
  );
}
