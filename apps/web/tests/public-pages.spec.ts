import { expect, test, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const pages = [
  {
    path: "/",
    heading: "A little ahead. A lot more present.",
    title: "A little ahead.",
  },
  {
    path: "/privacy",
    heading: "Your plans stay personal.",
    title: "Privacy policy",
  },
  {
    path: "/support",
    heading: "Let’s get you back on time.",
    title: "Support",
  },
  { path: "/terms", heading: "A few things to know.", title: "Terms of use" },
  {
    path: "/data-deletion",
    heading: "Your data. Your choice.",
    title: "Remove your data",
  },
] as const;

async function expectNoOverflow(page: Page) {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth + 1,
    ),
  ).toBe(true);
}

for (const route of pages) {
  test(`${route.path} is public, accessible, and has production metadata`, async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const response = await page.goto(route.path);
    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle(
      new RegExp(`${route.title.replaceAll(".", "\\.")}.*Nextbell`),
    );
    await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
    const heading = await page.getByRole("heading", { level: 1 }).innerText();
    expect(heading.replace(/\s+/g, "").replace("✳", "")).toBe(
      route.heading.replaceAll(" ", ""),
    );
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      "href",
      `https://nextbell.org${route.path === "/" ? "" : route.path}`,
    );
    await expect(page.locator('meta[name="description"]')).toHaveAttribute(
      "content",
      /.+/,
    );
    await expect(page.locator('meta[property="og:url"]')).toHaveAttribute(
      "content",
      `https://nextbell.org${route.path === "/" ? "" : route.path}`,
    );
    await expect(
      page.locator('meta[property="og:image"]').first(),
    ).toHaveAttribute("content", /https:\/\/nextbell.org\/opengraph-image/);
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
      "content",
      "summary_large_image",
    );
    await expect(page.locator('link[rel="icon"]').first()).toHaveAttribute(
      "href",
      /icon.png/,
    );
    await expect(page.locator('meta[name="viewport"]')).not.toHaveAttribute(
      "content",
      /user-scalable=no|maximum-scale=1/,
    );
    await expect(
      page
        .getByRole("contentinfo")
        .getByRole("link", { name: "makadsuhel11@gmail.com" }),
    ).toHaveAttribute("href", "mailto:makadsuhel11@gmail.com");
    await expect(
      page.locator(
        'a[href*="apps.apple.com"], a[href*="play.google.com"], a[href*="dashboard"], a[href*="login"], a[href*="sign-in"], form',
      ),
    ).toHaveCount(0);
    await expectNoOverflow(page);
    const scan = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(scan.violations).toEqual([]);
    expect(errors).toEqual([]);
  });

  test(`${route.path} reflows at 320px with enlarged text and reduced motion`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 320, height: 800 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(route.path);
    await page.addStyleTag({ content: "html { font-size: 200%; }" });
    await page.evaluate(() => document.fonts.ready);
    await expectNoOverflow(page);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    expect(
      await page
        .locator(".entrance")
        .evaluateAll((elements) =>
          elements.every(
            (element) => getComputedStyle(element).animationName === "none",
          ),
        ),
    ).toBe(true);
    expect(
      await page.evaluate(
        () => getComputedStyle(document.documentElement).scrollBehavior,
      ),
    ).toBe("auto");
  });
}

test("navigation, email support and data removal are reachable", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByRole("navigation", { name: "Main navigation" })
    .getByRole("link", { name: "Support", exact: true })
    .click();
  await expect(page).toHaveURL(/\/support$/);
  await expect(
    page.getByRole("link", { name: "Email support" }),
  ).toHaveAttribute(
    "href",
    "mailto:makadsuhel11@gmail.com?subject=Nextbell%20support",
  );
  await page
    .getByText("Why is a shared or subscribed calendar missing?", {
      exact: true,
    })
    .click();
  await expect(
    page.getByText(/The calendar owner never needs to sign in/),
  ).toBeVisible();
  for (const link of [
    { name: "Privacy", path: "/privacy" },
    { name: "Terms", path: "/terms" },
    { name: "Remove your data", path: "/data-deletion" },
  ]) {
    await page
      .getByRole("navigation", { name: "Footer navigation" })
      .getByRole("link", { name: link.name, exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`${link.path}$`));
  }
  await expect(
    page.getByText(
      /cannot remotely erase device-only data or delete your Google account/,
    ),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Manage your Google connections" }),
  ).toHaveAttribute("href", "https://myaccount.google.com/connections");
  await page
    .getByRole("banner")
    .getByRole("link", { name: "Nextbell home" })
    .click();
  await expect(page).toHaveURL(/\/$/);
});

test("keyboard users can skip navigation and change reminder chips", async ({
  page,
  browserName,
}) => {
  // WebKit follows Safari’s Option-Tab convention for focusing all links.
  const nextFocus = browserName === "webkit" ? "Alt+Tab" : "Tab";
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page.keyboard.press(nextFocus);
  await expect(
    page.getByRole("link", { name: "Skip to content" }),
  ).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("main")).toBeFocused();
  const ten = page.getByRole("button", { name: "10 min before" });
  const five = page.getByRole("button", { name: "5 min before" });
  await ten.focus();
  await page.keyboard.press("Space");
  await expect(ten).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator(".demo-result")).toHaveText("A nudge at 2:55 PM.");
  await page.keyboard.press(nextFocus);
  await expect(five).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator(".demo-result")).toHaveText(
    "Just on your agenda. No alarms.",
  );
  await ten.click();
  await five.click();
  await expect(page.locator(".demo-result")).toHaveText(
    "A nudge at 2:50 PM and 2:55 PM.",
  );
  await page.goto("/support");
  const summary = page.locator("#setup summary");
  await summary.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("#setup")).toHaveAttribute("open", "");
  expect(
    (
      await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze()
    ).violations,
  ).toEqual([]);
});

test("404, sitemap, robots, social image and bundled media work", async ({
  page,
  request,
}) => {
  const response = await page.goto("/this-page-does-not-exist");
  expect(response?.status()).toBe(404);
  await page.getByRole("link", { name: "Back to Nextbell" }).click();
  await expect(page).toHaveURL(/\/$/);
  const robots = await request.get("/robots.txt");
  expect(await robots.text()).toContain(
    "Sitemap: https://nextbell.org/sitemap.xml",
  );
  const sitemap = await request.get("/sitemap.xml");
  const sitemapText = await sitemap.text();
  for (const route of pages)
    expect(sitemapText).toContain(
      `https://nextbell.org${route.path === "/" ? "" : route.path}</loc>`,
    );
  const social = await request.get("/opengraph-image");
  expect(social.ok()).toBe(true);
  expect(social.headers()["content-type"]).toContain("image/png");
  for (const image of await page.locator("main img").all()) {
    await image.scrollIntoViewIfNeeded();
    await expect(image).toBeVisible();
    await expect
      .poll(() =>
        image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
      )
      .toBeGreaterThan(0);
  }
});
