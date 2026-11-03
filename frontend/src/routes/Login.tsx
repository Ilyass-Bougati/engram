import { useMutation } from "@tanstack/react-query";
import { Navigate, useSearchParams } from "react-router";

import { CenteredPage } from "@/components/CenteredPage";
import { FormError } from "@/components/states";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { formText } from "@/lib/form";
import type { SessionResponse } from "@/lib/types";

// Only same-site paths: "//evil.example" or "/\\evil.example" would leave the app.
function safeNext(next: string | null): string {
  return next?.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";
}

export function LoginPage() {
  const { state, startSession } = useAuth();
  const [params] = useSearchParams();
  const next = safeNext(params.get("next"));
  const login = useMutation({
    mutationFn: (credentials: { username: string; password: string }) =>
      api<SessionResponse>("/auth/login", { method: "POST", body: credentials }),
    onSuccess: startSession,
  });

  if (state.status === "signedIn") return <Navigate to={next} replace />;

  return (
    <CenteredPage>
      <title>Sign in · Engram</title>
      <h1 className="text-2xl font-semibold">Sign in to Engram</h1>
      <form
        className="grid gap-6"
        onSubmit={(event) => {
          event.preventDefault();
          const form = new FormData(event.currentTarget);
          login.mutate({
            username: formText(form, "username"),
            password: formText(form, "password"),
          });
        }}
      >
        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="username">Username</Label>
            <Input id="username" name="username" autoComplete="username" required autoFocus />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              required
            />
          </div>
        </div>
        <FormError error={login.error} />
        <Button type="submit" disabled={login.isPending}>
          {login.isPending ? "Signing in…" : "Sign in"}
        </Button>
      </form>
      <p className="text-sm text-muted-foreground">
        Accounts are by invite only. If you need one, or forgot your password, ask your admin.
      </p>
    </CenteredPage>
  );
}
