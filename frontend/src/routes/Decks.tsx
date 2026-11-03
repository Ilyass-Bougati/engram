import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDownIcon, ChevronRightIcon } from "lucide-react";
import { useState } from "react";
import { Link, useNavigate } from "react-router";

import { PageHeader } from "@/components/PageHeader";
import { EmptyState, ErrorState, FormError, LoadingRows } from "@/components/states";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { api } from "@/lib/api";
import { formText, readJsonFile } from "@/lib/form";
import { plural, studyCountsText } from "@/lib/format";
import type { Deck } from "@/lib/types";
import { useFilePicker } from "@/lib/useFilePicker";
import { AnkiImportDialog } from "@/routes/decks/AnkiImportDialog";

function NewDeckDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const create = useMutation({
    mutationFn: (body: { name: string; description: string }) =>
      api<Deck>("/decks", { method: "POST", body }),
    onSuccess: (deck) => {
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
      void navigate(`/decks/${deck.id}`);
    },
  });

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) create.reset();
        onOpenChange(next);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New deck</DialogTitle>
          <DialogDescription>
            You'll be the owner. You can share it after adding cards.
          </DialogDescription>
        </DialogHeader>
        <form
          className="grid gap-6"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            create.mutate({
              name: formText(form, "name"),
              description: formText(form, "description"),
            });
          }}
        >
          <div className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="deck-name">Name</Label>
              <Input id="deck-name" name="name" required maxLength={200} />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="deck-description">Description (optional)</Label>
              <Textarea
                id="deck-description"
                name="description"
                maxLength={2000}
                className="min-h-20 font-sans text-base"
              />
            </div>
          </div>
          <FormError error={create.error} />
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="ghost">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={create.isPending}>
              {create.isPending ? "Creating…" : "Create deck"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function DeckRow({ deck }: { deck: Deck }) {
  const hasWork = deck.due_count + deck.new_count > 0;
  return (
    <li className="relative flex items-center gap-4 px-4 py-4 hover:bg-muted sm:px-5">
      <div className="grid min-w-0 flex-1 gap-1">
        {/* The link covers the whole row; the Study button sits above it. */}
        <Link
          to={`/decks/${deck.id}`}
          className="truncate font-medium after:absolute after:inset-0 after:content-['']"
        >
          {deck.name}
        </Link>
        <p className="text-sm text-muted-foreground tabular-nums">
          {studyCountsText(deck.due_count, deck.new_count)} · {plural(deck.card_count, "card")}
          {deck.role !== "owner" && <> · shared with you as {deck.role}</>}
        </p>
      </div>
      {hasWork ? (
        <Button asChild variant="secondary" size="sm" className="relative">
          <Link to={`/decks/${deck.id}/study`} aria-label={`Study ${deck.name}`}>
            Study
          </Link>
        </Button>
      ) : (
        <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
      )}
    </li>
  );
}

export function DecksPage() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [dialog, setDialog] = useState<"new" | "anki" | null>(null);
  const decks = useQuery({ queryKey: ["decks"], queryFn: () => api<Deck[]>("/decks") });
  const importDeck = useMutation({
    mutationFn: async (file: File) =>
      api<Deck>("/decks/import", { method: "POST", body: await readJsonFile(file) }),
    onSuccess: (deck) => {
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
      void navigate(`/decks/${deck.id}`);
    },
  });
  const picker = useFilePicker((file) => {
    importDeck.mutate(file);
  });

  const actions = (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="secondary" disabled={importDeck.isPending}>
            {importDeck.isPending ? "Importing…" : "Import"}
            <ChevronDownIcon aria-hidden />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={picker.open}>Engram deck (.json)</DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() => {
              setDialog("anki");
            }}
          >
            Anki package (.apkg)
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <Button
        onClick={() => {
          setDialog("new");
        }}
      >
        New deck
      </Button>
    </>
  );

  return (
    <div className="grid gap-8">
      <title>Your decks · Engram</title>
      {picker.input}
      <PageHeader title="Your decks" actions={actions} />
      <FormError error={importDeck.error} className="-mt-4" />
      {decks.isPending ? (
        <LoadingRows label="Loading your decks" />
      ) : decks.isError ? (
        <ErrorState error={decks.error} onRetry={() => void decks.refetch()} />
      ) : decks.data.length === 0 ? (
        <EmptyState title="No decks yet">
          <p className="text-sm text-muted-foreground">
            Create a deck and add cards, or import one from Anki or a JSON deck file.
          </p>
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card">
          {decks.data.map((deck) => (
            <DeckRow key={deck.id} deck={deck} />
          ))}
        </ul>
      )}
      <NewDeckDialog
        open={dialog === "new"}
        onOpenChange={(open) => {
          setDialog(open ? "new" : null);
        }}
      />
      <AnkiImportDialog
        open={dialog === "anki"}
        onOpenChange={(open) => {
          setDialog(open ? "anki" : null);
        }}
      />
    </div>
  );
}
