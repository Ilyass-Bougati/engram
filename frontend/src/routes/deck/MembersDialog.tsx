import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useNavigate } from "react-router";

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
import { formText } from "@/lib/form";
import type { Deck, Member } from "@/lib/types";

type SharedRole = "editor" | "viewer";

const ROLE_OPTIONS: { value: SharedRole; label: string }[] = [
  { value: "viewer", label: "Viewer: can study" },
  { value: "editor", label: "Editor: can study and edit cards" },
];

function isSharedRole(value: string): value is SharedRole {
  return value === "editor" || value === "viewer";
}

function MemberRow({ deck, member }: { deck: Deck; member: Member }) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const me = useCurrentUser();
  const isMe = member.user_id === me.id;
  const membersKey = ["members", deck.id];
  const changeRole = useMutation({
    mutationFn: (role: SharedRole) =>
      api<Member>(`/decks/${deck.id}/members/${member.user_id}`, {
        method: "PATCH",
        body: { role },
      }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: membersKey }),
  });
  const remove = useMutation({
    mutationFn: () => api(`/decks/${deck.id}/members/${member.user_id}`, { method: "DELETE" }),
    onSuccess: () => {
      if (isMe) {
        void queryClient.invalidateQueries({ queryKey: ["decks"] });
        void navigate("/");
      } else {
        void queryClient.invalidateQueries({ queryKey: membersKey });
      }
    },
  });

  const name = (
    <span className="min-w-0 flex-1 truncate font-medium">
      {member.username}
      {isMe && <span className="font-normal text-muted-foreground"> (you)</span>}
    </span>
  );

  if (member.role === "owner") {
    return (
      <li className="flex items-center gap-3 py-3">
        {name}
        <span className="text-sm text-muted-foreground">Owner</span>
      </li>
    );
  }

  return (
    <li className="grid gap-2 py-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        {name}
        {deck.role === "owner" ? (
          <>
            <Select
              aria-label={`Role for ${member.username}`}
              className="w-32"
              value={member.role}
              disabled={changeRole.isPending}
              onChange={(event) => {
                if (isSharedRole(event.target.value)) changeRole.mutate(event.target.value);
              }}
            >
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
              aria-label={`Remove ${member.username}`}
            >
              Remove
            </Button>
          </>
        ) : (
          <>
            <span className="text-sm text-muted-foreground capitalize">{member.role}</span>
            {isMe && (
              <Button
                variant="ghost"
                size="sm"
                disabled={remove.isPending}
                onClick={() => {
                  remove.mutate();
                }}
              >
                Leave deck
              </Button>
            )}
          </>
        )}
      </div>
      <FormError error={changeRole.error ?? remove.error} />
    </li>
  );
}

function ShareForm({ deck }: { deck: Deck }) {
  const queryClient = useQueryClient();
  const [role, setRole] = useState<SharedRole>("viewer");
  const share = useMutation({
    mutationFn: (body: { username: string; role: SharedRole }) =>
      api<Member>(`/decks/${deck.id}/members`, { method: "POST", body }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["members", deck.id] }),
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
        <Label htmlFor="share-username">Username</Label>
        <Input id="share-username" name="username" autoComplete="off" required />
      </div>
      <div className="grid gap-2">
        <Label htmlFor="share-role">Role</Label>
        <Select
          id="share-role"
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
        {share.isPending ? "Sharing…" : "Share"}
      </Button>
    </form>
  );
}

export function MembersDialog({
  deck,
  open,
  onOpenChange,
}: {
  deck: Deck;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const isOwner = deck.role === "owner";
  const members = useQuery({
    queryKey: ["members", deck.id],
    queryFn: () => api<Member[]>(`/decks/${deck.id}/members`),
    enabled: open,
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isOwner ? "Share deck" : "Members"}</DialogTitle>
          <DialogDescription>
            {isOwner
              ? "They'll see every card in this deck. Their review progress stays their own."
              : "Everyone with access to this deck. Only the owner can change who has access."}
          </DialogDescription>
        </DialogHeader>
        {isOwner && <ShareForm deck={deck} />}
        <section className="grid gap-1" aria-labelledby="members-heading">
          <h3 id="members-heading" className="text-sm font-medium text-muted-foreground">
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
                <MemberRow key={member.user_id} deck={deck} member={member} />
              ))}
            </ul>
          )}
        </section>
      </DialogContent>
    </Dialog>
  );
}
