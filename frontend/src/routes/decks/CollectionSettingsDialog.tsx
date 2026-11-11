import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Trash2Icon } from "lucide-react";
import { useState } from "react";

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
import { api } from "@/lib/api";
import {
  type Collection,
  collectionApi,
  collectionDecks,
  deckDisplayName,
  deckPath,
} from "@/lib/collections";
import { formText } from "@/lib/form";
import { plural } from "@/lib/format";
import type { CollectionChange, CollectionView, Deck } from "@/lib/types";

function invalidateDecks(queryClient: ReturnType<typeof useQueryClient>): void {
  for (const queryKey of [["decks"], ["deck"], ["collection"]]) {
    void queryClient.invalidateQueries({ queryKey });
  }
}

function DeleteCollection({
  collection,
  owned,
  onCancel,
  onDeleted,
}: {
  collection: Collection;
  owned: Deck[];
  onCancel: () => void;
  onDeleted: () => void;
}) {
  const queryClient = useQueryClient();
  const remove = useMutation({
    mutationFn: () => api<CollectionChange>(collectionApi(collection.key), { method: "DELETE" }),
    onSuccess: () => {
      invalidateDecks(queryClient);
      onDeleted();
    },
  });
  const cardCount = owned.reduce((total, deck) => total + deck.card_count, 0);
  const shared = collection.deckCount - owned.length;
  return (
    <>
      <DialogHeader>
        <DialogTitle>
          Delete {plural(owned.length, "deck")} in "{deckDisplayName(collection.key)}"?
        </DialogTitle>
        <DialogDescription>
          This deletes {plural(owned.length, "deck")} you own, with {plural(cardCount, "card")} and
          everyone's review history for them. Members lose access right away. It can't be undone.
          {shared > 0 && ` The ${plural(shared, "deck")} shared with you stay.`}
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
          <Trash2Icon aria-hidden />
          {remove.isPending ? "Deleting…" : `Delete ${plural(owned.length, "deck")}`}
        </Button>
      </DialogFooter>
    </>
  );
}

function SettingsForm({
  collection,
  owned,
  onDelete,
  onRenamed,
}: {
  collection: Collection;
  owned: Deck[];
  onDelete: () => void;
  onRenamed: () => void;
}) {
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState(false);
  const decks = collectionDecks(collection);
  const limits = new Set(decks.map((deck) => deck.new_cards_per_day));
  const [sharedLimit] = limits.size === 1 ? [...limits] : [];
  const shared = decks.length - owned.length;
  const save = useMutation({
    mutationFn: async (form: FormData) => {
      const limit = formText(form, "limit");
      if (limit !== "" && Number(limit) !== sharedLimit) {
        await api<CollectionView>(collectionApi(collection.key, "/me"), {
          method: "PUT",
          body: { new_cards_per_day: Number(limit) },
        });
      }
      const name = formText(form, "name").trim();
      if (owned.length > 0 && deckPath(name).join("::") !== collection.key) {
        await api<CollectionChange>(collectionApi(collection.key), {
          method: "PATCH",
          body: { name },
        });
        return "renamed";
      }
      return "saved";
    },
    onSuccess: (outcome) => {
      invalidateDecks(queryClient);
      // The collection now lives under its new name; this dialog's path is gone.
      if (outcome === "renamed") onRenamed();
      else setSaved(true);
    },
  });

  return (
    <>
      <DialogHeader>
        <DialogTitle>Collection settings</DialogTitle>
        <DialogDescription>
          Changes apply to every deck in "{deckDisplayName(collection.key)}" (
          {plural(decks.length, "deck")}).
          {owned.length === 0 && " Only the decks' owners can rename them."}
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
          {owned.length > 0 && (
            <div className="grid gap-2">
              <Label htmlFor="collection-name">Name</Label>
              <Input
                id="collection-name"
                name="name"
                defaultValue={collection.key}
                required
                maxLength={200}
                aria-describedby="collection-name-hint"
              />
              <p id="collection-name-hint" className="text-sm text-muted-foreground">
                Renames the {plural(owned.length, "deck")} you own here. Use{" "}
                <code className="font-mono">::</code> to move the collection into another, as in{" "}
                <code className="font-mono">Archive::{collection.name}</code>.
                {shared > 0 &&
                  ` The ${plural(shared, "deck")} shared with you keep their names and stay where they are.`}
              </p>
            </div>
          )}
          <div className="grid gap-2">
            <Label htmlFor="collection-limit">New cards per day, for each deck</Label>
            <Input
              id="collection-limit"
              name="limit"
              type="number"
              inputMode="numeric"
              min={0}
              max={9999}
              required={sharedLimit !== undefined}
              defaultValue={sharedLimit}
              placeholder={sharedLimit === undefined ? "Mixed" : undefined}
              className="w-32 tabular-nums"
              aria-describedby="collection-limit-hint"
            />
            <p id="collection-limit-hint" className="text-sm text-muted-foreground">
              {sharedLimit === undefined
                ? `Your decks here have different limits, from ${String(Math.min(...limits))} to ${String(Math.max(...limits))}. A number here sets them all; leave it empty to keep them.`
                : "Sets your own limit on every deck here. Each deck counts separately."}
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
      {owned.length > 0 && (
        <section
          className="grid gap-3 border-t border-border pt-6"
          aria-labelledby="delete-collection-heading"
        >
          <h3 id="delete-collection-heading" className="font-medium">
            Delete collection
          </h3>
          <p className="text-sm text-muted-foreground">
            Removes the {plural(owned.length, "deck")} you own here for every member, with all their
            cards and review history.
          </p>
          <Button variant="danger" className="justify-self-start" onClick={onDelete}>
            <Trash2Icon aria-hidden />
            Delete collection…
          </Button>
        </section>
      )}
    </>
  );
}

export function CollectionSettingsDialog({
  collection,
  open,
  onOpenChange,
}: {
  collection: Collection;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const owned = collectionDecks(collection).filter((deck) => deck.role === "owner");
  const close = () => {
    onOpenChange(false);
  };
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
          <DeleteCollection
            collection={collection}
            owned={owned}
            onCancel={() => {
              setConfirmingDelete(false);
            }}
            onDeleted={close}
          />
        ) : (
          <SettingsForm
            collection={collection}
            owned={owned}
            onDelete={() => {
              setConfirmingDelete(true);
            }}
            onRenamed={close}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
