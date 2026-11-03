import { expect, importDeck, readStack, signInAs, test } from "../fixtures";

const SPANISH_VERBS = {
  format: "engram-deck",
  version: 1,
  deck: { name: "Spanish verbs", description: "Present tense, first person." },
  cards: [
    { type: "basic", front: "hablar", back: "hablo", tags: ["ar"] },
    { type: "basic", front: "comer", back: "como", tags: ["er"] },
  ],
};

test("the owner shares a deck and the other person gets view-only access", async ({
  page,
  browser,
  apiAs,
}) => {
  const { owner, friend } = readStack().users;
  const deck = await importDeck(await apiAs(owner), SPANISH_VERBS);
  await signInAs(page, owner);
  await page.goto(`/decks/${deck.id}`);

  await page.getByRole("button", { name: "More deck actions" }).click();
  await page.getByRole("menuitem", { name: "Share deck" }).click();
  const dialog = page.getByRole("dialog", { name: "Share deck" });
  await dialog.getByLabel("Username").fill("nobody-here");
  await dialog.getByRole("button", { name: "Share" }).click();
  await expect(dialog.getByRole("alert")).toHaveText(
    "No user named 'nobody-here'. Check the spelling.",
  );

  await dialog.getByLabel("Username").fill(friend.username);
  await dialog.getByRole("button", { name: "Share" }).click();
  await expect(dialog.getByLabel(`Role for ${friend.username}`)).toHaveValue("viewer");
  await page.keyboard.press("Escape");

  const friendContext = await browser.newContext();
  const friendPage = await friendContext.newPage();
  await signInAs(friendPage, friend);
  await friendPage.goto("/");
  await expect(friendPage.getByText("shared with you as viewer")).toBeVisible();
  await friendPage.getByRole("link", { name: "Spanish verbs", exact: true }).click();
  await expect(friendPage.getByRole("heading", { name: "Spanish verbs" })).toBeVisible();
  await expect(friendPage.getByRole("region", { name: "Cards" }).getByRole("listitem")).toHaveCount(
    2,
  );
  await expect(friendPage.getByRole("link", { name: "Add card" })).toHaveCount(0);
  await friendPage.getByRole("button", { name: "More deck actions" }).click();
  await expect(friendPage.getByRole("menuitem", { name: "Members" })).toBeVisible();
  await expect(friendPage.getByRole("menuitem", { name: "Import cards from JSON" })).toHaveCount(0);
  await friendContext.close();
});
