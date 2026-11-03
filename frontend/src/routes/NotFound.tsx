import { ArrowLeftIcon } from "lucide-react";
import { Link } from "react-router";

import { CenteredPage } from "@/components/CenteredPage";
import { Button } from "@/components/ui/button";

export function NotFound() {
  return (
    <CenteredPage>
      <title>Page not found · Engram</title>
      <div className="grid gap-2">
        <h1 className="text-2xl font-semibold">Page not found</h1>
        <p className="text-muted-foreground">
          There's nothing at this address. Check the link, or go back to your decks.
        </p>
      </div>
      <Button asChild className="self-start">
        <Link to="/">
          <ArrowLeftIcon aria-hidden />
          Go to your decks
        </Link>
      </Button>
    </CenteredPage>
  );
}
