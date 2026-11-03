import { ChevronDownIcon } from "lucide-react";
import type { ComponentProps } from "react";

import { cn } from "@/lib/cn";

// The native element: it gets the platform's own picker on phones and full keyboard support.
export function Select({ className, ...props }: ComponentProps<"select">) {
  return (
    <span className={cn("relative grid", className)}>
      <select
        className="h-10 w-full min-w-0 appearance-none rounded-sm border border-input bg-card pr-9 pl-3 text-base text-foreground disabled:opacity-50"
        {...props}
      />
      <ChevronDownIcon
        className="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-muted-foreground"
        aria-hidden
      />
    </span>
  );
}
