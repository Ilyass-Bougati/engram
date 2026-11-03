import type { ReactNode } from "react";

// Sign-in, invite and full-page errors: one narrow column, centered in the window.
export function CenteredPage({ children }: { children: ReactNode }) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-8 px-4 py-12">
      {children}
    </main>
  );
}
