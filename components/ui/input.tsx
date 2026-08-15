import * as React from "react";
import { cn } from "@/lib/utils";

const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          "flex h-10 w-full rounded-control border border-input bg-white/70 px-3.5 py-2 text-sm text-charcoal shadow-none transition-colors",
          "placeholder:text-muted/60 file:border-0 file:bg-transparent file:text-sm file:font-medium",
          "focus-visible:outline-none focus-visible:border-navy focus-visible:ring-1 focus-visible:ring-navy",
          "disabled:cursor-not-allowed disabled:opacity-50",
          "aria-[invalid=true]:border-red aria-[invalid=true]:ring-red/30",
          className,
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Input.displayName = "Input";

export { Input };
