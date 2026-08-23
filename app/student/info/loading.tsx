import { Skeleton } from "@/components/ui/misc";

/** Mirrors /student/info: hostel card, two contact cards, rules list. */
export default function StudentInfoLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        {/* Hostel card */}
        <div className="glass-card-strong rounded-card p-5">
          <div className="flex items-start gap-3">
            <Skeleton className="h-11 w-11 shrink-0" />
            <div className="min-w-0 flex-1">
              <Skeleton className="h-3 w-20" />
              <Skeleton className="mt-1.5 h-6 w-48" />
              <Skeleton className="mt-2 h-4 w-full" />
              <Skeleton className="mt-2 h-3 w-32" />
            </div>
          </div>
        </div>

        {/* Contacts */}
        <section>
          <Skeleton className="mb-3 ml-1 h-5 w-24" />
          <div className="flex flex-col gap-3">
            {Array.from({ length: 2 }).map((_, i) => (
              <div key={i} className="glass-card flex items-center gap-3 p-4">
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
                <div className="min-w-0 flex-1">
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="mt-1.5 h-4 w-32" />
                  <Skeleton className="mt-1.5 h-3 w-24" />
                </div>
                <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
              </div>
            ))}
          </div>
          <Skeleton className="mt-2 ml-1 h-3 w-64" />
        </section>

        {/* Rules */}
        <div className="glass-card p-5 md:p-6">
          <div className="mb-4 space-y-2">
            <Skeleton className="h-5 w-28" />
            <Skeleton className="h-3.5 w-36" />
          </div>
          <div className="flex flex-col gap-2.5">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="h-5 w-5 shrink-0 rounded-full" />
                <Skeleton className="h-4 flex-1" />
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
