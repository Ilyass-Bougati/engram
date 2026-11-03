import type { ReactNode } from "react";

import { EngramMark } from "@/components/EngramMark";

// Sign-in, invite and full-page errors: one narrow column, centered in the window.
export function CenteredPage({ children }: { children: ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm animate-rise-in flex-col justify-center gap-8 px-4 py-12">
      <EngramMark className="size-10" />
      {children}
    </main>
  );
}
