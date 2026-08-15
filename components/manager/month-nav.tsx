"use client";

import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { MonthSelector } from "@/components/shared/month-selector";

/** MonthSelector bound to the `?month=YYYY-MM` search param. */
export function MonthNav({ value }: { value: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [pending, start] = React.useTransition();

  const onChange = (period: string) => {
    const next = new URLSearchParams(params.toString());
    next.set("month", period);
    start(() => router.push(`${pathname}?${next.toString()}`));
  };

  return (
    <div className={pending ? "opacity-60 transition-opacity" : "transition-opacity"}>
      <MonthSelector value={value} onChange={onChange} variant="arrows" />
    </div>
  );
}
