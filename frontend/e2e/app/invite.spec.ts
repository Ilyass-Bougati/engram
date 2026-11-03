import { APP_URL } from "../stack";
import { expect, readStack, test } from "../fixtures";

test("an admin's invite link signs a new person up, once", async ({ page, browser }) => {
  const { admin } = readStack();

  await page.goto("/login");
  await page.getByLabel("Username").fill(admin.username);
  await page.getByLabel("Password").fill(admin.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("link", { name: "Admin" }).click();
  await page.getByRole("button", { name: "Create invite link" }).click();
  const link = await page.getByLabel("Invite link", { exact: true }).inputValue();
  expect(link).toMatch(new RegExp(`^${APP_URL}/invite/[\\w-]{20,}$`));
  await page.getByRole("button", { name: "Done" }).click();

  const newcomer = await browser.newContext();
  const signup = await newcomer.newPage();
  await signup.goto(link);
  await expect(signup.getByRole("heading", { name: "Create your account" })).toBeVisible();
  await signup.getByLabel("Username").fill("zainab");
  await signup.getByLabel("Password", { exact: true }).fill("correct horse battery");
  await signup.getByLabel("Confirm password").fill("correct horse batter");
  await signup.getByRole("button", { name: "Create account" }).click();
  await expect(signup.getByRole("alert")).toContainText("don't match");
  await signup.getByLabel("Confirm password").fill("correct horse battery");
  await signup.getByRole("button", { name: "Create account" }).click();
  await expect(signup.getByRole("heading", { name: "Your decks" })).toBeVisible();
  await expect(signup.getByText("No decks yet")).toBeVisible();
  await expect(signup.getByRole("button", { name: "zainab" })).toBeVisible();
  await newcomer.close();

  await page.reload();
  await expect(page.getByText("zainab signed up")).toBeVisible();

  const latecomer = await browser.newContext();
  const reuse = await latecomer.newPage();
  await reuse.goto(link);
  await expect(
    reuse.getByRole("heading", { name: "This invite link is no longer valid" }),
  ).toBeVisible();
  await latecomer.close();
});
