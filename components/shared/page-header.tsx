import * as React from "react";
import { cn } from "@/lib/utils";

/** Page title row (desktop 24px semibold / mobile 22px) with optional actions on the right. */
export function PageHeader({
  title,
  description,
  actions,
  className,
  eyebrow,
}: {
  title: React.ReactNode;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
  eyebrow?: React.ReactNode;
}) {
  return (
    <div className={cn("mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between", className)}>
      <div className="min-w-0">
        {eyebrow ? <div className="label-caps mb-1">{eyebrow}</div> : null}
        <h1 className="text-title-sm md:text-title text-navy">{title}</h1>
        {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
