const { test, expect } = require(process.env.JRC_PLAYWRIGHT_MODULE);
const fs = require('fs');
const fixture = JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_CREDENTIALS, 'utf8'));
const merge = (base, extra) => Object.fromEntries(Object.keys({ ...base, ...extra }).map(key => [key, typeof base[key] === 'object' && typeof extra[key] === 'object' ? merge(base[key], extra[key]) : (extra[key] ?? base[key])]));
const labels = merge(JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_LOCALE_FILE.replace('/pt_BR/', '/en/'), 'utf8')).JRC_APPROVALS, JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_LOCALE_FILE, 'utf8')).JRC_APPROVALS);
const origin = process.env.JRC_BROWSER_ORIGIN;
if (fixture.product_sha !== process.env.JRC_BROWSER_PRODUCT_SHA) throw new Error('Browser fixture image identity differs');
if (origin !== 'http://127.0.0.1:3000') throw new Error('Only the owned loopback image forwarder is permitted');
const modes = [
  { name: 'desktop-light', width: 1440, height: 1000, dark: false },
  { name: 'desktop-dark', width: 1440, height: 1000, dark: true },
  { name: 'mobile-light', width: 390, height: 844, dark: false },
  { name: 'mobile-dark', width: 390, height: 844, dark: true },
];

for (const [index, mode] of modes.entries()) {
  test(`native approval workspace ${mode.name}`, async ({ page, context, browser }) => {
    test.info().annotations.push({ type: 'browser', description: browser.version() });
    test.info().annotations.push({ type: 'product', description: fixture.product_sha });
    await page.setViewportSize({ width: mode.width, height: mode.height });
    await page.emulateMedia({ colorScheme: mode.dark ? 'dark' : 'light' });
    await context.route('**/*', route => {
      const url = route.request().url();
      if (url.startsWith(origin + '/') || url.startsWith('data:') || url.startsWith('blob:')) return route.continue();
      return route.abort('blockedbyclient');
    });
    await context.routeWebSocket('**/*', socket => {
      if (socket.url().startsWith('ws://127.0.0.1:3000/')) socket.connectToServer();
      else socket.close();
    });
    await page.goto(origin + '/app/login');
    expect(await page.evaluate(() => window.isSecureContext && typeof crypto.randomUUID === 'function')).toBe(true);
    await page.locator('input[name="email_address"]').fill(fixture.email);
    await page.locator('input[type="password"]').fill(fixture.password);
    const authenticated = page.waitForResponse(r => r.url().endsWith('/auth/sign_in') && r.request().method() === 'POST');
    await page.locator('button[type="submit"]').click();
    expect((await authenticated).status()).toBe(200);
    const base = `${origin}/app/accounts/${fixture.account_id}/approvals/inbox`;
    await page.goto(base);
    await expect(page.locator('[data-approval-workspace]')).toBeVisible();
    await expect(page.locator('[data-approval-request]')).toHaveCount(25);
    await expect(page.locator('[data-metric="pending"]')).not.toHaveText('—');
    await page.evaluate(dark => document.documentElement.classList.toggle('dark', dark), mode.dark);
    await expect(page.locator('input[type="search"]')).toBeVisible();
    const colors = await page.locator('[data-metric]').evaluateAll(metrics => metrics.map(metric =>
      getComputedStyle(metric.closest('article')).backgroundColor));
    expect(new Set(colors).size).toBe(4);
    expect(colors.every(color => color !== 'rgba(0, 0, 0, 0)')).toBe(true);
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-inbox.png`, fullPage: true });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);

    await page.getByRole('button', { name: labels.next, exact: true }).click();
    await expect(page).toHaveURL(/page=2/);
    await expect(page.locator('[data-approval-request]')).toHaveCount(29 - index - 25);
    await page.getByRole('button', { name: labels.previous, exact: true }).click();
    await expect(page.locator('[data-approval-request]')).toHaveCount(25);

    const id = fixture.request_ids[index];
    await page.locator('input[type="search"]').fill(String(id));
    await page.locator('input[type="search"]').locator('xpath=ancestor::form').evaluate(form => form.requestSubmit());
    await expect(page.locator(`[data-approval-request="${id}"]`)).toBeVisible();
    await page.locator(`[data-approval-request="${id}"]`).click();
    const detail = page.locator('[data-approval-workspace] section').last();
    await expect(detail.locator('textarea').first()).toBeVisible();
    const approve = detail.getByRole('button', { name: labels.decisionLabels.approved, exact: true });
    await expect(approve).toBeDisabled();
    await detail.locator('textarea').first().fill(`Synthetic ${mode.name} native evidence`);
    await expect(approve).toBeEnabled();
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-detail.png`, fullPage: true });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await approve.click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-confirmation.png`, fullPage: true });
    const saved = page.waitForResponse(r => r.url().endsWith(`/requests/${id}/decide`) && r.request().method() === 'POST');
    await dialog.getByRole('button', { name: labels.decisionLabels.approved, exact: true }).click();
    expect((await saved).status()).toBe(200);
    await page.reload();
    await expect(detail).toContainText(labels.workspace.states.approved);
    await page.evaluate(dark => document.documentElement.classList.toggle('dark', dark), mode.dark);
    if (mode.width === 390) {
      await page.getByRole('button', { name: labels.workspace.backToQueue, exact: true }).click();
      await expect(page.locator('input[type="search"]')).toBeVisible();
    }
    await page.getByRole('button', { name: labels.workspace.clearFilters, exact: true }).click();
    await expect(page.locator('input[type="search"]')).toHaveValue('');
    await expect(page.locator('[data-approval-request]')).toHaveCount(25);
    await page.getByRole('button', { name: labels.workspace.tabs.policies, exact: true }).click();
    await page.getByRole('button', { name: labels.open, exact: true }).first().click();
    const tabs = page.getByRole('tab');
    await expect(tabs).toHaveCount(4);
    for (let step = 0; step < 4; step += 1) {
      await tabs.nth(step).click();
      await expect(tabs.nth(step)).toHaveAttribute('aria-selected', 'true');
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-rule-summary.png`, fullPage: true });
  });
}
