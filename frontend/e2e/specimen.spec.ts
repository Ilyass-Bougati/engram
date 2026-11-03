import { expect, test, type Page } from "@playwright/test";

const VIEWPORTS = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
];
const SCHEMES = ["light", "dark"] as const;

async function openSpecimen(page: Page): Promise<void> {
  await page.goto("/specimen.html");
  await page.evaluate(() => document.fonts.ready);
}

for (const viewport of VIEWPORTS) {
  for (const colorScheme of SCHEMES) {
    test(`specimen at ${String(viewport.width)}px, ${colorScheme}`, async ({ page }) => {
      await page.setViewportSize(viewport);
      await page.emulateMedia({ colorScheme });
      await openSpecimen(page);

      const name = `${String(viewport.width)}-${colorScheme}`;
      await page.screenshot({ path: `screenshots/phase4/specimen-${name}.png`, fullPage: true });

      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - window.innerWidth,
      );
      expect(overflow).toBeLessThanOrEqual(0);
      const fontsLoaded = await page.evaluate(() => [
        document.fonts.check('16px "IBM Plex Sans Variable"'),
        document.fonts.check('16px "IBM Plex Mono"'),
      ]);
      expect(fontsLoaded).toEqual([true, true]);

      await page.getByRole("button", { name: "Share deck" }).click();
      const dialog = page.getByRole("dialog", { name: "Share deck" });
      await expect(dialog).toBeVisible();
      await expect(dialog.getByLabel("Username")).toBeFocused();
      await page.screenshot({
        path: `screenshots/phase4/dialog-${name}.png`,
        animations: "disabled",
      });
      await page.keyboard.press("Escape");
      await expect(dialog).toBeHidden();
    });
  }
}

test("glass turns solid when more contrast is requested", async ({ page }) => {
  const headerBackground = () =>
    page.locator("header.glass").evaluate((element) => getComputedStyle(element).backgroundColor);
  await openSpecimen(page);
  expect(await headerBackground()).toMatch(/^rgba\(.*, 0\.8\d*\)$/);
  await page.emulateMedia({ contrast: "more" });
  expect(await headerBackground()).toMatch(/^rgb\(/);
});
