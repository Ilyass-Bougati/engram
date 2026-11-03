import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  use,
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import { api, errorMessage, onSessionEnded, refreshSession, setAccessToken } from "@/lib/api";
import type { SessionResponse, User } from "@/lib/types";

type AuthState =
  | { status: "loading" }
  | { status: "unavailable"; message: string }
  | { status: "signedOut" }
  | { status: "signedIn"; user: User };

interface AuthContextValue {
  state: AuthState;
  retry: () => void;
  startSession: (session: SessionResponse) => void;
  updateUser: (user: User) => void;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<AuthState>({ status: "loading" });

  const endSession = useCallback(() => {
    setAccessToken(null);
    queryClient.clear();
    setState({ status: "signedOut" });
  }, [queryClient]);

  const restore = useCallback(() => {
    // The refresh cookie is the only thing that survives a reload.
    refreshSession().then(
      (session) => {
        setState(session ? { status: "signedIn", user: session.user } : { status: "signedOut" });
      },
      (error: unknown) => {
        setState({ status: "unavailable", message: errorMessage(error) });
      },
    );
  }, []);

  useEffect(() => {
    onSessionEnded(endSession);
    restore();
    return () => {
      onSessionEnded(null);
    };
  }, [endSession, restore]);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      retry: () => {
        setState({ status: "loading" });
        restore();
      },
      startSession: (session) => {
        setAccessToken(session.access_token);
        setState({ status: "signedIn", user: session.user });
      },
      updateUser: (user) => {
        setState({ status: "signedIn", user });
      },
      signOut: async () => {
        try {
          await api("/auth/logout", { method: "POST", csrf: true });
        } finally {
          endSession();
        }
      },
    }),
    [state, restore, endSession],
  );

  return <AuthContext value={value}>{children}</AuthContext>;
}

export function useAuth(): AuthContextValue {
  const context = use(AuthContext);
  if (!context) throw new Error("useAuth needs an <AuthProvider> above it");
  return context;
}

export function useCurrentUser(): User {
  const { state } = useAuth();
  if (state.status !== "signedIn") throw new Error("useCurrentUser is only used behind sign-in");
  return state.user;
}
