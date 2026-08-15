import * as React from "react";
import { cn } from "@/lib/utils";

const Textarea = React.forwardRef<HTMLTextAreaElement, React.ComponentProps<"textarea">>(
  ({ className, ...props }, ref) => {
    return (
      <textarea
        className={cn(
          "flex min-h-[88px] w-full rounded-control border border-input bg-white/70 px-3.5 py-2.5 text-sm text-charcoal transition-colors",
          "placeholder:text-muted/60 focus-visible:outline-none focus-visible:border-navy focus-visible:ring-1 focus-visible:ring-navy",
          "disabled:cursor-not-allowed disabled:opacity-50 aria-[invalid=true]:border-red",
          className,
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Textarea.displayName = "Textarea";

export { Textarea };
