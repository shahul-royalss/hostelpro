import { Skeleton } from "@/components/ui/misc";

/** Mirrors <VisitorsView>: tabs, log-visitor button, today's list, history toggle. */
export default function WardenVisitorsLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <Skeleton className="h-[52px] w-full rounded-full" />

        <div className="flex flex-col gap-5">
          <Skeleton className="h-12 w-full" />

          {/* Today */}
          <section>
            <div className="mb-3 flex items-center justify-between px-1">
              <Skeleton className="h-6 w-20" />
              <Skeleton className="h-3 w-24" />
            </div>
            <ul className="flex flex-col gap-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <li key={i} className="glass-card p-4">
                  <div className="flex items-center gap-3">
                    <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                    <div className="min-w-0 flex-1">
                      <Skeleton className="h-4 w-36" />
                      <Skeleton className="mt-1.5 h-3 w-48" />
                    </div>
                    <Skeleton className="h-9 w-24 shrink-0" />
                  </div>
                </li>
              ))}
            </ul>
          </section>

          {/* History header (collapsed) */}
          <section>
            <div className="mb-3 flex w-full items-center justify-between px-1">
              <Skeleton className="h-6 w-48" />
              <Skeleton className="h-4 w-10" />
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
