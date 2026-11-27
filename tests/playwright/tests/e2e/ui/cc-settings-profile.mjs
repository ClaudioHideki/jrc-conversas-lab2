import { expect } from '@playwright/test';
import fs from 'node:fs';

// No intercepted response is fulfilled: delay only the actual authorized reads, then release them through existing safety routes.
export async function verify(page, info, session, numbers) {
  const account = String(session.account_id);
  const prefix = `/api/v1/accounts/${account}/jrc_contact_center`;
  const suffixes = [
    '/units',
    '/queues',
    '/queue_memberships',
    '/routing_rules',
  ];
  const paths = new Set(
    [...suffixes, '/integrations/capabilities', '/administration'].map(
      suffix => prefix + suffix
    )
  );
  const metrics = page.locator('[data-legacy-settings-metric]');
  await expect(metrics).toHaveCount(4);
  const initialCounts = [];
  for (const suffix of suffixes) {
    const response = await page.request.get(
      `http://127.0.0.1:5387${prefix}${suffix}`,
      { headers: session.administrator }
    );
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(Array.isArray(data.items)).toBe(true);
    initialCounts.push(data.items.length);
  }
  for (const [index, count] of initialCounts.entries()) {
    await expect(
      metrics.nth(index).getByText(String(count), { exact: true })
    ).toHaveCount(1);
  }
  const reads = [];
  const configurationRequests = [];
  const writes = [];
  let collect = false;
  const onResponse = async response => {
    const path = new URL(response.url()).pathname;
    if (!collect || response.request().method() !== 'GET' || !paths.has(path))
      return;
    const row = { path, status: response.status() };
    try {
      row.data = await response.json();
    } catch {
      row.invalid_JSON = true;
    }
    reads.push(row);
  };
  const onRequest = request => {
    if (
      paths.has(new URL(request.url()).pathname) &&
      request.method() === 'GET'
    )
      configurationRequests.push(new URL(request.url()).pathname);
    if (
      new URL(request.url()).pathname.startsWith(prefix + '/') &&
      !['GET', 'HEAD'].includes(request.method())
    )
      writes.push(request.method());
  };
  page.on('response', onResponse);
  page.on('request', onRequest);
  await numbers.nth(0).fill('541');
  const before = await page.evaluate(async () =>
    Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
  );
  await expect(numbers.nth(0)).toHaveValue('541');
  expect(reads).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  const firstImage = `.codex/call-center-native-e2e/${info.project.name}-legacy-settings-same-profile-draft.png`;
  await page.evaluate(
    isDark => document.documentElement.classList.toggle('dark', isDark),
    info.project.name.endsWith('dark')
  );
  await page.screenshot({ path: firstImage, fullPage: true });
  expect(configurationRequests).toEqual([]);
  let release;
  const held = new Promise(resolve => {
    release = resolve;
  });
  const blocked = new Set();
  let paused = true;
  const routePattern = '**/jrc_contact_center/**';
  const holdRealRead = async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (
      collect &&
      paused &&
      request.method() === 'GET' &&
      ['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin) &&
      suffixes.some(suffix => url.pathname === prefix + suffix)
    ) {
      blocked.add(url.pathname);
      await held;
    }
    return route.fallback();
  };
  await page.route(routePattern, holdRealRead);
  let after;
  let finalCounts;
  try {
    collect = true;
    await page.evaluate(
      auth => Object.assign(window.axios.defaults.headers.common, auth),
      session.restricted
    );
    after = await page.evaluate(async () =>
      Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
    );
    expect(String(after.account_id)).toBe(account);
    expect(String(before.account_id)).toBe(account);
    expect(String(after.user_id)).not.toBe(String(before.user_id));
    await expect.poll(() => blocked.size).toBe(4);
    for (const metric of await metrics.all())
      await expect(metric.getByText('—', { exact: true })).toHaveCount(1);
    paused = false;
    release();
    await expect.poll(() => reads.length).toBe(6);
    expect(new Set(reads.map(row => row.path)).size).toBe(6);
    expect(reads.every(row => [200, 401, 403].includes(row.status))).toBe(true);
    expect(reads.some(row => row.invalid_JSON)).toBe(false);
    const available = reads.every(row => row.status === 200);
    finalCounts = suffixes.map(suffix => {
      const result = reads.find(row => row.path === prefix + suffix);
      if (available) expect(Array.isArray(result.data.items)).toBe(true);
      return available ? result.data.items.length : null;
    });
    for (const [index, count] of finalCounts.entries()) {
      await expect(
        metrics
          .nth(index)
          .getByText(count === null ? '—' : String(count), { exact: true })
      ).toHaveCount(1);
    }
    expect(writes).toEqual([]);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    const secondImage = `.codex/call-center-native-e2e/${info.project.name}-legacy-settings-scoped-profile.png`;
    await page.evaluate(
      isDark => document.documentElement.classList.toggle('dark', isDark),
      info.project.name.endsWith('dark')
    );
    await page.screenshot({ path: secondImage, fullPage: true });
    const dark = await page.evaluate(() =>
      document.documentElement.classList.contains('dark')
    );
    expect(dark).toBe(info.project.name.endsWith('dark'));
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-legacy-settings-native-context.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          synthetic: true,
          account_id: account,
          source:
            'actual_native_profile_and_account_API_refresh_no_forged_profile_or_API_response',
          initial_counts: initialCounts,
          final_counts: finalCounts,
          before,
          after,
          same_profile_preserved_unsaved_541: true,
          same_profile_native_configuration_requests: 0,
          old_scope_cleared_before_new_native_reads: true,
          reads: reads.map(row => ({ path: row.path, status: row.status })),
          no_write_or_provider_operation: writes.length === 0,
          actual_dark_theme: dark,
          screenshots: [firstImage, secondImage],
          whole_Settings_or_profile_menu_accepted: false,
        },
        null,
        2
      )
    );
  } finally {
    paused = false;
    release();
    await page.unroute(routePattern, holdRealRead);
    page.off('response', onResponse);
    page.off('request', onRequest);
  }
}
