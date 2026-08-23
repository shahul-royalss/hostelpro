import { Skeleton } from "@/components/ui/misc";

/** Mirrors the collapsed complaint rows in <ComplaintsView>. */
export default function StudentComplaintsLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <ul className="flex flex-col gap-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <li key={i} className="glass-card flex items-center gap-3 p-4">
            <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
            <div className="min-w-0 flex-1">
              <Skeleton className="h-4 w-3/4" />
              <Skeleton className="mt-1.5 h-3 w-1/2" />
            </div>
            <Skeleton className="h-5 w-16 shrink-0 rounded-full" />
            <Skeleton className="h-4 w-4 shrink-0" />
          </li>
        ))}
      </ul>
    </div>
  );
}
