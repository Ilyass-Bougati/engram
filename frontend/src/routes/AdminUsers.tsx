import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CircleUserIcon,
  ShieldCheckIcon,
  ShieldOffIcon,
  UserCheckIcon,
  UserXIcon,
} from "lucide-react";

import { PageHeader } from "@/components/PageHeader";
import { ErrorState, FormError, LoadingRows } from "@/components/states";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";
import { useCurrentUser } from "@/lib/auth";
import { cn } from "@/lib/cn";
import { formatDate } from "@/lib/format";
import type { AdminUser } from "@/lib/types";
import { AdminNav } from "@/routes/AdminNav";

function UserRow({ account }: { account: AdminUser }) {
  const queryClient = useQueryClient();
  const me = useCurrentUser();
  const isMe = account.id === me.id;
  const update = useMutation({
    mutationFn: (body: Partial<Pick<AdminUser, "role" | "is_active">>) =>
      api<AdminUser>(`/admin/users/${account.id}`, { method: "PATCH", body }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
  const isAdmin = account.role === "admin";

  return (
    <li className="grid gap-2 px-4 py-4 sm:px-5">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <div className="grid min-w-0 flex-1 gap-1">
          <p
            className={cn(
              "flex min-w-0 items-center gap-2 font-medium",
              !account.is_active && "text-muted-foreground",
            )}
          >
            {isAdmin ? (
              <ShieldCheckIcon className="size-4 shrink-0 text-primary" aria-hidden />
            ) : (
              <CircleUserIcon className="size-4 shrink-0 text-muted-foreground" aria-hidden />
            )}
            <span className="truncate">{account.username}</span>
            {isMe && <span className="font-normal text-muted-foreground"> (you)</span>}
          </p>
          <p className="text-sm text-muted-foreground">
            {isAdmin ? "Admin" : "User"}
            {!account.is_active && " · deactivated, can't sign in"} · joined{" "}
            {formatDate(account.created_at)}
          </p>
        </div>
        {isMe ? (
          <p className="text-sm text-muted-foreground">Another admin can change your account.</p>
        ) : (
          <div className="-ml-3 flex flex-wrap gap-2 sm:ml-0">
            <Button
              variant="ghost"
              size="sm"
              disabled={update.isPending}
              onClick={() => {
                update.mutate({ role: isAdmin ? "user" : "admin" });
              }}
            >
              {isAdmin ? <ShieldOffIcon aria-hidden /> : <ShieldCheckIcon aria-hidden />}
              {isAdmin ? "Remove admin" : "Make admin"}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              className={cn(account.is_active && "text-destructive")}
              disabled={update.isPending}
              onClick={() => {
                update.mutate({ is_active: !account.is_active });
              }}
            >
              {account.is_active ? <UserXIcon aria-hidden /> : <UserCheckIcon aria-hidden />}
              {account.is_active ? "Deactivate" : "Reactivate"}
            </Button>
          </div>
        )}
      </div>
      <FormError error={update.error} />
    </li>
  );
}

export function AdminUsersPage() {
  const users = useQuery({
    queryKey: ["admin", "users"],
    queryFn: () => api<AdminUser[]>("/admin/users"),
  });
  return (
    <div className="grid gap-8">
      <title>Users · Admin · Engram</title>
      <PageHeader title="Admin" />
      <AdminNav />
      <p className="-mt-4 text-sm text-muted-foreground">
        Deactivating someone signs them out everywhere and blocks sign-in. Their decks and progress
        stay. Reset a forgotten password with the set-password admin command.
      </p>
      {users.isPending ? (
        <LoadingRows label="Loading users" />
      ) : users.isError ? (
        <ErrorState error={users.error} onRetry={() => void users.refetch()} />
      ) : (
        <ul className="divide-y divide-border overflow-hidden rounded-md border border-border bg-card">
          {users.data.map((account) => (
            <UserRow key={account.id} account={account} />
          ))}
        </ul>
      )}
    </div>
  );
}
