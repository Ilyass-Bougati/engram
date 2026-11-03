import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDownIcon } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router";

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
import { buildDeckTree } from "@/lib/collections";
import { formText, readJsonFile } from "@/lib/form";
import type { Deck } from "@/lib/types";
import { useFilePicker } from "@/lib/useFilePicker";
import { AnkiImportDialog } from "@/routes/decks/AnkiImportDialog";
import { CollectionHint } from "@/routes/decks/CollectionHint";
import { DeckTree } from "@/routes/decks/DeckTree";

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
              <Input
                id="deck-name"
                name="name"
                required
                maxLength={200}
                aria-describedby="deck-name-hint"
              />
              <CollectionHint id="deck-name-hint" />
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
        <DeckTree nodes={buildDeckTree(decks.data)} />
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
