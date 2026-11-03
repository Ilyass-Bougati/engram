import { fileURLToPath } from "node:url";

import { expect, readStack, signInAs, test } from "../fixtures";

const PACKAGE = fileURLToPath(new URL("../fixtures/geography.apkg", import.meta.url));

test("imports an Anki package with its progress", async ({ page }) => {
  await signInAs(page, readStack().users.importer);
  await page.goto("/");

  await page.getByRole("button", { name: "Import" }).click();
  await page.getByRole("menuitem", { name: "Anki package (.apkg)" }).click();
  const dialog = page.getByRole("dialog", { name: "Import from Anki" });
  await dialog.getByLabel("Deck package").setInputFiles(PACKAGE);
  await expect(dialog.getByLabel("Keep my Anki progress")).toBeChecked();
  await dialog.getByRole("button", { name: "Import" }).click();

  const summary = dialog.getByRole("status");
  await expect(summary).toContainText("Imported 6 cards into Geography.");
  await expect(summary).toContainText("4 past reviews kept your schedule going.");
  await expect(summary).toContainText("3 cards lost an image or a sound");
  await expect(summary).toContainText("1 card was left out");

  await dialog.getByRole("link", { name: "Open deck" }).click();
  await expect(page.getByRole("heading", { name: "Geography" })).toBeVisible();
  const cards = page.getByRole("region", { name: "Cards" }).getByRole("listitem");
  await expect(cards).toHaveCount(6);
  // Cloze and MathJax arrive as Markdown and render.
  await expect(cards.nth(3).locator(".katex")).toBeVisible();
});
