import { ChevronRightIcon } from "lucide-react";
import { type CSSProperties, useState } from "react";
import { Link } from "react-router";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";
import { type Collection, type DeckLeaf, type DeckNode, deckDisplayName } from "@/lib/collections";
import { plural, studyCountsText } from "@/lib/format";

const STORAGE_KEY = "engram-open-collections";

function storedOpenCollections(): Set<string> {
  // Storage can throw in private windows or with site data blocked; start all closed.
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]");
    return new Set(Array.isArray(stored) ? stored.filter((key) => typeof key === "string") : []);
  } catch {
    return new Set();
  }
}

function useOpenCollections(): [Set<string>, (key: string) => void] {
  const [open, setOpen] = useState(storedOpenCollections);
  const toggle = (key: string) => {
    const next = new Set(open);
    if (!next.delete(key)) next.add(key);
    setOpen(next);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify([...next]));
    } catch {
      // Not remembered after a reload; the collection still opens now.
    }
  };
  return [open, toggle];
}

// Nested rows line their text up with the name of the collection above: the chevron is 1rem
// wide with a 0.75rem gap.
function indent(depth: number): { className: string; style: CSSProperties } {
  return {
    className: "ps-[calc(1rem+var(--depth)*1.75rem)] sm:ps-[calc(1.25rem+var(--depth)*1.75rem)]",
    style: { "--depth": depth } as CSSProperties,
  };
}

function DeckRow({ node, depth }: { node: DeckLeaf; depth: number }) {
  const { deck } = node;
  const hasWork = deck.due_count + deck.new_count > 0;
  const rowIndent = indent(depth);
  return (
    <li
      className={cn(
        "relative flex items-center gap-4 py-4 pe-4 hover:bg-muted sm:pe-5",
        rowIndent.className,
      )}
      style={rowIndent.style}
    >
      <div className="grid min-w-0 flex-1 gap-1">
        {/* The link covers the whole row; the Study button sits above it. */}
        <Link
          to={`/decks/${deck.id}`}
          className="truncate font-medium after:absolute after:inset-0 after:content-['']"
        >
          {node.name}
        </Link>
        <p className="text-sm text-muted-foreground tabular-nums">
          {studyCountsText(deck.due_count, deck.new_count)} · {plural(deck.card_count, "card")}
          {deck.role !== "owner" && <> · shared with you as {deck.role}</>}
        </p>
      </div>
      {hasWork ? (
        <Button asChild variant="secondary" size="sm" className="relative">
          <Link to={`/decks/${deck.id}/study`} aria-label={`Study ${deckDisplayName(deck.name)}`}>
            Study
          </Link>
        </Button>
      ) : (
        <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
      )}
    </li>
  );
}

function CollectionRow({
  node,
  depth,
  open,
  onToggle,
}: {
  node: Collection;
  depth: number;
  open: Set<string>;
  onToggle: (key: string) => void;
}) {
  const isOpen = open.has(node.key);
  const listId = `collection-${encodeURIComponent(node.key)}`;
  const rowIndent = indent(depth);
  return (
    <li>
      <button
        type="button"
        aria-expanded={isOpen}
        aria-controls={listId}
        onClick={() => {
          onToggle(node.key);
        }}
        className={cn(
          "flex w-full items-center gap-3 py-4 pe-4 text-left hover:bg-muted sm:pe-5",
          rowIndent.className,
        )}
        style={rowIndent.style}
      >
        <ChevronRightIcon
          className={cn(
            "size-4 shrink-0 text-muted-foreground transition-transform duration-(--duration-fast) ease-standard",
            isOpen && "rotate-90",
          )}
          aria-hidden
        />
        <span className="grid min-w-0 flex-1 gap-1">
          <span className="truncate font-medium">{node.name}</span>
          <span className="text-sm text-muted-foreground tabular-nums">
            {studyCountsText(node.dueCount, node.newCount)} · {plural(node.deckCount, "deck")} ·{" "}
            {plural(node.cardCount, "card")}
          </span>
        </span>
      </button>
      {isOpen && (
        <ul id={listId} className="divide-y divide-border border-t border-border">
          <DeckNodes nodes={node.children} depth={depth + 1} open={open} onToggle={onToggle} />
        </ul>
      )}
    </li>
  );
}

function DeckNodes({
  nodes,
  depth,
  open,
  onToggle,
}: {
  nodes: DeckNode[];
  depth: number;
  open: Set<string>;
  onToggle: (key: string) => void;
}) {
  return nodes.map((node) =>
    node.kind === "deck" ? (
      <DeckRow key={node.deck.id} node={node} depth={depth} />
    ) : (
      <CollectionRow
        key={`collection:${node.key}`}
        node={node}
        depth={depth}
        open={open}
        onToggle={onToggle}
      />
    ),
  );
}

export function DeckTree({ nodes }: { nodes: DeckNode[] }) {
  const [open, toggle] = useOpenCollections();
  return (
    <ul className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card">
      <DeckNodes nodes={nodes} depth={0} open={open} onToggle={toggle} />
    </ul>
  );
}
