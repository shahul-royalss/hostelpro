import { Skeleton } from "@/components/ui/misc";

/** Mirrors /student/room: room summary card then the roommate list. */
export default function StudentRoomLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        {/* Room card */}
        <div className="glass-card-strong rounded-card p-5 md:p-6">
          <div className="flex items-start justify-between gap-3">
            <div>
              <Skeleton className="h-3 w-16" />
              <Skeleton className="mt-1.5 h-8 w-36" />
            </div>
            <Skeleton className="h-8 w-28 rounded-full" />
          </div>
          <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1">
            <Skeleton className="h-4 w-20" />
            <Skeleton className="h-4 w-24" />
          </div>
          <div className="mt-4 flex items-center justify-between gap-3 rounded-control bg-white/60 px-3.5 py-3">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-3 w-32" />
          </div>
        </div>

        {/* Roommates */}
        <section>
          <Skeleton className="mb-3 h-5 w-28" />
          <ul className="flex flex-col gap-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <li key={i} className="glass-card flex items-center gap-3 p-4">
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                <div className="min-w-0 flex-1">
                  <Skeleton className="h-4 w-36" />
                  <Skeleton className="mt-1.5 h-3 w-28" />
                </div>
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
