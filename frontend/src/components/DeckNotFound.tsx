import { Link } from "react-router";

import { Button } from "@/components/ui/button";

export function DeckNotFound() {
  return (
    <div className="grid justify-items-start gap-4" role="alert">
      <title>Deck not found · Engram</title>
      <h1 className="text-2xl font-semibold">Deck not found</h1>
      <p className="text-muted-foreground">
        It doesn't exist, it was deleted, or you no longer have access. Ask the owner to share it
        again if you need it.
      </p>
      <Button asChild variant="secondary">
        <Link to="/">Back to your decks</Link>
      </Button>
    </div>
  );
}
