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
    await page.waitForURL(/\/app\/accounts\/\d+/);
    await page.waitForLoadState('domcontentloaded');
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
    const detail = page.locator('[data-approval-workspace] > section').nth(1);
    await expect(detail.locator('textarea').first()).toBeVisible();
    const approve = detail.getByRole('button', { name: new RegExp('^' + labels.decisionLabels.approved + '(?: ·|$)') }).first();
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


async function actualLogin(page, person = { email: fixture.email, password: fixture.password }) {
  await page.goto(origin + '/app/login');
  await page.locator('input[name="email_address"]').fill(person.email);
  await page.locator('input[type="password"]').fill(person.password);
  const response = page.waitForResponse(r => new URL(r.url()).pathname === '/auth/sign_in' && r.request().method() === 'POST');
  await page.locator('button[type="submit"]').click();
  const result = await response;
  expect(result.status()).toBe(200);
  await page.waitForURL(/\/app\/accounts\/\d+/);
  await page.waitForLoadState('domcontentloaded');
  const headers = await result.allHeaders();
  return Object.fromEntries(['access-token', 'client', 'uid', 'token-type'].filter(key => headers[key]).map(key => [key, headers[key]]));
}
async function isolatedTransport(context) {
  await context.route('**/*', route => route.request().url().startsWith(origin + '/') ? route.continue() : route.abort('blockedbyclient'));
  await context.routeWebSocket('**/*', socket => socket.url().startsWith('ws://127.0.0.1:3000/') ? socket.connectToServer() : socket.close());
}
for (const [index, mode] of modes.entries()) {
  test(`native simulation delegation adjustment and audit ${mode.name}`, async ({ page, context }) => {
    await page.setViewportSize({ width: mode.width, height: mode.height });
    await isolatedTransport(context);
    const headers = await actualLogin(page, fixture.users.manager);
    const base = `${origin}/app/accounts/${fixture.account_id}/approvals`;
    const api = `${origin}/api/v1/accounts/${fixture.account_id}/approvals`;
    await page.goto(base + '/simulate');
    await expect(page.getByRole('combobox', { name: labels.event, exact: true })).toBeVisible();
    await page.evaluate(dark => document.documentElement.classList.toggle('dark', dark), mode.dark);
    expect((await page.getByRole('combobox', { name: labels.event, exact: true }).locator('option').allTextContents()).some(text => text.includes('JRC_APPROVALS.'))).toBe(false);
    await page.getByRole('combobox', { name: labels.event, exact: true }).selectOption('crm.proposal_send');

    const resourcePicker = page.getByRole('combobox', { name: labels.resource, exact: true });
    const resourceOption = resourcePicker.locator('option[value="' + fixture.simulation_resource_id + '"]');
    for (let resourcePage = 0; resourcePage < 3 && (await resourceOption.count()) === 0; resourcePage += 1) {
      await expect(resourcePicker).toBeEnabled();
      if ((await resourceOption.count()) > 0) break;
      const response = page.waitForResponse(r => new URL(r.url()).pathname.endsWith('/approvals/resources') && r.request().method() === 'GET');
      await resourcePicker.locator('xpath=../..').getByRole('button', { name: labels.next, exact: true }).click();
      expect((await response).status()).toBe(200);
      await expect(resourcePicker).toBeEnabled();
    }
    await expect(resourceOption).toHaveCount(1);
    await resourcePicker.selectOption(String(fixture.simulation_resource_id));

    const simulation = page.waitForResponse(r => r.url().endsWith('/requests/simulate') && r.request().method() === 'POST');
    await page.getByRole('button', { name: labels.simulate, exact: true }).last().click();
    const simulated = await simulation;
    expect(simulated.status()).toBe(200);
    expect(simulated.request().postDataJSON().key).toBe('crm.proposal_send');
    const simulationBody = await simulated.json();
    expect(simulationBody.effects).toEqual([]);
    expect(simulationBody.versions.length).toBeGreaterThan(0);
    await expect(page.getByText(labels.noEffects, { exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-simulation.png`, fullPage: true });

    await page.getByRole('button', { name: labels.workspace.tabs.delegations, exact: true }).click();
    await expect(page.getByRole('combobox', { name: labels.scope, exact: true })).toBeVisible();
    await page.getByRole('combobox', { name: labels.scope, exact: true }).selectOption({ index: 1 });
    await page.getByRole('combobox', { name: labels.ownDelegation.recipient, exact: true }).selectOption(String(fixture.users.delegate.id));
    const localTime = offset => new Date(Date.now() + offset).toISOString().slice(0, 16);
    await page.getByLabel(labels.starts_at, { exact: true }).fill(localTime(10 * 60 * 1000));
    await page.getByLabel(labels.ends_at, { exact: true }).fill(localTime(40 * 60 * 1000));
    await page.getByLabel(labels.decisionLabels.approved, { exact: true }).check();
    const reason = `Synthetic ${mode.name} temporary delegation`;
    await page.getByLabel(labels.ownDelegation.reason, { exact: true }).fill(reason);
    const creation = page.waitForResponse(r => r.url().endsWith('/own_delegations') && r.request().method() === 'POST');
    await page.getByRole('button', { name: labels.ownDelegation.create, exact: true }).click();
    const created = await creation;
    expect(created.status()).toBe(201);
    const grant = await created.json();
    await page.reload();
    await expect(page.locator('article').filter({ hasText: reason })).toHaveCount(1);
    await page.evaluate(dark => document.documentElement.classList.toggle('dark', dark), mode.dark);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-delegation.png`, fullPage: true });
    const revoke = page.waitForResponse(r => r.url().endsWith(`/own_delegations/${grant.id}`) && r.request().method() === 'DELETE');
    await page.locator('article').filter({ hasText: reason }).getByRole('button', { name: labels.ownDelegation.revoke, exact: true }).click();
    expect((await revoke).status()).toBe(204);
    const persistedGrants = await context.request.get(api + '/own_delegations', { headers });
    expect(persistedGrants.status()).toBe(200);
    expect((await persistedGrants.json()).find(row => row.id === grant.id).revoked).toBe(true);

    const id = fixture.request_ids[4 + index];
    await page.goto(base + `/inbox/${id}`);
    await page.getByRole('button', { name: labels.adjustment.title, exact: true }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await dialog.getByLabel(labels.adjustment.discount, { exact: true }).fill('1.00');
    const save = dialog.getByRole('button', { name: labels.adjustment.save, exact: true });
    await expect(save).toBeDisabled();
    await dialog.getByLabel(labels.reason, { exact: true }).fill(`Synthetic ${mode.name} adjustment audit`);
    await expect(save).toBeEnabled();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-adjustment.png`, fullPage: true });
    const adjustment = page.waitForResponse(r => r.url().endsWith(`/requests/${id}/adjust`) && r.request().method() === 'POST');
    await save.click();
    const adjusted = await adjustment;
    expect(adjusted.status()).toBe(200);
    const adjustedBody = await adjusted.json();
    expect(adjustedBody.saved).toBe(true);
    expect(adjustedBody.request.id).toBeGreaterThan(id);
    const readBack = await context.request.get(api + `/requests/${adjustedBody.request.id}`, { headers });
    expect(readBack.status()).toBe(200);
    expect((await readBack.json()).adjustment.values.discount_cents).toBe(100);

    await page.getByRole('button', { name: labels.workspace.tabs.history, exact: true }).click();
    await expect(page.getByRole('table')).toBeVisible();
    await page.getByRole('button', { name: labels.open, exact: true }).first().click();
    await expect(page.locator('article')).not.toHaveCount(0);
    await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-history.png`, fullPage: true });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
}

test('native denial isolation empty state and stale navigation', async ({ page, context, browser }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await isolatedTransport(context);
  const headers = await actualLogin(page);
  const base = `${origin}/app/accounts/${fixture.account_id}/approvals`;
  const api = `${origin}/api/v1/accounts/${fixture.account_id}/approvals`;
  const noUnit = await context.request.get(api + `/requests/${fixture.other_unit_request_id}`, { headers });
  expect([403, 404]).toContain(noUnit.status());
  expect(await noUnit.text()).not.toContain('CONFIDENTIAL_OTHER_UNIT');
  const noAccount = await context.request.get(`${origin}/api/v1/accounts/${fixture.foreign_account_id}/approvals/requests`, { headers });
  expect([401, 403, 404]).toContain(noAccount.status());

  const conflictId = fixture.request_ids[9];
  await page.goto(base + '/inbox/' + conflictId);
  const conflictDetail = page.locator('[data-approval-workspace] > section').nth(1);
  await expect(conflictDetail.getByRole('button', { name: labels.adjustment.title, exact: true })).toHaveCount(0);
  const snapshot = await context.request.get(api + '/requests/' + conflictId, { headers });
  expect(snapshot.status()).toBe(200);
  const current = await snapshot.json();
  const deniedEdit = await context.request.post(api + '/requests/' + conflictId + '/adjust', {
    headers, data: { adjustment: { changes: { discount_cents: 100 }, mode: 'save',
      reason: 'Synthetic reviewer cannot edit another owners CRM source',
      expected_version: current.lock_version, idempotency_key: require('crypto').randomUUID() } },
  });
  expect(deniedEdit.status()).toBe(403);
  await conflictDetail.locator('textarea').first().fill('Synthetic stale reviewer decision');
  const other = await browser.newContext();
  try {
    const authenticated = await other.request.post(origin + '/auth/sign_in', {
      data: { email: fixture.users.recipient.email, password: fixture.users.recipient.password },
    });
    expect(authenticated.status()).toBe(200);
    const auth = authenticated.headers();
    const recipientHeaders = Object.fromEntries(['access-token', 'client', 'uid', 'token-type'].filter(k => auth[k]).map(k => [k, auth[k]]));
    const first = await other.request.post(api + '/requests/' + conflictId + '/decide', {
      headers: recipientHeaders, data: { decision: { step_code: 'review', decision: 'approved',
        reason: 'Synthetic concurrent eligible principal', expected_version: current.lock_version,
        idempotency_key: require('crypto').randomUUID() } },
    });
    expect(first.status()).toBe(200);
  } finally { await other.close(); }
  await conflictDetail.getByRole('button', { name: new RegExp('^' + labels.decisionLabels.approved + '(?: ·|$)') }).first().click();
  const stale = page.waitForResponse(r => r.url().endsWith('/requests/' + conflictId + '/decide') && r.request().method() === 'POST');
  await page.getByRole('dialog').getByRole('button', { name: labels.decisionLabels.approved, exact: true }).click();
  expect((await stale).status()).toBe(409);
  await expect(page.getByText(labels.concurrent, { exact: true })).toBeVisible();
  await page.screenshot({ path: process.env.JRC_BROWSER_OUTPUT + '/desktop-real-conflict.png', fullPage: true });
  const final = await context.request.get(api + '/requests/' + conflictId, { headers });
  expect((await final.json()).decisions).toHaveLength(1);

  await page.goto(base + '/inbox');
  await expect(page.locator('[data-approval-request]')).not.toHaveCount(0);
  await page.locator('input[type="search"]').fill('UNMATCHED_SYNTHETIC_QUEUE_SEARCH');
  await page.locator('input[type="search"]').locator('xpath=ancestor::form').evaluate(form => form.requestSubmit());
  await expect(page.locator('[data-approval-request]')).toHaveCount(0);
  await expect(page.getByText(labels.empty, { exact: true }).first()).toBeVisible();
  await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/desktop-empty.png`, fullPage: true });
  let release;
  let captured;
  const capturedPromise = new Promise(resolve => { captured = resolve; });
  const releasePromise = new Promise(resolve => { release = resolve; });
  await page.route('**/approvals/requests?*', async route => {
    const response = await route.fetch();
    captured();
    await releasePromise;
    await route.fulfill({ response }); // Unmodified real server response, delayed only.
  }, { times: 1 });
  await page.getByRole('button', { name: labels.workspace.clearFilters, exact: true }).click();
  await capturedPromise;
  await expect(page.getByRole('status').filter({ hasText: labels.loading })).toBeVisible();
  await page.getByRole('button', { name: labels.workspace.tabs.policies, exact: true }).click();
  release();
  await expect(page).toHaveURL(/\/policies$/);
  await expect(page.getByRole('table')).toBeVisible();
  await expect(page.locator('[data-approval-request]')).toHaveCount(0);
  // Replace the actual authenticated session through native authentication, never a Vue store injection.
  await page.getByRole('button', { name: /Synthetic reviewer/ }).last().click();
  const loggedOut = page.waitForResponse(r => new URL(r.url()).pathname === '/auth/sign_out' && r.request().method() === 'DELETE');
  await page.getByText(/^(Sair|Logout|Log out)$/, { exact: true }).click();
  expect((await loggedOut).status()).toBe(200);
  await page.waitForURL(/\/app\/login/);
  await actualLogin(page, fixture.users.denied);
  await page.goto(base + '/inbox');
  await expect(page.getByText(labels.denied, { exact: true }).first()).toBeVisible();
  await expect(page.locator('[data-approval-request]')).toHaveCount(0);
  await expect(page.locator('[data-metric]')).toHaveCount(0);
  await page.screenshot({ path: `${process.env.JRC_BROWSER_OUTPUT}/desktop-denied-profile.png`, fullPage: true });
});
