import { expect, test } from "@playwright/test";

test("renders application root", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#app")).toBeVisible();
});
