import { Skeleton } from "@/components/ui/misc";

/** Mirrors /warden/announcements: a stack of announcement cards. */
export default function WardenAnnouncementsLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <ul className="flex flex-col gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <li key={i} className="glass-card p-5 md:p-6">
            <div className="mb-3 flex items-start justify-between gap-3">
              <Skeleton className="h-5 w-40" />
              <Skeleton className="h-5 w-16 shrink-0 rounded-full" />
            </div>
            <div className="space-y-2">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-2/3" />
            </div>
            <Skeleton className="mt-3 h-3 w-28" />
          </li>
        ))}
      </ul>
    </div>
  );
}
