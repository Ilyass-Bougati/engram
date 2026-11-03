import {
  keepPreviousData,
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { EllipsisIcon, SearchIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router";

import { DeckNotFound } from "@/components/DeckNotFound";
import { Markdown } from "@/components/markdown/Markdown";
import { PageHeader } from "@/components/PageHeader";
import { EmptyState, ErrorState, FormError, LoadingRows } from "@/components/states";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { api } from "@/lib/api";
import { downloadFromApi } from "@/lib/download";
import { readJsonFile } from "@/lib/form";
import { firstLine, plural, studyCountsText } from "@/lib/format";
import { invalidateDeck, isNotFound, useDeck } from "@/lib/queries";
import type { Card, CardPage, Deck, TagCount } from "@/lib/types";
import { useDebounced } from "@/lib/useDebounced";
import { useFilePicker } from "@/lib/useFilePicker";
import { DeckSettingsDialog } from "@/routes/deck/DeckSettingsDialog";
import { MembersDialog } from "@/routes/deck/MembersDialog";

function cardsPath(deckId: string, q: string, tag: string, cursor: string | null): string {
  const params = new URLSearchParams();
  if (q) params.set("q", q);
  if (tag) params.set("tag", tag);
  if (cursor) params.set("cursor", cursor);
  const query = params.toString();
  return `/decks/${deckId}/cards${query ? `?${query}` : ""}`;
}

function CardRow({ deckId, card }: { deckId: string; card: Card }) {
  const prompt = card.type === "basic" ? card.front : card.question;
  const kind =
    card.type === "basic"
      ? "Front and back"
      : `Multiple choice · ${plural(card.options.length, "option")}`;
  return (
    <li>
      <Link
        to={`/decks/${deckId}/cards/${card.id}`}
        className="grid gap-1 px-4 py-3 hover:bg-muted sm:px-5"
      >
        <Markdown line className="font-medium">
          {firstLine(prompt)}
        </Markdown>
        <span className="truncate text-sm text-muted-foreground">
          {kind}
          {card.tags.length > 0 && <> · {card.tags.join(", ")}</>}
        </span>
      </Link>
    </li>
  );
}

function CardList({ deck }: { deck: Deck }) {
  const [params, setParams] = useSearchParams();
  const tag = params.get("tag") ?? "";
  const [search, setSearch] = useState(params.get("q") ?? "");
  const q = useDebounced(search.trim(), 250);
  const canEdit = deck.role !== "viewer";

  // Kept in the URL so coming back from a card restores the same list.
  useEffect(() => {
    setParams(
      (current) => {
        const next = new URLSearchParams(current);
        if (q) next.set("q", q);
        else next.delete("q");
        return next;
      },
      { replace: true },
    );
  }, [q, setParams]);

  const tags = useQuery({
    queryKey: ["tags", deck.id],
    queryFn: () => api<TagCount[]>(`/decks/${deck.id}/tags`),
  });
  const cards = useInfiniteQuery({
    queryKey: ["cards", deck.id, { q, tag }],
    queryFn: ({ pageParam }) => api<CardPage>(cardsPath(deck.id, q, tag, pageParam)),
    initialPageParam: null as string | null,
    getNextPageParam: (page) => page.next_cursor,
    placeholderData: keepPreviousData,
  });

  const filtered = q !== "" || tag !== "";
  const allCards = cards.data?.pages.flatMap((page) => page.cards) ?? [];

  return (
    <section className="grid gap-4" aria-labelledby="cards-heading">
      <h2 id="cards-heading" className="sr-only">
        Cards
      </h2>
      {(deck.card_count > 0 || filtered) && (
        <div className="flex flex-col gap-2 sm:flex-row">
          <div className="relative flex-1">
            <SearchIcon
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
              aria-hidden
            />
            <Input
              type="search"
              aria-label="Search cards"
              placeholder="Search cards"
              className="pl-9"
              value={search}
              onChange={(event) => {
                setSearch(event.target.value);
              }}
            />
          </div>
          <Select
            aria-label="Filter by tag"
            className="sm:w-56"
            value={tag}
            onChange={(event) => {
              const value = event.target.value;
              setParams(
                (current) => {
                  const next = new URLSearchParams(current);
                  if (value) next.set("tag", value);
                  else next.delete("tag");
                  return next;
                },
                { replace: true },
              );
            }}
          >
            <option value="">All tags</option>
            {tags.data?.map((entry) => (
              <option key={entry.tag} value={entry.tag}>
                {entry.tag} ({entry.card_count})
              </option>
            ))}
          </Select>
        </div>
      )}
      {cards.isPending ? (
        <LoadingRows label="Loading cards" />
      ) : cards.isError ? (
        <ErrorState error={cards.error} onRetry={() => void cards.refetch()} />
      ) : allCards.length === 0 && filtered ? (
        <EmptyState title="No cards match">
          <p className="text-sm text-muted-foreground">
            Nothing in this deck matches {q ? `"${q}"` : "that"}
            {tag ? ` with the tag ${tag}` : ""}.
          </p>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => {
              setSearch("");
              setParams({}, { replace: true });
            }}
          >
            Clear search
          </Button>
        </EmptyState>
      ) : allCards.length === 0 ? (
        <EmptyState title="No cards yet">
          <p className="text-sm text-muted-foreground">
            {canEdit
              ? "Add one, or import a JSON deck from the menu."
              : "The owner hasn't added any cards. Check back later."}
          </p>
          {canEdit && (
            <Button asChild size="sm">
              <Link to={`/decks/${deck.id}/cards/new`}>Add card</Link>
            </Button>
          )}
        </EmptyState>
      ) : (
        <>
          <ul
            className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card"
            aria-busy={cards.isFetching}
          >
            {allCards.map((card) => (
              <CardRow key={card.id} deckId={deck.id} card={card} />
            ))}
          </ul>
          {cards.hasNextPage && (
            <Button
              variant="secondary"
              className="justify-self-center"
              disabled={cards.isFetchingNextPage}
              onClick={() => void cards.fetchNextPage()}
            >
              {cards.isFetchingNextPage ? "Loading…" : "Show more cards"}
            </Button>
          )}
        </>
      )}
    </section>
  );
}

export function DeckPage() {
  const { deckId = "" } = useParams();
  const deck = useDeck(deckId);
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [dialog, setDialog] = useState<"members" | "settings" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const importCards = useMutation({
    mutationFn: async (file: File) =>
      api<{ imported: number }>(`/decks/${deckId}/import`, {
        method: "POST",
        body: await readJsonFile(file),
      }),
    onSuccess: (result) => {
      setNotice(`Imported ${plural(result.imported, "card")}.`);
      invalidateDeck(queryClient, deckId);
    },
  });
  const fork = useMutation({
    mutationFn: () => api<Deck>(`/decks/${deckId}/fork`, { method: "POST" }),
    onSuccess: (copy) => {
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
      void navigate(`/decks/${copy.id}`);
    },
  });
  const exportDeck = useMutation({
    mutationFn: () => downloadFromApi(`/decks/${deckId}/export`, "deck.engram.json"),
  });
  const picker = useFilePicker((file) => {
    setNotice(null);
    importCards.mutate(file);
  });

  if (deck.isPending) return <LoadingRows rows={4} label="Loading deck" />;
  if (deck.isError) {
    return isNotFound(deck.error) ? (
      <DeckNotFound />
    ) : (
      <ErrorState error={deck.error} onRetry={() => void deck.refetch()} />
    );
  }

  const { role } = deck.data;
  const canEdit = role !== "viewer";
  const actionError = importCards.error ?? fork.error ?? exportDeck.error;

  return (
    <div className="grid gap-8">
      <title>{`${deck.data.name} · Engram`}</title>
      {picker.input}
      <PageHeader
        title={deck.data.name}
        description={
          <>
            {deck.data.description && (
              <p className="max-w-prose whitespace-pre-line text-muted-foreground">
                {deck.data.description}
              </p>
            )}
            <p className="text-sm text-muted-foreground tabular-nums">
              {studyCountsText(deck.data.due_count, deck.data.new_count)} ·{" "}
              {plural(deck.data.card_count, "card")}
              {role !== "owner" && <> · shared with you as {role}</>}
            </p>
          </>
        }
        actions={
          <>
            <Button asChild>
              <Link to={`/decks/${deckId}/study`}>Study</Link>
            </Button>
            {canEdit && (
              <Button asChild variant="secondary">
                <Link to={`/decks/${deckId}/cards/new`}>Add card</Link>
              </Button>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="secondary" size="icon" aria-label="More deck actions">
                  <EllipsisIcon aria-hidden />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {canEdit && (
                  <DropdownMenuItem disabled={importCards.isPending} onSelect={picker.open}>
                    Import cards from JSON
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem
                  disabled={exportDeck.isPending}
                  onSelect={() => {
                    exportDeck.mutate();
                  }}
                >
                  Export as JSON
                </DropdownMenuItem>
                <DropdownMenuItem
                  disabled={fork.isPending}
                  onSelect={() => {
                    fork.mutate();
                  }}
                >
                  Fork a copy for yourself
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onSelect={() => {
                    setDialog("members");
                  }}
                >
                  {role === "owner" ? "Share deck" : "Members"}
                </DropdownMenuItem>
                <DropdownMenuItem
                  onSelect={() => {
                    setDialog("settings");
                  }}
                >
                  Deck settings
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </>
        }
      />
      {(notice ?? actionError ?? importCards.isPending) && (
        <div className="-mt-4">
          {importCards.isPending && (
            <p role="status" className="text-sm text-muted-foreground">
              Importing cards…
            </p>
          )}
          {notice && (
            <p role="status" className="text-sm text-muted-foreground">
              {notice}
            </p>
          )}
          <FormError error={actionError} />
        </div>
      )}
      <CardList deck={deck.data} />
      <MembersDialog
        deck={deck.data}
        open={dialog === "members"}
        onOpenChange={(open) => {
          setDialog(open ? "members" : null);
        }}
      />
      <DeckSettingsDialog
        deck={deck.data}
        open={dialog === "settings"}
        onOpenChange={(open) => {
          setDialog(open ? "settings" : null);
        }}
      />
    </div>
  );
}
