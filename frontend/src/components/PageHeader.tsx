import type { ReactNode } from "react";

export function PageHeader({
  title,
  eyebrow,
  description,
  actions,
}: {
  title: string;
  // Small text above the title, such as the collection a deck is in.
  eyebrow?: string | undefined;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
      <div className="grid min-w-0 gap-2">
        {eyebrow ? (
          <hgroup className="grid gap-1">
            <p className="text-sm font-medium text-muted-foreground">{eyebrow}</p>
            <h1 className="text-2xl font-semibold break-words sm:text-3xl">{title}</h1>
          </hgroup>
        ) : (
          <h1 className="text-2xl font-semibold break-words sm:text-3xl">{title}</h1>
        )}
        {description}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  );
}
