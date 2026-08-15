"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MonthSelector } from "@/components/shared/month-selector";

/** OW-6 month selector bound to `?month=YYYY-MM`. */
export function FinanceMonthNav({ value }: { value: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [pending, start] = React.useTransition();

  const onChange = (period: string) => {
    const next = new URLSearchParams(params.toString());
    next.set("month", period);
    start(() => router.push(`${pathname}?${next.toString()}`, { scroll: false }));
  };

  return (
    <div className={pending ? "opacity-60 transition-opacity" : "transition-opacity"} aria-busy={pending}>
      <MonthSelector value={value} onChange={onChange} variant="arrows" />
    </div>
  );
}
