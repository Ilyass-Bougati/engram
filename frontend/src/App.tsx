import { createBrowserRouter, Navigate, Outlet, useLocation } from "react-router";

import { AppShell } from "@/components/AppShell";
import { CenteredPage } from "@/components/CenteredPage";
import { Button } from "@/components/ui/button";
import { useAuth, useCurrentUser } from "@/lib/auth";
import { AdminInvitesPage } from "@/routes/AdminInvites";
import { AdminUsersPage } from "@/routes/AdminUsers";
import { DecksPage } from "@/routes/Decks";
import { InvitePage } from "@/routes/Invite";
import { LoginPage } from "@/routes/Login";
import { NotFound } from "@/routes/NotFound";
import { RouteError } from "@/routes/RouteError";
import { SettingsPage } from "@/routes/Settings";

// Shown while the refresh cookie is exchanged for a session; usually a few milliseconds.
function RestoringSession() {
  return (
    <div role="status" className="sr-only">
      Loading
    </div>
  );
}

function ServerUnavailable({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <CenteredPage>
      <div className="grid gap-2" role="alert">
        <h1 className="text-2xl font-semibold">Engram isn't responding</h1>
        <p className="text-muted-foreground">{message}</p>
      </div>
      <Button className="self-start" onClick={onRetry}>
        Try again
      </Button>
    </CenteredPage>
  );
}

function RequireSignIn() {
  const { state, retry } = useAuth();
  const location = useLocation();
  if (state.status === "loading") return <RestoringSession />;
  if (state.status === "unavailable") {
    return <ServerUnavailable message={state.message} onRetry={retry} />;
  }
  if (state.status === "signedOut") {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/login?next=${next}`} replace />;
  }
  return <Outlet />;
}

// For /login and /invite: wait for the session check so a signed-in visitor goes straight on.
function SignedOutOnly() {
  const { state, retry } = useAuth();
  if (state.status === "loading") return <RestoringSession />;
  if (state.status === "unavailable") {
    return <ServerUnavailable message={state.message} onRetry={retry} />;
  }
  return <Outlet />;
}

function ShellLayout() {
  const user = useCurrentUser();
  const { signOut } = useAuth();
  return (
    <AppShell
      username={user.username}
      isAdmin={user.role === "admin"}
      onSignOut={() => void signOut()}
    >
      <Outlet />
    </AppShell>
  );
}

function RequireAdmin() {
  const user = useCurrentUser();
  return user.role === "admin" ? <Outlet /> : <NotFound />;
}

// The screens that render card Markdown load on demand, so KaTeX and the Markdown pipeline
// aren't part of the first download on the sign-in page or the deck list.
const loadDeckPage = async () => ({ Component: (await import("@/routes/Deck")).DeckPage });
const loadCardEditor = async () => ({
  Component: (await import("@/routes/CardEditor")).CardEditorPage,
});

export const router = createBrowserRouter([
  {
    errorElement: <RouteError />,
    hydrateFallbackElement: <RestoringSession />,
    children: [
      {
        element: <SignedOutOnly />,
        children: [
          { path: "/login", element: <LoginPage /> },
          { path: "/invite/:token", element: <InvitePage /> },
        ],
      },
      {
        element: <RequireSignIn />,
        children: [
          {
            path: "/decks/:deckId/study",
            lazy: async () => ({ Component: (await import("@/routes/Study")).StudyPage }),
          },
          {
            element: <ShellLayout />,
            children: [
              { path: "/", element: <DecksPage /> },
              { path: "/decks/:deckId", lazy: loadDeckPage },
              { path: "/decks/:deckId/cards/new", lazy: loadCardEditor },
              { path: "/decks/:deckId/cards/:cardId", lazy: loadCardEditor },
              { path: "/settings", element: <SettingsPage /> },
              {
                element: <RequireAdmin />,
                children: [
                  { path: "/admin/invites", element: <AdminInvitesPage /> },
                  { path: "/admin/users", element: <AdminUsersPage /> },
                ],
              },
            ],
          },
        ],
      },
      { path: "*", element: <NotFound /> },
    ],
  },
]);
