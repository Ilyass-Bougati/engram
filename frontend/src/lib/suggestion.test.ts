import { describe, expect, test } from "vitest";

import { suggestDeck, suggestionReason } from "@/lib/suggestion";
import type { Deck } from "@/lib/types";

function deck(name: string, due = 0, fresh = 0): Deck {
  return {
    id: name,
    name,
    description: "",
    role: "owner",
    card_count: 10,
    due_count: due,
    new_count: fresh,
    new_cards_per_day: 20,
    created_at: "",
    updated_at: "",
  };
}

describe("suggestDeck", () => {
  test("prefers the most due cards over any number of new ones", () => {
    const decks = [deck("New", 0, 50), deck("Some", 3), deck("Most", 9)];
    expect(suggestDeck(decks)?.name).toBe("Most");
  });

  test("falls back to the most new cards when nothing is due", () => {
    expect(suggestDeck([deck("Few", 0, 2), deck("Many", 0, 8)])?.name).toBe("Many");
  });

  test("breaks ties by new cards, then by name in numeric order", () => {
    expect(suggestDeck([deck("A", 4, 1), deck("B", 4, 2)])?.name).toBe("B");
    expect(suggestDeck([deck("Day 10", 4), deck("Day 2", 4)])?.name).toBe("Day 2");
  });

  test("suggests nothing when there's nothing to study", () => {
    expect(suggestDeck([deck("Done")])).toBeNull();
    expect(suggestDeck([])).toBeNull();
  });
});

test("suggestionReason says what's waiting", () => {
  expect(suggestionReason(deck("A", 12, 5))).toBe("12 cards due, plus 5 new");
  expect(suggestionReason(deck("A", 1))).toBe("1 card due");
  expect(suggestionReason(deck("A", 0, 8))).toBe("8 new cards ready");
});
