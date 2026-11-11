import { expect, importDeck, readStack, signInAs, test } from "../fixtures";

function deckFile(name: string, front: string, back: string) {
  return {
    format: "engram-deck",
    version: 1,
    deck: { name, description: "" },
    cards: [{ type: "basic", front, back, tags: [] }],
  };
}

test("a collection is studied, shared and renamed as a whole", async ({ page, apiAs }) => {
  // Refresh tokens work once, and invites are rate-limited, so this test borrows two users:
  // reader's refresh token is handed to no other browser (its test signs in with the
  // password), and student is only checked through the API and loses access at the end.
  const { reader: owner, student: friend } = readStack().users;
  const ownerApi = await apiAs(owner);
  await importDeck(ownerApi, deckFile("Portuguese::Day 10", "obrigado", "thank you"));
  await importDeck(ownerApi, deckFile("Portuguese::Day 2", "bom dia", "good morning"));
  await signInAs(page, owner);
  await page.goto("/");

  // Study draws from both decks, Day 2 before Day 10, and names the deck of each card.
  await page.getByRole("link", { name: "Study Portuguese", exact: true }).click();
  const card = page.getByRole("article", { name: "Card" });
  const expected: [string, string][] = [
    ["Day 2", "bom dia"],
    ["Day 10", "obrigado"],
  ];
  for (const [deck, front] of expected) {
    await expect(card.getByText(deck, { exact: true })).toBeVisible();
    await expect(card.getByText(front)).toBeVisible();
    await page.keyboard.press("Space");
    await page.keyboard.press("4");
  }
  await expect(page.getByRole("heading", { name: "Done for now" })).toBeVisible();
  await page.getByRole("link", { name: "Back to your decks" }).click();

  await page.getByRole("button", { name: "More actions for Portuguese" }).click();
  await page.getByRole("menuitem", { name: "Share collection" }).click();
  const share = page.getByRole("dialog", { name: 'Share "Portuguese"' });
  await share.getByLabel("Username").fill(friend.username);
  await share.getByRole("button", { name: "Share" }).click();
  await expect(share.getByRole("status")).toHaveText(`Shared with ${friend.username}: 2 decks.`);
  await expect(share.getByLabel(`Role for ${friend.username} on your decks`)).toHaveValue("viewer");
  await page.keyboard.press("Escape");

  await page.getByRole("button", { name: "More actions for Portuguese" }).click();
  await page.getByRole("menuitem", { name: "Collection settings" }).click();
  const settings = page.getByRole("dialog", { name: "Collection settings" });
  await settings.getByLabel("Name").fill("Languages::Portuguese");
  await settings.getByRole("button", { name: "Save" }).click();
  await expect(settings).toBeHidden();
  await expect(page.getByRole("button", { name: /^Languages/ })).toBeVisible();

  const friendApi = await apiAs(friend);
  const friendDecks = async () =>
    ((await (await friendApi.get("/api/decks")).json()) as { name: string; role: string }[])
      .filter((deck) => deck.name.startsWith("Languages::Portuguese::"))
      .map((deck) => [deck.name, deck.role]);
  expect((await friendDecks()).sort()).toEqual([
    ["Languages::Portuguese::Day 10", "viewer"],
    ["Languages::Portuguese::Day 2", "viewer"],
  ]);

  await page.getByRole("button", { name: /^Languages/ }).click();
  await page.getByRole("button", { name: "More actions for Languages / Portuguese" }).click();
  await page.getByRole("menuitem", { name: "Share collection" }).click();
  const shareAgain = page.getByRole("dialog", { name: 'Share "Languages / Portuguese"' });
  await shareAgain
    .getByRole("button", { name: `Remove ${friend.username} from your decks` })
    .click();
  await expect(shareAgain.getByRole("status")).toHaveText(
    `${friend.username} was removed from 2 decks.`,
  );
  expect(await friendDecks()).toEqual([]);
});
