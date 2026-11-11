import {
  ChevronDownIcon,
  ChevronRightIcon,
  EllipsisIcon,
  FolderIcon,
  FolderOpenIcon,
  GalleryVerticalEndIcon,
  PlayIcon,
  SettingsIcon,
  UserPlusIcon,
  UsersIcon,
} from "lucide-react";
import { type CSSProperties, useState } from "react";
import { Link } from "react-router";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/cn";
import {
  type Collection,
  collectionDecks,
  collectionStudyUrl,
  type DeckLeaf,
  type DeckNode,
  deckDisplayName,
} from "@/lib/collections";
import { plural, studyCountsText } from "@/lib/format";
import { CollectionSettingsDialog } from "@/routes/decks/CollectionSettingsDialog";
import { CollectionShareDialog } from "@/routes/decks/CollectionShareDialog";

type DialogKind = "share" | "settings";
type OpenDialog = (kind: DialogKind, collection: Collection) => void;

function findCollection(nodes: DeckNode[], key: string): Collection | undefined {
  for (const node of nodes) {
    if (node.kind !== "collection") continue;
    if (node.key === key) return node;
    const found = findCollection(node.children, key);
    if (found) return found;
  }
  return undefined;
}

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

// Nested rows line their icon up with the name of the collection above: icons are 1rem wide
// with a 0.75rem gap.
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
        "relative flex items-center gap-3 py-4 pe-4 transition-colors duration-(--duration-fast) hover:bg-muted sm:pe-5",
        rowIndent.className,
      )}
      style={rowIndent.style}
    >
      <GalleryVerticalEndIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
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
            <PlayIcon aria-hidden />
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
  onDialog,
}: {
  node: Collection;
  depth: number;
  open: Set<string>;
  onToggle: (key: string) => void;
  onDialog: OpenDialog;
}) {
  const isOpen = open.has(node.key);
  const listId = `collection-${encodeURIComponent(node.key)}`;
  const rowIndent = indent(depth);
  const displayName = deckDisplayName(node.key);
  const ownsDecks = collectionDecks(node).some((deck) => deck.role === "owner");
  return (
    <li>
      <div
        className={cn(
          "relative flex items-center gap-3 py-4 pe-4 transition-colors duration-(--duration-fast) hover:bg-muted sm:pe-5",
          rowIndent.className,
        )}
        style={rowIndent.style}
      >
        {isOpen ? (
          <FolderOpenIcon className="size-4 shrink-0 text-primary" aria-hidden />
        ) : (
          <FolderIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
        )}
        {/* The toggle covers the whole row; Study and the menu sit above it. */}
        <button
          type="button"
          aria-expanded={isOpen}
          aria-controls={listId}
          onClick={() => {
            onToggle(node.key);
          }}
          className="grid min-w-0 flex-1 gap-1 text-left after:absolute after:inset-0 after:content-['']"
        >
          <span className="truncate font-medium">{node.name}</span>
          <span className="text-sm text-muted-foreground tabular-nums">
            {studyCountsText(node.dueCount, node.newCount)} · {plural(node.deckCount, "deck")} ·{" "}
            {plural(node.cardCount, "card")}
          </span>
        </button>
        {node.dueCount + node.newCount > 0 && (
          <Button asChild variant="secondary" size="sm" className="relative">
            <Link to={collectionStudyUrl(node.key)} aria-label={`Study ${displayName}`}>
              <PlayIcon aria-hidden />
              Study
            </Link>
          </Button>
        )}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="relative"
              aria-label={`More actions for ${displayName}`}
            >
              <EllipsisIcon aria-hidden />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              onSelect={() => {
                onDialog("share", node);
              }}
            >
              {ownsDecks ? (
                <>
                  <UserPlusIcon aria-hidden />
                  Share collection
                </>
              ) : (
                <>
                  <UsersIcon aria-hidden />
                  Members
                </>
              )}
            </DropdownMenuItem>
            <DropdownMenuItem
              onSelect={() => {
                onDialog("settings", node);
              }}
            >
              <SettingsIcon aria-hidden />
              Collection settings
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <ChevronDownIcon
          className={cn(
            "size-4 shrink-0 text-muted-foreground transition-transform duration-(--duration-base) ease-standard",
            isOpen && "rotate-180",
          )}
          aria-hidden
        />
      </div>
      {/* Slides open by animating the row height from 0 to the content's. Closed decks stay
          in the page, inert, so they can't be focused or read out while hidden. */}
      <div
        className={cn(
          "grid overflow-hidden transition-[grid-template-rows] duration-(--duration-base) ease-standard",
          isOpen ? "grid-rows-[1fr]" : "grid-rows-[0fr]",
        )}
        inert={!isOpen}
      >
        <ul id={listId} className="min-h-0 divide-y divide-border border-t border-border">
          <DeckNodes
            nodes={node.children}
            depth={depth + 1}
            open={open}
            onToggle={onToggle}
            onDialog={onDialog}
          />
        </ul>
      </div>
    </li>
  );
}

function DeckNodes({
  nodes,
  depth,
  open,
  onToggle,
  onDialog,
}: {
  nodes: DeckNode[];
  depth: number;
  open: Set<string>;
  onToggle: (key: string) => void;
  onDialog: OpenDialog;
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
        onDialog={onDialog}
      />
    ),
  );
}

export function DeckTree({ nodes }: { nodes: DeckNode[] }) {
  const [open, toggle] = useOpenCollections();
  // The dialog stays mounted after closing so it can animate out. It looks its collection up
  // by key on every render, so counts stay current and a renamed collection closes it.
  const [dialog, setDialog] = useState<{ kind: DialogKind; key: string; open: boolean } | null>(
    null,
  );
  const collection = dialog && findCollection(nodes, dialog.key);
  const onOpenChange = (isOpen: boolean) => {
    if (dialog) setDialog({ ...dialog, open: isOpen });
  };
  return (
    <>
      <ul className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card">
        <DeckNodes
          nodes={nodes}
          depth={0}
          open={open}
          onToggle={toggle}
          onDialog={(kind, node) => {
            setDialog({ kind, key: node.key, open: true });
          }}
        />
      </ul>
      {collection && dialog.kind === "share" && (
        <CollectionShareDialog
          key={collection.key}
          collection={collection}
          open={dialog.open}
          onOpenChange={onOpenChange}
        />
      )}
      {collection && dialog.kind === "settings" && (
        <CollectionSettingsDialog
          key={collection.key}
          collection={collection}
          open={dialog.open}
          onOpenChange={onOpenChange}
        />
      )}
    </>
  );
}
