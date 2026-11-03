import { describe, expect, test } from "vitest";

import { buildDeckTree, deckDisplayName, type DeckNode } from "@/lib/collections";
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

// The tree as nested names, with each collection's totals.
function outline(nodes: DeckNode[]): unknown[] {
  return nodes.map((node) =>
    node.kind === "deck"
      ? node.name
      : {
          [node.name]: outline(node.children),
          totals: [node.dueCount, node.newCount, node.cardCount, node.deckCount],
        },
  );
}

describe("buildDeckTree", () => {
  test("groups decks by their :: path and sums each collection", () => {
    const tree = buildDeckTree([
      deck("OCP Java 17::Day 10 - Streams", 1),
      deck("Organic chemistry"),
      deck("OCP Java 17::Day 2 - Operators", 0, 20),
      deck("OCP Java 17 :: Extras :: Quirks", 2),
      deck("Algebra"),
    ]);
    expect(outline(tree)).toEqual([
      "Algebra",
      {
        "OCP Java 17": [
          "Day 2 - Operators",
          "Day 10 - Streams",
          { Extras: ["Quirks"], totals: [2, 0, 10, 1] },
        ],
        totals: [3, 20, 30, 3],
      },
      "Organic chemistry",
    ]);
  });

  test("puts a deck named like a collection inside it, first", () => {
    const tree = buildDeckTree([deck("Java::Basics"), deck("Java"), deck("Java::Advanced")]);
    expect(outline(tree)).toEqual([
      { Java: ["Java", "Advanced", "Basics"], totals: [0, 0, 30, 3] },
    ]);
  });

  test("keeps decks with the same name apart and ignores empty path parts", () => {
    const tree = buildDeckTree([deck("Spanish::Verbs"), deck("Spanish::Verbs"), deck("::Odd::")]);
    expect(outline(tree)).toEqual(["Odd", { Spanish: ["Verbs", "Verbs"], totals: [0, 0, 20, 2] }]);
    expect(deckDisplayName("OCP Java 17::Day 1")).toBe("OCP Java 17 / Day 1");
  });
});
