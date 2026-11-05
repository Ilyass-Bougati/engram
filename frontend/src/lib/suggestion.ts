import { collator } from "@/lib/collections";
import { plural } from "@/lib/format";
import type { Deck } from "@/lib/types";

// What to study next: due cards first, since reviews slip if they're left, then new cards.
// One deck, not a collection, because studying happens one deck at a time.
export function suggestDeck(decks: Deck[]): Deck | null {
  const ready = decks.filter((deck) => deck.due_count + deck.new_count > 0);
  ready.sort(
    (a, b) =>
      b.due_count - a.due_count || b.new_count - a.new_count || collator.compare(a.name, b.name),
  );
  return ready[0] ?? null;
}

export function suggestionReason({ due_count: due, new_count: fresh }: Deck): string {
  if (due === 0) return `${plural(fresh, "new card")} ready`;
  const dueText = `${plural(due, "card")} due`;
  return fresh === 0 ? dueText : `${dueText}, plus ${String(fresh)} new`;
}
