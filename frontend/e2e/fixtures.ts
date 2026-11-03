import { readFileSync } from "node:fs";
import path from "node:path";

import { test as base, type APIRequestContext, type Page } from "@playwright/test";

import { BACKEND_URL, type TestUser } from "./stack";

export { readStack } from "./stack";

export { expect } from "@playwright/test";

export const EXAMPLE_DECK = JSON.parse(
  readFileSync(path.join(import.meta.dirname, "../../docs/example-deck.json"), "utf8"),
) as unknown;

// An API client authenticated as a test user, for setting up data the spec isn't about.
export const test = base.extend<{ apiAs: (user: TestUser) => Promise<APIRequestContext> }>({
  apiAs: async ({ playwright }, use) => {
    const contexts: APIRequestContext[] = [];
    await use(async (user) => {
      const context = await playwright.request.newContext({
        baseURL: BACKEND_URL,
        extraHTTPHeaders: { Authorization: `Bearer ${user.accessToken}` },
      });
      contexts.push(context);
      return context;
    });
    await Promise.all(contexts.map((context) => context.dispose()));
  },
});

// Hands the browser a refresh cookie from the setup project, as if the user had signed in
// earlier; the app's first refresh turns it into a session.
export async function signInAs(page: Page, user: TestUser): Promise<void> {
  await page.context().addCookies([
    {
      name: "engram_refresh",
      value: user.refreshToken,
      domain: "localhost",
      path: "/api/auth",
      httpOnly: true,
      secure: true,
      sameSite: "Lax",
    },
  ]);
}

export async function importDeck(
  api: APIRequestContext,
  deckFile: unknown,
): Promise<{ id: string; name: string }> {
  const response = await api.post("/api/decks/import", { data: deckFile });
  if (!response.ok())
    throw new Error(`import failed: ${String(response.status())} ${await response.text()}`);
  return (await response.json()) as { id: string; name: string };
}
