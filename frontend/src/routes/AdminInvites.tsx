import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BanIcon,
  CalendarXIcon,
  CheckIcon,
  CircleCheckIcon,
  ClockIcon,
  CopyIcon,
  LinkIcon,
  type LucideIcon,
} from "lucide-react";
import { useState } from "react";

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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api } from "@/lib/api";
import { cn } from "@/lib/cn";
import { formatDate, formatDateTime } from "@/lib/format";
import type { CreatedInvite, InviteState, InviteSummary } from "@/lib/types";
import { AdminNav } from "@/routes/AdminNav";

const STATE_LABELS: Record<InviteState, string> = {
  pending: "Waiting to be used",
  used: "Used",
  expired: "Expired",
  revoked: "Revoked",
};

const STATE_ICONS: Record<InviteState, LucideIcon> = {
  pending: ClockIcon,
  used: CircleCheckIcon,
  expired: CalendarXIcon,
  revoked: BanIcon,
};

function NewInviteDialog({ token, onClose }: { token: string | null; onClose: () => void }) {
  const [copied, setCopied] = useState(false);
  const link = token ? `${window.location.origin}/invite/${token}` : "";
  return (
    <Dialog
      open={token !== null}
      onOpenChange={(open) => {
        if (!open) {
          setCopied(false);
          onClose();
        }
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invite link created</DialogTitle>
          <DialogDescription>
            Send it to the person you're inviting. It works for one sign-up and expires in 7 days.
            This is the only time it's shown.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-2">
          <Label htmlFor="invite-link">Invite link</Label>
          <Input
            id="invite-link"
            readOnly
            value={link}
            className="font-mono text-sm"
            onFocus={(event) => {
              event.currentTarget.select();
            }}
          />
          {copied && (
            <p role="status" className="text-sm text-muted-foreground">
              Copied to the clipboard.
            </p>
          )}
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="ghost">Done</Button>
          </DialogClose>
          <Button
            onClick={() => {
              void navigator.clipboard.writeText(link).then(() => {
                setCopied(true);
              });
            }}
          >
            {copied ? <CheckIcon aria-hidden /> : <CopyIcon aria-hidden />}
            Copy link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function InviteRow({ invite }: { invite: InviteSummary }) {
  const queryClient = useQueryClient();
  const revoke = useMutation({
    mutationFn: () => api(`/admin/invites/${invite.id}`, { method: "DELETE" }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["admin", "invites"] }),
  });
  let detail: string;
  if (invite.state === "used" && invite.used_by && invite.used_at) {
    detail = `${invite.used_by} signed up ${formatDateTime(invite.used_at)}`;
  } else if (invite.state === "pending") {
    detail = `Expires ${formatDateTime(invite.expires_at)}`;
  } else if (invite.state === "expired") {
    detail = `Expired ${formatDate(invite.expires_at)}`;
  } else {
    detail = "Can no longer be used";
  }

  const StateIcon = STATE_ICONS[invite.state];
  return (
    <li className="grid gap-2 px-4 py-4 sm:px-5">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <div className="grid min-w-0 flex-1 gap-1">
          <p
            className={cn(
              "flex items-center gap-2 font-medium",
              invite.state !== "pending" && "text-muted-foreground",
            )}
          >
            <StateIcon
              className={cn("size-4 shrink-0", invite.state === "pending" && "text-primary")}
              aria-hidden
            />
            {STATE_LABELS[invite.state]}
          </p>
          <p className="text-sm text-muted-foreground">
            {detail} · created by {invite.created_by} on {formatDate(invite.created_at)}
          </p>
        </div>
        {invite.state === "pending" && (
          <Button
            variant="ghost"
            size="sm"
            disabled={revoke.isPending}
            onClick={() => {
              revoke.mutate();
            }}
          >
            <BanIcon aria-hidden />
            {revoke.isPending ? "Revoking…" : "Revoke"}
          </Button>
        )}
      </div>
      <FormError error={revoke.error} />
    </li>
  );
}

export function AdminInvitesPage() {
  const queryClient = useQueryClient();
  const [newToken, setNewToken] = useState<string | null>(null);
  const invites = useQuery({
    queryKey: ["admin", "invites"],
    queryFn: () => api<InviteSummary[]>("/admin/invites"),
  });
  const create = useMutation({
    mutationFn: () => api<CreatedInvite>("/admin/invites", { method: "POST" }),
    onSuccess: (created) => {
      setNewToken(created.token);
      void queryClient.invalidateQueries({ queryKey: ["admin", "invites"] });
    },
  });

  return (
    <div className="grid gap-8">
      <title>Invites · Admin · Engram</title>
      <PageHeader
        title="Admin"
        actions={
          <Button
            disabled={create.isPending}
            onClick={() => {
              create.mutate();
            }}
          >
            <LinkIcon aria-hidden />
            {create.isPending ? "Creating…" : "Create invite link"}
          </Button>
        }
      />
      <AdminNav />
      <FormError error={create.error} />
      {invites.isPending ? (
        <LoadingRows label="Loading invites" />
      ) : invites.isError ? (
        <ErrorState error={invites.error} onRetry={() => void invites.refetch()} />
      ) : invites.data.length === 0 ? (
        <EmptyState title="No invites yet" icon={LinkIcon}>
          <p className="text-sm text-muted-foreground">
            Create an invite link and send it to someone. It's the only way to sign up.
          </p>
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card">
          {invites.data.map((invite) => (
            <InviteRow key={invite.id} invite={invite} />
          ))}
        </ul>
      )}
      <NewInviteDialog
        token={newToken}
        onClose={() => {
          setNewToken(null);
        }}
      />
    </div>
  );
}
