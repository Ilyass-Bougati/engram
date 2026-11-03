import { expect, readStack, signInAs, test } from "../fixtures";

test("creates a deck, then a front/back card and a quiz card", async ({ page }) => {
  await signInAs(page, readStack().users.author);
  await page.goto("/");
  await expect(page.getByText("No decks yet")).toBeVisible();

  await page.getByRole("button", { name: "New deck" }).click();
  await page.getByLabel("Name").fill("Capitals");
  await page.getByRole("button", { name: "Create deck" }).click();
  await expect(page.getByRole("heading", { name: "Capitals" })).toBeVisible();
  await expect(page.getByText("No cards yet")).toBeVisible();

  await page.getByRole("link", { name: "Add card" }).first().click();
  await page.getByLabel("Front", { exact: true }).fill("What is the capital of **Portugal**?");
  await page.getByLabel("Back", { exact: true }).fill("Lisbon");
  await page.getByLabel("Tags (optional)").fill("europe");
  const preview = page.getByRole("region", { name: "Preview" });
  await expect(preview.locator("strong")).toHaveText("Portugal");
  await page.getByRole("button", { name: "Save and add another" }).click();
  await expect(page.getByRole("status")).toHaveText("Card added. Write the next one.");

  await page.getByText("Multiple choice", { exact: true }).click();
  await page.getByLabel("Question").fill("Which city is the capital of Australia?");
  await page.getByLabel("Option 1", { exact: true }).fill("Sydney");
  await page.getByLabel("Option 2", { exact: true }).fill("Canberra");
  await page.getByRole("button", { name: "Add option" }).click();
  await page.getByLabel("Option 3", { exact: true }).fill("Melbourne");
  await page.getByRole("button", { name: "Save card" }).click();
  await expect(page.getByRole("alert")).toHaveText("Mark the one correct option.");
  await page.getByLabel("Option 2 is correct").check();
  await expect(preview.getByText("Correct")).toHaveCount(1);
  await page.getByRole("button", { name: "Save card" }).click();

  await expect(page.getByRole("heading", { name: "Capitals" })).toBeVisible();
  const cards = page.getByRole("region", { name: "Cards" }).getByRole("listitem");
  await expect(cards).toHaveCount(2);
  await expect(cards.first()).toContainText("What is the capital of Portugal?");
  await expect(cards.first()).toContainText("Front and back · europe");
  await expect(cards.last()).toContainText("Multiple choice · 3 options · europe");

  await page.getByLabel("Search cards").fill("australia");
  await expect(cards).toHaveCount(1);
  await expect(cards.first()).toContainText("Which city is the capital of Australia?");
});
