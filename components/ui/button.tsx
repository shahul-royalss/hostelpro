import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-control text-sm font-medium transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30 focus-visible:ring-offset-2 focus-visible:ring-offset-ivory disabled:pointer-events-none disabled:opacity-50 active:scale-[0.98] [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        /** Solid navy — primary action */
        default: "bg-navy text-white shadow-sm hover:bg-navy/90",
        /** Frosted glass with navy text — secondary */
        secondary: "bg-white/60 text-navy border border-white/70 backdrop-blur-md shadow-glass hover:bg-white/80",
        /** Ghost — tertiary / "Back" */
        ghost: "text-navy hover:bg-navy/5",
        /** Outline — sage/red variants for approve/reject */
        outline: "border border-line bg-transparent text-navy hover:bg-white/50",
        "outline-sage": "border border-sage text-sage bg-transparent hover:bg-sage-soft",
        "outline-red": "border border-red text-red bg-transparent hover:bg-red-soft",
        destructive: "bg-red text-white shadow-sm hover:bg-red/90",
        teal: "bg-teal text-white shadow-sm hover:bg-teal/90",
        link: "text-navy underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-8 rounded-[10px] px-3 text-xs",
        lg: "h-12 rounded-control px-6 text-[15px]",
        xl: "h-12 w-full rounded-control px-6 text-[15px]",
        icon: "h-10 w-10",
        "icon-sm": "h-8 w-8 rounded-[10px]",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  loading?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, loading = false, children, disabled, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        disabled={disabled || loading}
        {...props}
      >
        {asChild ? (
          children
        ) : (
          <>
            {loading && <Loader2 className="animate-spin" />}
            {children}
          </>
        )}
      </Comp>
    );
  },
);
Button.displayName = "Button";

export { Button, buttonVariants };
