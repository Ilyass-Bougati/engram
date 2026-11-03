import type { ComponentProps } from "react";

import { cn } from "@/lib/cn";

export function Input({ className, ...props }: ComponentProps<"input">) {
  return (
    <input
      className={cn(
        "h-10 w-full min-w-0 rounded-sm border border-input bg-card px-3 text-base text-foreground placeholder:text-muted-foreground disabled:opacity-50 aria-invalid:border-destructive",
        // File inputs: the browser's button styled as a quiet control, centered in the field.
        "[&[type=file]]:py-[5px] [&[type=file]]:pl-[5px] file:mr-3 file:h-7 file:rounded-[4px] file:border-0 file:bg-muted file:px-3 file:text-sm file:font-medium file:text-foreground",
        className,
      )}
      {...props}
    />
  );
}
