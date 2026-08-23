import { Skeleton } from "@/components/ui/misc";

/** Mirrors <RegisterStudentForm> step 1. The bottom nav is hidden here (hideNav), so pb-8. */
export default function WardenRegisterLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-8" aria-busy="true" aria-label="Loading">
      <div className="-mt-2">
        {/* Sticky progress header */}
        <div className="-mx-4 px-4 pb-3 pt-1">
          <Skeleton className="h-1 w-full rounded-full" />
          <div className="no-scrollbar mt-2.5 flex gap-4 overflow-x-auto">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex shrink-0 items-center gap-1.5">
                <Skeleton className="h-4 w-4 rounded-full" />
                <Skeleton className="h-3 w-16" />
              </div>
            ))}
          </div>
        </div>

        {/* Step card */}
        <div className="pb-24">
          <Skeleton className="h-6 w-44" />
          <Skeleton className="mt-2 h-4 w-72" />
          <div className="glass-card mt-4 flex flex-col gap-4 p-5 md:p-6">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="flex flex-col gap-1.5">
                <Skeleton className="h-3 w-28" />
                <Skeleton className="h-10 w-full" />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
