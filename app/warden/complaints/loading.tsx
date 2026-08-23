import { Skeleton } from "@/components/ui/misc";

/** Mirrors <ComplaintsView>: status filter pills then compact complaint rows. */
export default function WardenComplaintsLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-full rounded-full" />
        <ul className="flex flex-col gap-2.5">
          {Array.from({ length: 6 }).map((_, i) => (
            <li key={i} className="glass-card flex items-center gap-3 p-3.5">
              <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
              <div className="min-w-0 flex-1">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="mt-1.5 h-3 w-1/2" />
              </div>
              <Skeleton className="h-5 w-16 shrink-0 rounded-full" />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
