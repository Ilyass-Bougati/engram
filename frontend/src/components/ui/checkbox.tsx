import type { ComponentProps } from "react";

import { cn } from "@/lib/cn";

export function Checkbox({ className, type = "checkbox", ...props }: ComponentProps<"input">) {
  return (
    <input
      type={type}
      className={cn("size-4 shrink-0 accent-primary disabled:opacity-50", className)}
      {...props}
    />
  );
}
