import { Link } from "react-router";

import { Button } from "@/components/ui/button";

export function NotFound() {
  return (
    <div className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-6 px-4">
      <div className="grid gap-2">
        <h1 className="text-2xl font-semibold">Page not found</h1>
        <p className="text-muted-foreground">
          There's nothing at this address. Check the link, or go back to your decks.
        </p>
      </div>
      <Button asChild className="self-start">
        <Link to="/">Go to your decks</Link>
      </Button>
    </div>
  );
}
