import { useQuery, type QueryClient } from "@tanstack/react-query";

import { api, ApiError } from "@/lib/api";
import type { Deck } from "@/lib/types";

export function useDeck(deckId: string) {
  return useQuery({ queryKey: ["deck", deckId], queryFn: () => api<Deck>(`/decks/${deckId}`) });
}

// Decks the user can't see are 404 by design; a malformed ID in the URL is a 422.
export function isNotFound(error: unknown): boolean {
  return error instanceof ApiError && (error.status === 404 || error.status === 422);
}

// After anything that changes a deck's cards or the user's progress in it.
export function invalidateDeck(queryClient: QueryClient, deckId: string): void {
  for (const queryKey of [["decks"], ["deck", deckId], ["cards", deckId], ["tags", deckId]]) {
    void queryClient.invalidateQueries({ queryKey });
  }
}
