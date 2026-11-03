import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useNavigate } from "react-router";

import { FormError } from "@/components/states";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { api } from "@/lib/api";
import { deckDisplayName } from "@/lib/collections";
import { formText } from "@/lib/form";
import { plural } from "@/lib/format";
import { invalidateDeck } from "@/lib/queries";
import type { Deck } from "@/lib/types";
import { CollectionHint } from "@/routes/decks/CollectionHint";

function DeleteDeck({ deck, onCancel }: { deck: Deck; onCancel: () => void }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const remove = useMutation({
    mutationFn: () => api(`/decks/${deck.id}`, { method: "DELETE" }),
    onSuccess: () => {
      queryClient.removeQueries({ queryKey: ["deck", deck.id] });
      void queryClient.invalidateQueries({ queryKey: ["decks"] });
      void navigate("/");
    },
  });
  return (
    <>
      <DialogHeader>
        <DialogTitle>Delete "{deckDisplayName(deck.name)}"?</DialogTitle>
        <DialogDescription>
          This deletes {plural(deck.card_count, "card")} and everyone's review history for them.
          Members lose access right away. It can't be undone.
        </DialogDescription>
      </DialogHeader>
      <FormError error={remove.error} />
      <DialogFooter>
        <Button variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
        <Button
          variant="danger"
          disabled={remove.isPending}
          onClick={() => {
            remove.mutate();
          }}
        >
          {remove.isPending ? "Deleting…" : "Delete deck"}
        </Button>
      </DialogFooter>
    </>
  );
}

function SettingsForm({ deck, onDelete }: { deck: Deck; onDelete: () => void }) {
  const queryClient = useQueryClient();
  const isOwner = deck.role === "owner";
  const [saved, setSaved] = useState(false);
  const save = useMutation({
    mutationFn: async (form: FormData) => {
      const limit = Number(formText(form, "limit"));
      if (limit !== deck.new_cards_per_day) {
        await api<Deck>(`/decks/${deck.id}/me`, {
          method: "PUT",
          body: { new_cards_per_day: limit },
        });
      }
      if (isOwner) {
        await api<Deck>(`/decks/${deck.id}`, {
          method: "PATCH",
          body: { name: formText(form, "name"), description: formText(form, "description") },
        });
      }
    },
    onSuccess: () => {
      setSaved(true);
      invalidateDeck(queryClient, deck.id);
    },
  });

  return (
    <>
      <DialogHeader>
        <DialogTitle>Deck settings</DialogTitle>
        <DialogDescription>
          {isOwner
            ? "The daily limit is yours alone; the name and description are shown to every member."
            : "The daily limit is yours alone. Only the owner can rename the deck."}
        </DialogDescription>
      </DialogHeader>
      <form
        className="grid gap-6"
        onChange={() => {
          setSaved(false);
        }}
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate(new FormData(event.currentTarget));
        }}
      >
        <div className="grid gap-4">
          {isOwner && (
            <>
              <div className="grid gap-2">
                <Label htmlFor="settings-name">Name</Label>
                <Input
                  id="settings-name"
                  name="name"
                  defaultValue={deck.name}
                  required
                  maxLength={200}
                  aria-describedby="settings-name-hint"
                />
                <CollectionHint id="settings-name-hint" />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="settings-description">Description</Label>
                <Textarea
                  id="settings-description"
                  name="description"
                  defaultValue={deck.description}
                  maxLength={2000}
                  className="min-h-20 font-sans text-base"
                />
              </div>
            </>
          )}
          <div className="grid gap-2">
            <Label htmlFor="settings-limit">New cards per day</Label>
            <Input
              id="settings-limit"
              name="limit"
              type="number"
              inputMode="numeric"
              min={0}
              max={9999}
              required
              defaultValue={deck.new_cards_per_day}
              className="w-32 tabular-nums"
              aria-describedby="settings-limit-hint"
            />
            <p id="settings-limit-hint" className="text-sm text-muted-foreground">
              How many cards you see for the first time each day. Reviews of cards you've already
              started are never limited.
            </p>
          </div>
        </div>
        <FormError error={save.error} />
        {saved && (
          <p role="status" className="text-sm text-muted-foreground">
            Saved.
          </p>
        )}
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="ghost">Close</Button>
          </DialogClose>
          <Button type="submit" disabled={save.isPending}>
            {save.isPending ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </form>
      {isOwner && (
        <section
          className="grid gap-3 border-t border-border pt-6"
          aria-labelledby="delete-heading"
        >
          <h3 id="delete-heading" className="font-medium">
            Delete deck
          </h3>
          <p className="text-sm text-muted-foreground">
            Removes the deck for every member, with all cards and review history.
          </p>
          <Button variant="danger" className="justify-self-start" onClick={onDelete}>
            Delete deck…
          </Button>
        </section>
      )}
    </>
  );
}

export function DeckSettingsDialog({
  deck,
  open,
  onOpenChange,
}: {
  deck: Deck;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setConfirmingDelete(false);
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
        {confirmingDelete ? (
          <DeleteDeck
            deck={deck}
            onCancel={() => {
              setConfirmingDelete(false);
            }}
          />
        ) : (
          <SettingsForm
            deck={deck}
            onDelete={() => {
              setConfirmingDelete(true);
            }}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
