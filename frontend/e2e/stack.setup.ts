import { randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";

import { expect, request, test as setup } from "@playwright/test";

import { BACKEND_URL, compose, STACK_FILE, type StackState, type TestUser } from "./stack";

const ADMIN_USERNAME = "amara";
const USERNAMES = {
  reader: "noor",
  author: "ines",
  student: "kofi",
  owner: "lucia",
  friend: "tomas",
  importer: "sami",
} as const;

function secret(): string {
  return randomBytes(24).toString("base64url");
}

async function signedIn(
  username: string,
  password: string,
  response: { ok: () => boolean; json: () => Promise<unknown>; status: () => number },
  refreshToken: string | undefined,
): Promise<TestUser> {
  expect(response.ok(), `signing in ${username} answered ${String(response.status())}`).toBe(true);
  const { access_token } = (await response.json()) as { access_token: string };
  expect(refreshToken).toBeTruthy();
  return { username, password, accessToken: access_token, refreshToken: refreshToken ?? "" };
}

async function refreshCookie(
  context: Awaited<ReturnType<typeof request.newContext>>,
): Promise<string | undefined> {
  const { cookies } = await context.storageState();
  return cookies.find((cookie) => cookie.name === "engram_refresh")?.value;
}

// Users come from invites redeemed here, once, so the specs themselves stay under the
// per-IP limits on login (10/min) and invite redemption (10/min).
setup("start a throwaway stack and create the test users", async () => {
  setup.setTimeout(300_000);
  const secrets = { POSTGRES_PASSWORD: secret(), JWT_SECRET: secret() };
  compose(["down", "--volumes", "--remove-orphans"], secrets);
  compose(["up", "--detach", "--build", "--wait", "backend"], secrets);

  const adminPassword = secret();
  compose(
    [
      "exec",
      "-T",
      "backend",
      "python",
      "-m",
      "app.cli",
      "create-admin",
      ADMIN_USERNAME,
      "--password-stdin",
    ],
    secrets,
    `${adminPassword}\n`,
  );
  const adminContext = await request.newContext({ baseURL: BACKEND_URL });
  const admin = await signedIn(
    ADMIN_USERNAME,
    adminPassword,
    await adminContext.post("/api/auth/login", {
      data: { username: ADMIN_USERNAME, password: adminPassword },
    }),
    await refreshCookie(adminContext),
  );

  const users = {} as StackState["users"];
  for (const [role, username] of Object.entries(USERNAMES) as [keyof typeof USERNAMES, string][]) {
    const invite = await adminContext.post("/api/admin/invites", {
      headers: { Authorization: `Bearer ${admin.accessToken}` },
    });
    expect(invite.ok()).toBe(true);
    const { token } = (await invite.json()) as { token: string };
    const password = secret();
    const userContext = await request.newContext({ baseURL: BACKEND_URL });
    const response = await userContext.post(`/api/invites/${token}/redeem`, {
      data: { username, password, timezone: "Europe/Berlin" },
    });
    users[role] = await signedIn(username, password, response, await refreshCookie(userContext));
    await userContext.dispose();
  }
  await adminContext.dispose();

  const state: StackState = { secrets, admin, users };
  writeFileSync(STACK_FILE, JSON.stringify(state, null, 2));
});
