import { expect } from '@playwright/test';
import fs from 'node:fs';

async function verifyGeometry(library) {
  const form = library.locator('[data-audio-filter-form]');
  const result = await form.evaluate(node => {
    const cells = [...node.children].filter(cell =>
      cell.querySelector('input, select')
    );
    const box = element => {
      const r = element.getBoundingClientRect();
      return {
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        right: r.right,
        bottom: r.bottom,
      };
    };
    return {
      viewport_width: innerWidth,
      actual_CSS_no_style_injection: true,
      fields: cells.map(cell => {
        const field = cell.querySelector('input, select');
        const label = cell.matches('label')
          ? cell
          : cell.querySelector('label');
        return { cell: box(cell), control: box(field), label: box(label) };
      }),
    };
  });
  expect(result.fields).toHaveLength(6);
  for (const field of result.fields) {
    expect(field.control.width).toBeGreaterThanOrEqual(160);
    expect(field.label.right).toBeLessThanOrEqual(field.cell.right + 1);
    expect(field.label.x).toBeGreaterThanOrEqual(field.cell.x - 1);
  }
  for (const [index, first] of result.fields.entries()) {
    for (const second of result.fields.slice(index + 1)) {
      const a = first.label,
        b = second.label;
      const x = Math.min(a.right, b.right) - Math.max(a.x, b.x);
      const y = Math.min(a.bottom, b.bottom) - Math.max(a.y, b.y);
      expect(x > 1 && y > 1).toBe(false);
    }
  }
  return result;
}

export async function verify({
  page,
  info,
  target,
  library,
  saved,
  prefix,
  asset,
  name,
  contrast,
}) {
  const applyPurpose = async value => {
    await library.locator('[data-audio-file-purpose-filter]').fill(value);
    const received = page.waitForResponse(response => {
      const requested = new URL(response.url());
      return (
        requested.pathname === prefix &&
        response.request().method() === 'GET' &&
        requested.searchParams.get('purpose') === value
      );
    });
    await library
      .getByRole('button', { name: 'Filtrar áudios', exact: true })
      .click();
    const response = await received;
    expect(response.status()).toBe(200);
    return response.json();
  };
  const usage = await applyPurpose('ura');
  expect(usage.meta.total).toBe(1);
  expect(usage.items.map(item => item.id)).toEqual([asset.id]);
  expect(usage.items[0].purpose).toBe('SYNTHETIC URA reception');
  await page.reload();
  await expect(library.locator('[data-audio-file-purpose-filter]')).toHaveValue(
    'ura'
  );
  await expect(saved).toContainText(name);
  const usageContrast = await contrast(
    library.locator(
      `label[for="${await library.locator('[data-audio-file-purpose-filter]').getAttribute('id')}"]`
    )
  );
  expect(usageContrast.ratio).toBeGreaterThanOrEqual(4.5);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await expect(
    saved.locator('[data-audio-asset-purpose-summary]')
  ).toContainText('SYNTHETIC URA reception');
  const geometry = await verifyGeometry(library);
  const actualDark = await page.evaluate(() =>
    document.documentElement.classList.contains('dark')
  );
  expect(actualDark).toBe(info.project.name.endsWith('dark'));
  const usageScreenshot = `.codex/call-center-native-e2e/${info.project.name}-audio-purpose-filter.png`;
  await library
    .locator('[data-audio-file-purpose-filter]')
    .scrollIntoViewIfNeeded();
  await page.screenshot({ path: usageScreenshot, fullPage: false });
  const unmatchedUsage = await applyPurpose(
    'SYNTHETIC no such institutional usage'
  );
  expect(unmatchedUsage.meta.total).toBe(0);
  expect(unmatchedUsage.items).toEqual([]);
  await expect(saved).toHaveCount(0);
  await applyPurpose('ura');
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-audio-purpose-filter.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: String(target.account_id),
        synthetic: true,
        actual_dark_theme: actualDark,
        actual_filter_geometry: geometry,
        actual_native_GET: true,
        asset_id: asset.id,
        persisted_purpose: 'SYNTHETIC URA reception',
        matching_total: usage.meta.total,
        unmatched_total: unmatchedUsage.meta.total,
        restored_URL_and_same_native_asset_after_reload: true,
        contrast: usageContrast,
        screenshot: usageScreenshot,
        new_catalog_or_provider_operation: false,
        whole_figure_or_Part1_accepted: false,
      },
      null,
      2
    ) + '\n'
  );
}
