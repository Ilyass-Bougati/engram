import type { SessionResponse } from "@/lib/types";

// An error whose message is written for the person using the app and can be shown as is.
export class UserFacingError extends Error {}

export class ApiError extends UserFacingError {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const CSRF_HEADER = { "X-Engram-CSRF": "1" };

// The access token lives in memory only, so a script injected into the page can't read a
// stored copy; the refresh token is an httpOnly cookie scoped to /api/auth.
let accessToken: string | null = null;
let refreshInFlight: Promise<SessionResponse | null> | null = null;
let sessionEndedListener: (() => void) | null = null;

export function setAccessToken(token: string | null): void {
  accessToken = token;
}

export function onSessionEnded(listener: (() => void) | null): void {
  sessionEndedListener = listener;
}

async function errorFrom(response: Response): Promise<ApiError> {
  let detail = `The server answered ${String(response.status)}. Try again in a moment.`;
  try {
    const body = (await response.json()) as { detail?: unknown };
    if (typeof body.detail === "string") detail = body.detail;
  } catch (error) {
    // A proxy error page instead of JSON: keep the generic message.
    if (!(error instanceof SyntaxError)) throw error;
  }
  return new ApiError(response.status, detail);
}

async function fetchOrExplain(input: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(input, init);
  } catch (error) {
    if (error instanceof TypeError) {
      throw new ApiError(0, "Can't reach the server. Check your connection and try again.");
    }
    throw error;
  }
}

async function postRefresh(): Promise<SessionResponse | null> {
  const response = await fetchOrExplain("/api/auth/refresh", {
    method: "POST",
    headers: CSRF_HEADER,
  });
  if (response.status === 401) return null;
  if (!response.ok) throw await errorFrom(response);
  return (await response.json()) as SessionResponse;
}

// Refresh tokens rotate on every use, and presenting an already-rotated one ends the whole
// session as suspected theft. So refreshes never overlap: concurrent callers in this tab share
// one request, and the Web Lock makes other tabs wait until the new cookie is set.
export function refreshSession(): Promise<SessionResponse | null> {
  refreshInFlight ??= (
    "locks" in navigator ? navigator.locks.request("engram-refresh", postRefresh) : postRefresh()
  )
    .then((session) => {
      accessToken = session?.access_token ?? null;
      return session;
    })
    .finally(() => {
      refreshInFlight = null;
    });
  return refreshInFlight;
}

interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  csrf?: boolean;
}

export async function apiResponse(path: string, options: RequestOptions = {}): Promise<Response> {
  const { method = "GET", body, csrf = false } = options;
  const attempt = () => {
    const headers: Record<string, string> = csrf ? { ...CSRF_HEADER } : {};
    if (accessToken) headers.Authorization = `Bearer ${accessToken}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    return fetchOrExplain(`/api${path}`, {
      method,
      headers,
      body: body === undefined ? null : JSON.stringify(body),
    });
  };
  let response = await attempt();
  if (response.status === 401 && accessToken !== null) {
    // The access token expired (15 minutes): refresh once and retry.
    const session = await refreshSession();
    if (session === null) {
      sessionEndedListener?.();
      throw new ApiError(401, "Your session has expired. Sign in again.");
    }
    response = await attempt();
  }
  if (!response.ok) throw await errorFrom(response);
  return response;
}

export async function api<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const response = await apiResponse(path, options);
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export function errorMessage(error: unknown): string {
  return error instanceof UserFacingError
    ? error.message
    : "Something went wrong. Reload the page.";
}
