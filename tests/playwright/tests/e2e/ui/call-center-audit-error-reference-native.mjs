import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Same native audit form and response. No route fulfillment or injected error body.
export async function verifyNativeAuditQueryFailure(page, panel, info) {
  const table = panel.locator('[data-audit-table]');
  await expect(table).toBeVisible();
  const row = table.locator('[data-audit-row]').first();
  await expect(table.locator('thead th')).toHaveCount(6);
  await expect(row.locator('td')).toHaveCount(6);
  await expect(row.locator('[data-audit-local-result]')).toHaveText('Registrado no JRC');
  const layout = await row.evaluate(element => ({
    tag: element.tagName, display: getComputedStyle(element).display,
    left: element.getBoundingClientRect().left, right: element.getBoundingClientRect().right,
    viewport: innerWidth,
  }));
  expect(layout.tag).toBe('TR');
  expect(layout.display).toBe(info.project.name.startsWith('mobile') ? 'block' : 'table-row');
  expect(layout.left).toBeGreaterThanOrEqual(0);
  expect(layout.right).toBeLessThanOrEqual(layout.viewport);
  await panel.getByLabel('Data inicial', { exact: true }).fill('2026-11-18');
  await panel.getByLabel('Data final', { exact: true }).fill('2026-11-17');
  const failed = page.waitForResponse(response =>
    response.request().method() === 'GET' &&
    new URL(response.url()).pathname.endsWith('/configuration_audits') && response.status() === 422
  );
  await panel.getByRole('button', { name: 'Aplicar filtros', exact: true }).click();
  const response = await failed;
  const id = response.headers()['x-request-id'];
  expect(id).toMatch(/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i);
  const error = panel.locator('[data-audit-list-error]');
  await expect(error).toContainText('Confira as datas inicial e final.');
  await expect(error).toContainText(id);
  await expect(panel.locator('[data-audit-row]')).toHaveCount(0);
  const contrast = await measureLocatorTextContrast(error);
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  const screenshot = `.codex/call-center-native-e2e/${info.project.name}-audit-native-error-reference.png`;
  await page.screenshot({ path: screenshot, fullPage: true });
  return { actual_native_request_id: id, actual_native_query_status: response.status(), contrast, screenshot, native_table_layout: layout };
}

export async function preserveNativeAuditQueryRecovery(page, panel, info, accountId, observed) {
  await expect(panel.locator('[data-audit-list-error]')).toHaveCount(0);
  await expect(panel.locator('[data-audit-row]').first()).toBeVisible();
  const dark = await page.evaluate(() => document.documentElement.classList.contains('dark'));
  expect(dark).toBe(info.project.name.endsWith('dark'));
  fs.writeFileSync(`.codex/call-center-native-e2e/${info.project.name}-audit-native-error-reference.json`, JSON.stringify({
    ...observed, sha: process.env.GITHUB_SHA, project: info.project.name, account_id: String(accountId), synthetic: true,
    actual_dark_theme: dark, real_error_not_empty_success: true,
    explicit_successful_recovery_cleared_error: true, no_new_provider_operation: true,
    whole_figure14_or_Part1_accepted: false,
  }, null, 2) + '\n');
}
