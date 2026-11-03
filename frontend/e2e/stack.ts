import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

// The throwaway stack's app: the built web app and the API on one origin, as deployed. The
// browser uses localhost (the refresh cookie is set for it); API set-up calls go direct.
export const APP_URL = "http://localhost:6768";
export const BACKEND_URL = "http://127.0.0.1:6768";
export const STACK_FILE = path.join(import.meta.dirname, ".stack.json");

export interface TestUser {
  username: string;
  password: string;
  accessToken: string;
  // Each refresh token can sign in exactly one browser context: it rotates on first use.
  refreshToken: string;
}

export interface StackState {
  secrets: { POSTGRES_PASSWORD: string; JWT_SECRET: string };
  admin: TestUser;
  users: Record<"reader" | "author" | "student" | "owner" | "friend" | "importer", TestUser>;
}

export function readStack(): StackState {
  return JSON.parse(readFileSync(STACK_FILE, "utf8")) as StackState;
}

export function compose(args: string[], secrets: StackState["secrets"], input?: string): string {
  return execFileSync(
    "docker",
    [
      "compose",
      "--project-name",
      "engram-e2e",
      "--file",
      path.join(import.meta.dirname, "../../compose.yaml"),
      "--file",
      path.join(import.meta.dirname, "compose.e2e.yaml"),
      ...args,
    ],
    {
      env: { ...process.env, ...secrets },
      input,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "inherit"],
    },
  );
}
