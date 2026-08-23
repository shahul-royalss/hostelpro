import { Skeleton } from "@/components/ui/misc";

/** Mirrors <LeavesView>: the Leaves/Visitors tabs, pending requests, then history. */
export default function WardenLeavesLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <Skeleton className="h-[52px] w-full rounded-full" />

        <div className="flex flex-col gap-5">
          {/* Pending requests */}
          <section>
            <div className="mb-3 flex items-center justify-between px-1">
              <Skeleton className="h-6 w-40" />
              <Skeleton className="h-6 w-16 rounded-full" />
            </div>
            <ul className="flex flex-col gap-3">
              {Array.from({ length: 2 }).map((_, i) => (
                <li key={i} className="glass-card p-4">
                  <div className="flex items-center gap-3">
                    <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                    <div className="min-w-0 flex-1">
                      <Skeleton className="h-4 w-36" />
                      <Skeleton className="mt-1.5 h-3 w-48" />
                    </div>
                  </div>
                  <div className="mt-3 flex flex-col gap-1.5 rounded-control bg-white/50 p-3">
                    <Skeleton className="h-4 w-52" />
                    <Skeleton className="h-4 w-full" />
                  </div>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <Skeleton className="h-12 w-full" />
                    <Skeleton className="h-12 w-full" />
                  </div>
                </li>
              ))}
            </ul>
          </section>

          {/* History */}
          <section>
            <Skeleton className="mb-3 ml-1 h-6 w-24" />
            <ul className="flex flex-col gap-3">
              {Array.from({ length: 4 }).map((_, i) => (
                <li key={i} className="glass-card flex items-center gap-3 p-4">
                  <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                  <div className="min-w-0 flex-1">
                    <Skeleton className="h-4 w-32" />
                    <Skeleton className="mt-1.5 h-3 w-44" />
                  </div>
                  <Skeleton className="h-5 w-16 shrink-0 rounded-full" />
                </li>
              ))}
            </ul>
          </section>
        </div>
      </div>
    </div>
  );
}
