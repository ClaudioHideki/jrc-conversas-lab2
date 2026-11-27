import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// The original recordings browser case supplies its real authenticated page.
// No fake response, provider call, new seed or permission is introduced.
export async function verifyNativeRecordingResultFilters(page, info, target) {
  const account = String(target.account_id);
  const base = `/api/v1/accounts/${account}/jrc_contact_center/recordings`;
  const screenshots = [];
  const result = page.locator('[data-recordings-filter="status"]');
  const direction = page.locator('[data-recordings-filter="direction"]');
  const responseFor = criteria =>
    page.waitForResponse(response => {
      const url = new URL(response.url());
      return (
        response.request().method() === 'GET' &&
        url.pathname === base &&
        Object.entries(criteria).every(
          ([key, value]) => url.searchParams.get(key) === String(value)
        )
      );
    });
  const capture = async name => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    const dark = await page.evaluate(() =>
      document.documentElement.classList.contains('dark')
    );
    expect(dark).toBe(info.project.name.endsWith('dark'));
    const path = `.codex/call-center-native-e2e/${info.project.name}-recording-result-${name}.png`;
    await page.screenshot({ path, fullPage: true });
    screenshots.push(path);
  };
  await page.goto(
    `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&synthetic_filter_context=preserved`
  );
  await expect(page.locator('[data-recording-row]')).toHaveCount(20);
  await result.selectOption('answered');
  await direction.selectOption('inbound');
  const firstResponse = responseFor({
    status: 'answered',
    direction: 'inbound',
    page: 1,
  });
  await page
    .locator('[data-scoped-recordings] form button[type="submit"]')
    .click();
  const first = await firstResponse;
  expect(first.status()).toBe(200);
  const page1 = await first.json();
  expect(page1.meta).toMatchObject({ page: 1, total: 21, pages: 2 });
  expect(page1.summary.total).toBe(21);
  expect(page1.items).toHaveLength(20);
  expect(
    page1.items.every(
      row => row.status === 'answered' && row.direction === 'inbound'
    )
  ).toBe(true);
  const contrast = await measureLocatorTextContrast(result.locator('..'));
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await capture('native-filtered-list');
  const nextResponse = responseFor({
    status: 'answered',
    direction: 'inbound',
    page: 2,
  });
  await page.getByRole('button', { name: 'Próxima', exact: true }).click();
  const next = await nextResponse;
  expect(next.status()).toBe(200);
  const page2 = await next.json();
  expect(page2.meta).toMatchObject({ page: 2, total: 21, pages: 2 });
  expect(page2.summary).toEqual(page1.summary);
  expect(page2.items).toHaveLength(1);
  const ids = [...page1.items, ...page2.items].map(row => row.id);
  expect(new Set(ids).size).toBe(21);
  const reloadResponse = responseFor({
    status: 'answered',
    direction: 'inbound',
    page: 2,
  });
  await page.reload();
  expect((await reloadResponse).status()).toBe(200);
  await expect(page.locator('[data-recording-row]')).toHaveCount(1);
  await expect(result).toHaveValue('answered');
  await expect(direction).toHaveValue('inbound');
  expect(new URL(page.url()).searchParams.get('synthetic_filter_context')).toBe(
    'preserved'
  );
  await result.selectOption('busy');
  const emptyResponse = responseFor({
    status: 'busy',
    direction: 'inbound',
    page: 1,
  });
  await page
    .locator('[data-scoped-recordings] form button[type="submit"]')
    .click();
  const empty = await emptyResponse;
  expect(empty.status()).toBe(200);
  const zero = await empty.json();
  expect(zero.items).toEqual([]);
  expect(zero.meta.total).toBe(0);
  expect(zero.summary.total).toBe(0);
  expect(zero.summary.duration_seconds).toBe(null);
  await expect(page.locator('[data-recording-row]')).toHaveCount(0);
  await capture('real-zero-filtered-result');
  const clearResponse = responseFor({ page: 1 });
  await page
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  const cleared = await clearResponse;
  expect(cleared.status()).toBe(200);
  expect((await cleared.json()).meta.total).toBe(21);
  await expect(page.locator('[data-recording-row]')).toHaveCount(20);
  await expect(result).toHaveValue('');
  await expect(direction).toHaveValue('');
  expect(new URL(page.url()).searchParams.has('recordings_status')).toBe(false);
  expect(new URL(page.url()).searchParams.has('recordings_direction')).toBe(
    false
  );
  expect(new URL(page.url()).searchParams.get('synthetic_filter_context')).toBe(
    'preserved'
  );
  const denied = await page.request.get(base, {
    headers: target.operator,
    params: {
      status: 'answered',
      direction: 'inbound',
      unit_id: target.denied_unit_id,
    },
  });
  expect(denied.status()).toBe(404);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-recording-result-filters.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: account,
        synthetic: true,
        actual_dark_theme: info.project.name.endsWith('dark'),
        native_page_one: page1.meta,
        native_page_two: page2.meta,
        same_scoped_period_summary_before_pagination: page1.summary,
        distinct_native_ids: ids,
        filters_and_second_page_restored_by_native_reload: true,
        real_empty_result: zero.summary,
        explicit_clear_preserved_other_navigation: true,
        denied_unit_status: denied.status(),
        contrast,
        screenshots,
        new_provider_operation: false,
        whole_figure_accepted: false,
      },
      null,
      2
    ) + '\n'
  );
}
