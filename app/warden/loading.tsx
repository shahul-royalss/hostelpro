import { Skeleton } from "@/components/ui/misc";

/** Mobile skeleton shown while any /warden route streams in. */
export default function WardenLoading() {
  return (
    <div className="mx-auto w-full max-w-[480px] px-page-mobile pt-[80px] pb-[104px]" aria-busy="true" aria-label="Loading">
      <Skeleton className="mb-4 h-4 w-48" />
      <div className="flex flex-col gap-4">
        <div className="glass-card p-5">
          <Skeleton className="mb-3 h-4 w-24" />
          <Skeleton className="mb-3 h-9 w-40" />
          <Skeleton className="mb-4 h-1.5 w-full" />
          <div className="grid grid-cols-2 gap-3">
            <Skeleton className="h-10" />
            <Skeleton className="h-10" />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-[112px] rounded-card" />
          ))}
        </div>
        <div className="glass-card p-5">
          <Skeleton className="mb-3 h-4 w-32" />
          <Skeleton className="mb-2 h-4 w-full" />
          <Skeleton className="mb-2 h-4 w-5/6" />
          <Skeleton className="h-4 w-2/3" />
        </div>
      </div>
    </div>
  );
}
