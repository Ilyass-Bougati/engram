import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { errorMessage } from "@/lib/api";
import { cn } from "@/lib/cn";

// Static blocks in the shape of the content that's coming. No shimmer: nothing here changes
// state until the content replaces it.
export function LoadingRows({ rows = 3, label }: { rows?: number; label: string }) {
  return (
    <div role="status" aria-label={label} className="grid gap-3">
      {Array.from({ length: rows }, (_, index) => (
        <div key={index} className="grid gap-2 rounded-md border border-border bg-card px-4 py-4">
          <div className="h-4 w-2/5 rounded-sm bg-muted" />
          <div className="h-3 w-1/4 rounded-sm bg-muted" />
        </div>
      ))}
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  return (
    <div
      role="alert"
      className="grid justify-items-start gap-3 rounded-md border border-border bg-card p-6"
    >
      <p className="font-medium">This didn't load.</p>
      <p className="text-sm text-muted-foreground">{errorMessage(error)}</p>
      <Button variant="secondary" size="sm" onClick={onRetry}>
        Try again
      </Button>
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="grid justify-items-start gap-3 rounded-md border border-dashed border-input px-6 py-10">
      <p className="font-medium">{title}</p>
      {children}
    </div>
  );
}

export function FormError({ error, className }: { error: unknown; className?: string }) {
  if (error === null || error === undefined) return null;
  return (
    <p role="alert" className={cn("text-sm text-destructive", className)}>
      {errorMessage(error)}
    </p>
  );
}
