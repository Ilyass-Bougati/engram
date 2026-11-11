import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { LogOutIcon, UserMinusIcon, UserPlusIcon } from "lucide-react";
import { useState } from "react";

import { ErrorState, FormError } from "@/components/states";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { api } from "@/lib/api";
import { useCurrentUser } from "@/lib/auth";
import {
  type Collection,
  collectionApi,
  collectionDecks,
  deckDisplayName,
} from "@/lib/collections";
import { formText } from "@/lib/form";
import { plural } from "@/lib/format";
import type { CollectionChange, CollectionMember, DeckRole } from "@/lib/types";

type SharedRole = "editor" | "viewer";

const ROLE_OPTIONS: { value: SharedRole; label: string }[] = [
  { value: "viewer", label: "Viewer: can study" },
  { value: "editor", label: "Editor: can study and edit cards" },
];

function isSharedRole(value: string): value is SharedRole {
  return value === "editor" || value === "viewer";
}

const ROLE_PHRASES: Record<DeckRole, string> = {
  owner: "owner of",
  editor: "editor on",
  viewer: "viewer on",
};

// "Owner of 2 decks, viewer on 1 deck"
function rolesText(roles: CollectionMember["roles"]): string {
  const text = (["owner", "editor", "viewer"] as const)
    .filter((role) => roles[role])
    .map((role) => `${ROLE_PHRASES[role]} ${plural(roles[role] ?? 0, "deck")}`)
    .join(", ");
  return text.charAt(0).toUpperCase() + text.slice(1);
}

// The one role someone has on every deck they share here, if there is one.
function sharedRole(roles: CollectionMember["roles"]): SharedRole | "" {
  const held = Object.keys(roles);
  const [only] = held;
  return held.length === 1 && only !== undefined && isSharedRole(only) ? only : "";
}

function changeText(change: CollectionChange, done: string): string {
  const skipped =
    change.skipped > 0
      ? ` ${plural(change.skipped, "deck")} you don't own stayed as they were.`
      : "";
  return `${done} ${plural(change.changed, "deck")}.${skipped}`;
}

function MemberRow({
  collection,
  member,
  ownsDecks,
  onLeft,
  onChanged,
}: {
  collection: Collection;
  member: CollectionMember;
  ownsDecks: boolean;
  onLeft: () => void;
  onChanged: (message: string) => void;
}) {
  const queryClient = useQueryClient();
  const me = useCurrentUser();
  const isMe = member.user_id === me.id;
  const membersKey = ["collection-members", collection.key];
  const changeRole = useMutation({
    mutationFn: (role: SharedRole) =>
      api<CollectionChange>(collectionApi(collection.key, "/members"), {
        method: "POST",
        body: { username: member.username, role },
      }),
    onSuccess: (change) => {
      onChanged(changeText(change, `${member.username}'s role changed on`));
      void queryClient.invalidateQueries({ queryKey: membersKey });
    },
  });
  const remove = useMutation({
    mutationFn: () =>
      api<CollectionChange>(collectionApi(collection.key, `/members/${member.user_id}`), {
        method: "DELETE",
      }),
    onSuccess: (change) => {
      if (isMe) {
        for (const queryKey of [["decks"], ["deck"], ["collection"]]) {
          void queryClient.invalidateQueries({ queryKey });
        }
        onLeft();
      } else {
        onChanged(changeText(change, `${member.username} was removed from`));
        void queryClient.invalidateQueries({ queryKey: membersKey });
      }
    },
  });
  const leavable = (member.roles.editor ?? 0) + (member.roles.viewer ?? 0);

  return (
    <li className="grid gap-2 py-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <span className="grid min-w-0 flex-1 gap-0.5">
          <span className="truncate font-medium">
            {member.username}
            {isMe && <span className="font-normal text-muted-foreground"> (you)</span>}
          </span>
          <span className="text-sm text-muted-foreground">{rolesText(member.roles)}</span>
        </span>
        {isMe
          ? leavable > 0 && (
              <Button
                variant="ghost"
                size="sm"
                disabled={remove.isPending}
                onClick={() => {
                  remove.mutate();
                }}
              >
                <LogOutIcon aria-hidden />
                Leave {plural(leavable, "shared deck")}
              </Button>
            )
          : ownsDecks && (
              <>
                <Select
                  aria-label={`Role for ${member.username} on your decks`}
                  className="w-32"
                  value={sharedRole(member.roles)}
                  disabled={changeRole.isPending}
                  onChange={(event) => {
                    if (isSharedRole(event.target.value)) changeRole.mutate(event.target.value);
                  }}
                >
                  <option value="" disabled hidden>
                    Mixed
                  </option>
                  <option value="viewer">Viewer</option>
                  <option value="editor">Editor</option>
                </Select>
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={remove.isPending}
                  onClick={() => {
                    remove.mutate();
                  }}
                  aria-label={`Remove ${member.username} from your decks`}
                >
                  <UserMinusIcon aria-hidden />
                  Remove
                </Button>
              </>
            )}
      </div>
      <FormError error={changeRole.error ?? remove.error} />
    </li>
  );
}

function ShareForm({
  collection,
  onShared,
}: {
  collection: Collection;
  onShared: (message: string) => void;
}) {
  const queryClient = useQueryClient();
  const [role, setRole] = useState<SharedRole>("viewer");
  const share = useMutation({
    mutationFn: (body: { username: string; role: SharedRole }) =>
      api<CollectionChange>(collectionApi(collection.key, "/members"), { method: "POST", body }),
    onSuccess: (change, body) => {
      onShared(changeText(change, `Shared with ${body.username}:`));
      void queryClient.invalidateQueries({ queryKey: ["collection-members", collection.key] });
    },
  });

  return (
    <form
      className="grid gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        const form = event.currentTarget;
        share.mutate(
          { username: formText(new FormData(form), "username").trim(), role },
          {
            onSuccess: () => {
              form.reset();
            },
          },
        );
      }}
    >
      <div className="grid gap-2">
        <Label htmlFor="collection-share-username">Username</Label>
        <Input id="collection-share-username" name="username" autoComplete="off" required />
      </div>
      <div className="grid gap-2">
        <Label htmlFor="collection-share-role">Role</Label>
        <Select
          id="collection-share-role"
          value={role}
          onChange={(event) => {
            if (isSharedRole(event.target.value)) setRole(event.target.value);
          }}
        >
          {ROLE_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
      </div>
      <FormError error={share.error} />
      <Button type="submit" className="justify-self-end" disabled={share.isPending}>
        <UserPlusIcon aria-hidden />
        {share.isPending ? "Sharing…" : "Share"}
      </Button>
    </form>
  );
}

export function CollectionShareDialog({
  collection,
  open,
  onOpenChange,
}: {
  collection: Collection;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [notice, setNotice] = useState<string | null>(null);
  const decks = collectionDecks(collection);
  const owned = decks.filter((deck) => deck.role === "owner").length;
  const members = useQuery({
    queryKey: ["collection-members", collection.key],
    queryFn: () => api<CollectionMember[]>(collectionApi(collection.key, "/members")),
    enabled: open,
  });

  let description: string;
  if (owned === 0) {
    description =
      "Everyone with access to a deck here. Only each deck's owner can change who has access.";
  } else if (owned < decks.length) {
    description = `Sharing covers the ${plural(owned, "deck")} you own here; the ${plural(decks.length - owned, "deck")} shared with you aren't yours to share. Decks added later need sharing again.`;
  } else {
    description = `They'll see every card in all ${plural(owned, "deck")}. Decks added to the collection later aren't shared until you share again. Review progress stays each person's own.`;
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setNotice(null);
        onOpenChange(next);
      }}
    >
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {owned > 0 ? "Share" : "Members of"} "{deckDisplayName(collection.key)}"
          </DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {owned > 0 && <ShareForm collection={collection} onShared={setNotice} />}
        {notice && (
          <p role="status" className="text-sm text-muted-foreground">
            {notice}
          </p>
        )}
        <section className="grid gap-1" aria-labelledby="collection-members-heading">
          <h3 id="collection-members-heading" className="text-sm font-medium text-muted-foreground">
            People with access
          </h3>
          {members.isPending ? (
            <p role="status" className="py-3 text-sm text-muted-foreground">
              Loading members…
            </p>
          ) : members.isError ? (
            <ErrorState error={members.error} onRetry={() => void members.refetch()} />
          ) : (
            <ul className="divide-y divide-border">
              {members.data.map((member) => (
                <MemberRow
                  key={member.user_id}
                  collection={collection}
                  member={member}
                  ownsDecks={owned > 0}
                  onLeft={() => {
                    onOpenChange(false);
                  }}
                  onChanged={setNotice}
                />
              ))}
            </ul>
          )}
        </section>
      </DialogContent>
    </Dialog>
  );
}
