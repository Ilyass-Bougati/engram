import type { APIRequestContext, Page } from "@playwright/test";

import { EXAMPLE_DECK, expect, importDeck, readStack, signInAs, test } from "./fixtures";

const VARIANTS = [
  { width: 1440, height: 900, colorScheme: "light" },
  { width: 1440, height: 900, colorScheme: "dark" },
  { width: 390, height: 844, colorScheme: "light" },
  { width: 390, height: 844, colorScheme: "dark" },
] as const;

type Variant = (typeof VARIANTS)[number];

const GEOGRAPHY = {
  format: "engram-deck",
  version: 1,
  deck: { name: "Capitals of the Americas", description: "" },
  cards: [
    {
      type: "quiz",
      question: "Which city is the capital of Canada?",
      options: [
        { text: "Toronto", correct: false },
        { text: "Ottawa", correct: true },
        { text: "Vancouver", correct: false },
        { text: "Montreal", correct: false },
      ],
      explanation:
        "Ottawa has been the capital since 1857, chosen partly as a compromise between Toronto and Montreal.",
      tags: ["canada"],
    },
  ],
};

const EMPTY_DECK = {
  format: "engram-deck",
  version: 1,
  deck: { name: "Organic chemistry", description: "Functional groups and reactions." },
  cards: [],
};

// Client-side navigation: a full page load would spend a refresh-token rotation (rate
// limited per IP) on every screenshot.
async function go(page: Page, path: string): Promise<void> {
  await page.evaluate((target) => {
    window.history.pushState(null, "", target);
    window.dispatchEvent(new PopStateEvent("popstate"));
  }, path);
}

async function capture(page: Page, name: string, variant: Variant): Promise<void> {
  await page.waitForLoadState("networkidle");
  await page.evaluate(() => document.fonts.ready);
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow, `${name} scrolls sideways at ${String(variant.width)}px`).toBeLessThanOrEqual(0);
  await page.screenshot({
    path: `screenshots/phase5/${name}-${String(variant.width)}-${variant.colorScheme}.png`,
    fullPage: true,
    animations: "disabled",
  });
}

async function cardIds(api: APIRequestContext, deckId: string): Promise<string[]> {
  const response = await api.get(`/api/decks/${deckId}/cards`);
  const page = (await response.json()) as { cards: { id: string }[] };
  return page.cards.map((card) => card.id);
}

test("screenshots of every screen", async ({ browser, page, apiAs }) => {
  test.setTimeout(240_000);
  const { admin, users } = readStack();
  const api = await apiAs(admin);
  const algebra = await importDeck(api, EXAMPLE_DECK);
  const geography = await importDeck(api, GEOGRAPHY);
  const empty = await importDeck(api, EMPTY_DECK);
  for (const [user, role] of [
    [users.friend, "viewer"],
    [users.reader, "editor"],
  ] as const) {
    const shared = await api.post(`/api/decks/${algebra.id}/members`, {
      data: { username: user.username, role },
    });
    expect(shared.ok()).toBe(true);
  }
  const [basicCardId, , quizCardId] = await cardIds(api, algebra.id);
  const invite = await api.post("/api/admin/invites");
  const { token } = (await invite.json()) as { token: string };

  const signedOut = await browser.newPage();
  for (const variant of VARIANTS) {
    await signedOut.setViewportSize(variant);
    await signedOut.emulateMedia({ colorScheme: variant.colorScheme });
    await signedOut.goto("/login");
    await expect(signedOut.getByRole("heading", { name: "Sign in to Engram" })).toBeVisible();
    await capture(signedOut, "login", variant);
  }
  await signedOut.goto(`/invite/${token}`);
  for (const variant of VARIANTS) {
    await signedOut.setViewportSize(variant);
    await signedOut.emulateMedia({ colorScheme: variant.colorScheme });
    await expect(signedOut.getByRole("heading", { name: "Create your account" })).toBeVisible();
    await capture(signedOut, "invite", variant);
  }
  await signedOut.close();

  await signInAs(page, admin);
  await page.goto("/");
  for (const variant of VARIANTS) {
    await page.setViewportSize(variant);
    await page.emulateMedia({ colorScheme: variant.colorScheme });

    await go(page, "/");
    await expect(
      page.getByRole("link", { name: "Linear algebra basics", exact: true }),
    ).toBeVisible();
    await capture(page, "decks", variant);

    await go(page, `/decks/${algebra.id}`);
    await expect(page.getByRole("heading", { name: "Linear algebra basics" })).toBeVisible();
    await expect(page.getByRole("region", { name: "Cards" }).getByRole("listitem")).toHaveCount(4);
    await capture(page, "deck", variant);

    await page.getByRole("button", { name: "More deck actions" }).click();
    await page.getByRole("menuitem", { name: "Share deck" }).click();
    await expect(page.getByRole("dialog").getByText(users.friend.username)).toBeVisible();
    await capture(page, "share-dialog", variant);
    await page.keyboard.press("Escape");

    await go(page, `/decks/${empty.id}`);
    await expect(page.getByText("No cards yet")).toBeVisible();
    await capture(page, "deck-empty", variant);

    await go(page, `/decks/${algebra.id}/cards/${basicCardId ?? ""}`);
    await expect(page.getByRole("heading", { name: "Edit card" })).toBeVisible();
    await capture(page, "card-basic", variant);

    await go(page, `/decks/${algebra.id}/cards/${quizCardId ?? ""}`);
    await expect(page.getByLabel("Option 3", { exact: true })).toBeVisible();
    await capture(page, "card-quiz", variant);

    await go(page, `/decks/${algebra.id}/study`);
    await expect(page.getByRole("button", { name: "Show answer" })).toBeVisible();
    await capture(page, "study-front", variant);
    await page.keyboard.press("Space");
    await expect(page.getByLabel("Answer")).toBeVisible();
    await capture(page, "study-answer", variant);

    await go(page, `/decks/${geography.id}/study`);
    await page.getByText("Ottawa", { exact: true }).click();
    await page.getByRole("button", { name: "Check answer" }).click();
    await expect(page.getByText("Correct.")).toBeVisible();
    await capture(page, "study-quiz-answered", variant);

    await go(page, `/decks/${empty.id}/study`);
    await expect(page.getByRole("heading", { name: "Nothing to study right now" })).toBeVisible();
    await capture(page, "study-nothing", variant);

    await go(page, "/settings");
    await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
    await capture(page, "settings", variant);

    await go(page, "/admin/invites");
    await expect(page.getByText("Waiting to be used")).toBeVisible();
    await capture(page, "admin-invites", variant);

    await go(page, "/admin/users");
    await expect(page.getByText(users.friend.username)).toBeVisible();
    await capture(page, "admin-users", variant);
  }
});
