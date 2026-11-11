import type { Deck } from "@/lib/types";

// Collections come from deck names, as in Anki: "Java::Day 1" is the deck "Day 1" in the
// collection "Java". There is nothing to create or delete; renaming a deck moves it.
const SEPARATOR = "::";

export function deckPath(name: string): string[] {
  const path = name
    .split(SEPARATOR)
    .map((part) => part.trim())
    .filter(Boolean);
  return path.length > 0 ? path : [name];
}

// The API path for a collection-wide route: collectionApi("Java", "/study/next").
export function collectionApi(key: string, route = ""): string {
  return `/collections${route}?path=${encodeURIComponent(key)}`;
}

export function collectionStudyUrl(key: string): string {
  return `/collections/study?path=${encodeURIComponent(key)}`;
}

// For places that show one deck on its own: "Java / Day 1".
export function deckDisplayName(name: string): string {
  return deckPath(name).join(" / ");
}

export interface DeckLeaf {
  kind: "deck";
  name: string;
  deck: Deck;
}

export interface Collection {
  kind: "collection";
  name: string;
  // The full path, joined: stable across renames of other decks, so it keys the open state.
  key: string;
  children: DeckNode[];
  dueCount: number;
  newCount: number;
  cardCount: number;
  deckCount: number;
}

export type DeckNode = DeckLeaf | Collection;

// Every deck in a collection, its subcollections' included.
export function collectionDecks(collection: Collection): Deck[] {
  return collection.children.flatMap((node) =>
    node.kind === "deck" ? [node.deck] : collectionDecks(node),
  );
}

export const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

function newCollection(name: string, key: string): Collection {
  return {
    kind: "collection",
    name,
    key,
    children: [],
    dueCount: 0,
    newCount: 0,
    cardCount: 0,
    deckCount: 0,
  };
}

export function buildDeckTree(decks: Deck[]): DeckNode[] {
  const root = newCollection("", "");
  const collections = new Map<string, Collection>([["", root]]);
  const collectionAt = (path: string[]): Collection => {
    let parent = root;
    for (let depth = 1; depth <= path.length; depth++) {
      const key = path.slice(0, depth).join(SEPARATOR);
      let collection = collections.get(key);
      if (!collection) {
        collection = newCollection(path[depth - 1] ?? "", key);
        collections.set(key, collection);
        parent.children.push(collection);
      }
      parent = collection;
    }
    return parent;
  };

  const paths = decks.map((deck) => deckPath(deck.name));
  for (const path of paths) collectionAt(path.slice(0, -1));
  decks.forEach((deck, index) => {
    const path = paths[index] ?? [deck.name];
    // A deck named like a collection ("Java" next to "Java::Day 1") goes inside it.
    const homePath = collections.has(path.join(SEPARATOR)) ? path : path.slice(0, -1);
    collectionAt(homePath).children.push({ kind: "deck", name: path.at(-1) ?? deck.name, deck });
    for (let depth = homePath.length; depth > 0; depth--) {
      const collection = collectionAt(homePath.slice(0, depth));
      collection.dueCount += deck.due_count;
      collection.newCount += deck.new_count;
      collection.cardCount += deck.card_count;
      collection.deckCount += 1;
    }
  });

  const sort = (nodes: DeckNode[], parent: string): void => {
    nodes.sort((a, b) => {
      // A collection's own deck comes first, then everything by name, numbers in order.
      const aOwn = a.kind === "deck" && a.name === parent;
      const bOwn = b.kind === "deck" && b.name === parent;
      if (aOwn !== bOwn) return aOwn ? -1 : 1;
      return collator.compare(a.name, b.name);
    });
    for (const node of nodes) if (node.kind === "collection") sort(node.children, node.name);
  };
  sort(root.children, "");
  return root.children;
}
