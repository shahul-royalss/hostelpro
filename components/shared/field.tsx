import * as React from "react";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

/**
 * Form field wrapper: caps label + control + hint/error.
 * Works with plain forms (FormData server actions) and react-hook-form.
 */
export function Field({
  label,
  htmlFor,
  error,
  hint,
  required,
  className,
  children,
  right,
}: {
  label?: React.ReactNode;
  htmlFor?: string;
  error?: string | null;
  hint?: React.ReactNode;
  required?: boolean;
  className?: string;
  children: React.ReactNode;
  right?: React.ReactNode;
}) {
  return (
    <div className={cn("flex flex-col gap-1.5", className)}>
      {(label || right) && (
        <div className="flex items-center justify-between">
          {label ? (
            <Label htmlFor={htmlFor}>
              {label}
              {required ? <span className="ml-0.5 text-red">*</span> : null}
            </Label>
          ) : (
            <span />
          )}
          {right}
        </div>
      )}
      {children}
      {error ? (
        <p className="text-xs text-red" role="alert">
          {error}
        </p>
      ) : hint ? (
        <p className="text-xs text-muted">{hint}</p>
      ) : null}
    </div>
  );
}

/** Two-column responsive form grid */
export function FormGrid({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn("grid grid-cols-1 gap-4 md:grid-cols-2", className)}>{children}</div>;
}
