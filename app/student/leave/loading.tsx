import { Skeleton } from "@/components/ui/misc";

/** Mirrors <LeaveView>: apply button, "My requests" heading, request cards. */
export default function StudentLeaveLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <Skeleton className="h-12 w-full" />

        <section>
          <div className="mb-3 flex items-baseline justify-between px-1">
            <Skeleton className="h-5 w-32" />
            <Skeleton className="h-3 w-24" />
          </div>
          <ul className="flex flex-col gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <li key={i} className="glass-card p-4">
                <div className="flex items-start gap-3">
                  <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <Skeleton className="h-4 w-40" />
                        <Skeleton className="mt-1.5 h-3 w-32" />
                      </div>
                      <Skeleton className="h-5 w-16 shrink-0 rounded-full" />
                    </div>
                    <Skeleton className="mt-2 h-4 w-full" />
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
