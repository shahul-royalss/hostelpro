import { Skeleton } from "@/components/ui/misc";

/** Mirrors <RoomList>: floor filter pills then one card per room. */
export default function WardenRoomsLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <div className="flex flex-col gap-4">
        <Skeleton className="h-8 w-full rounded-full" />
        <ul className="flex flex-col gap-3">
          {Array.from({ length: 7 }).map((_, i) => (
            <li key={i} className="glass-card flex items-center gap-3 p-4">
              <Skeleton className="h-11 w-11 shrink-0 rounded-full" />
              <div className="min-w-0 flex-1">
                <Skeleton className="h-5 w-28" />
                <Skeleton className="mt-1.5 h-3 w-16" />
              </div>
              <div className="flex shrink-0 flex-col items-end gap-1.5">
                <Skeleton className="h-2.5 w-16 rounded-full" />
                <Skeleton className="h-3 w-24" />
              </div>
              <Skeleton className="h-11 w-11 shrink-0 rounded-full" />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
