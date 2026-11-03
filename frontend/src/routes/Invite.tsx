import { useMutation, useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { Link, Navigate, useParams } from "react-router";

import { CenteredPage } from "@/components/CenteredPage";
import { FormError } from "@/components/states";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, ApiError, UserFacingError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formText } from "@/lib/form";
import type { SessionResponse } from "@/lib/types";

function browserTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}

export function InvitePage() {
  const { token = "" } = useParams();
  const { state, startSession } = useAuth();
  const [mismatch, setMismatch] = useState(false);
  const invite = useQuery({
    queryKey: ["invite", token],
    queryFn: () => api<{ expires_at: string }>(`/invites/${encodeURIComponent(token)}`),
    enabled: state.status !== "signedIn",
  });
  const redeem = useMutation({
    mutationFn: (body: { username: string; password: string; timezone: string }) =>
      api<SessionResponse>(`/invites/${encodeURIComponent(token)}/redeem`, {
        method: "POST",
        body,
      }),
    onSuccess: startSession,
  });

  if (state.status === "signedIn") return <Navigate to="/" replace />;

  if (invite.isPending) {
    return (
      <CenteredPage>
        <title>Create your account · Engram</title>
        <p role="status" className="text-muted-foreground">
          Checking your invite link…
        </p>
      </CenteredPage>
    );
  }

  if (invite.isError) {
    const expired = invite.error instanceof ApiError && invite.error.status === 404;
    return (
      <CenteredPage>
        <title>Invite link not valid · Engram</title>
        <div className="grid gap-2" role="alert">
          <h1 className="text-2xl font-semibold">
            {expired ? "This invite link is no longer valid" : "The invite couldn't be checked"}
          </h1>
          <p className="text-muted-foreground">
            {expired
              ? "It may have been used already, revoked, or it expired after 7 days. Ask your admin for a new link."
              : invite.error.message}
          </p>
        </div>
        {expired ? (
          <Button asChild variant="secondary" className="self-start">
            <Link to="/login">Go to sign in</Link>
          </Button>
        ) : (
          <Button className="self-start" onClick={() => void invite.refetch()}>
            Try again
          </Button>
        )}
      </CenteredPage>
    );
  }

  const timezone = browserTimezone();
  const formError = mismatch
    ? new UserFacingError("The passwords don't match. Type the same password in both fields.")
    : redeem.error;

  return (
    <CenteredPage>
      <title>Create your account · Engram</title>
      <div className="grid gap-2">
        <h1 className="text-2xl font-semibold">Create your account</h1>
        <p className="text-muted-foreground">
          You've been invited to Engram. Pick a username and password.
        </p>
      </div>
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault();
          const form = new FormData(event.currentTarget);
          const password = formText(form, "password");
          const passwordsMatch = password === formText(form, "confirm");
          setMismatch(!passwordsMatch);
          if (!passwordsMatch) return;
          redeem.mutate({ username: formText(form, "username"), password, timezone });
        }}
      >
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="username">Username</Label>
            <Input
              id="username"
              name="username"
              autoComplete="username"
              required
              minLength={3}
              maxLength={32}
              pattern="[A-Za-z0-9_.\-]+"
              aria-describedby="username-hint"
              autoFocus
            />
            <p id="username-hint" className="text-sm text-muted-foreground">
              3 to 32 characters: letters, numbers, dots, dashes and underscores.
            </p>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              required
              minLength={10}
              maxLength={256}
              aria-describedby="password-hint"
            />
            <p id="password-hint" className="text-sm text-muted-foreground">
              At least 10 characters.
            </p>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="confirm">Confirm password</Label>
            <Input
              id="confirm"
              name="confirm"
              type="password"
              autoComplete="new-password"
              required
              aria-invalid={mismatch || undefined}
            />
          </div>
        </div>
        <p className="text-sm text-muted-foreground">
          Your day starts at 4:00 in {timezone}. You can change the timezone later in settings.
        </p>
        <FormError error={formError} />
        <Button type="submit" disabled={redeem.isPending}>
          {redeem.isPending ? "Creating account…" : "Create account"}
        </Button>
      </form>
    </CenteredPage>
  );
}
