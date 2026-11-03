import { expect, readStack, test } from "../fixtures";

test("signs in after a wrong password, lands on the page asked for, and signs out", async ({
  page,
}) => {
  const { reader } = readStack().users;

  await page.goto("/settings");
  await expect(page).toHaveURL(/\/login\?next=%2Fsettings$/);
  await page.getByLabel("Username").fill(reader.username);
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("alert")).toHaveText("Incorrect username or password.");

  await page.getByLabel("Password").fill(reader.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
  await expect(page.getByText(`Signed in as ${reader.username}.`)).toBeVisible();

  await page.getByRole("button", { name: reader.username }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await expect(page.getByRole("heading", { name: "Sign in to Engram" })).toBeVisible();
  // The refresh cookie was revoked, so a reload doesn't bring the session back.
  await page.reload();
  await expect(page.getByRole("heading", { name: "Sign in to Engram" })).toBeVisible();
});
