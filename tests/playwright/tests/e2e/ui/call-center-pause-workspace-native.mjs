import { expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Extends the existing native pause catalog case. No mocked HTTP response,
// new fixture, provider command or application write is used by navigation.
export async function verifyNativePauseWorkspace(page, info, target) {
  const account = String(target.account_id);
  const api = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center/`;
  const workspace = page.locator('[data-pause-workspace]');
  const screenshots = [];
  const reads = [];
  const contrast = [];
  const writes = [];
  const errors = [];
  const pageError = error => errors.push(error.message);
  const track = request => {
    if (
      request.url().includes(`/accounts/${account}/jrc_contact_center/`) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      writes.push(request.method() + ' ' + new URL(request.url()).pathname);
  };
  const nativeResponse = async (request, path) => {
    const response = await request;
    expect(response.status()).toBe(200);
    const text = await response.text();
    const value = JSON.parse(text);
    expect(value.account_id).toBe(account);
    reads.push({
      path,
      sha256: createHash('sha256').update(text).digest('hex'),
    });
    return value;
  };
  const readAfter = async (path, action) => {
    const response = page.waitForResponse(value => {
      const actual = new URL(value.url());
      return isBrowserApiResponse(
        value,
        page.url(),
        api + path + actual.search,
        'GET'
      );
    });
    await action();
    return nativeResponse(response, path);
  };
  const capture = async key => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(info.project.name.endsWith('dark'));
    const path = `.codex/call-center-native-e2e/${info.project.name}-pause-workspace-${key}.png`;
    await page.screenshot({ path, fullPage: true });
    screenshots.push(path);
  };
  page.on('request', track);
  page.on('pageerror', pageError);
  try {
    await expect(workspace.getByRole('tab')).toHaveCount(4);
    await expect(
      workspace.locator('[data-pause-workspace-tab="motives"]')
    ).toHaveAttribute('aria-selected', 'true');
    contrast.push(
      ...(await Promise.all(
        ['motives', 'distribution', 'availability', 'history'].map(
          async key => {
            const value = await measureLocatorTextContrast(
              workspace.locator(`[data-pause-workspace-tab="${key}"]`)
            );
            expect(value.ratio).toBeGreaterThanOrEqual(4.5);
            return { key, ...value };
          }
        )
      ))
    );
    const routing = await readAfter('routing_rules', () =>
      workspace.locator('[data-pause-workspace-tab="distribution"]').click()
    );
    expect(Array.isArray(routing.items)).toBe(true);
    await expect(workspace.locator('[data-routing-workspace]')).toBeVisible();
    await expect(page).toHaveURL(/pauses_tab=distribution/);
    await capture('distribution');
    const observed = await readAfter('supervisor', () =>
      workspace.locator('[data-pause-workspace-tab="availability"]').click()
    );
    expect(Array.isArray(observed.agents)).toBe(true);
    expect(Array.isArray(observed.queues)).toBe(true);
    await expect(
      workspace.locator('[data-supervisor-observed-metrics]')
    ).toBeVisible();
    await expect(workspace.locator('[data-routing-workspace]')).toHaveCount(0);
    await capture('availability');
    await readAfter('supervisor', () => page.reload());
    await expect(
      workspace.locator('[data-pause-workspace-tab="availability"]')
    ).toHaveAttribute('aria-selected', 'true');
    const history = await readAfter('agent_state_histories', () =>
      workspace.locator('[data-pause-workspace-tab="history"]').click()
    );
    expect(Array.isArray(history.items)).toBe(true);
    await expect(
      page.getByRole('dialog').locator('[data-state-history-content]')
    ).toBeVisible();
    await capture('history');
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Fechar', exact: true })
      .click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await readAfter('pause_catalog', () =>
      workspace.locator('[data-pause-workspace-tab="motives"]').click()
    );
    await expect(workspace.locator('[data-pause-catalog]')).toBeVisible();
    await expect(page).not.toHaveURL(/pauses_tab=/);
    expect(writes).toEqual([]);
    expect(errors).toEqual([]);
    const denied = await Promise.all(
      ['routing_rules', 'supervisor', 'agent_state_histories'].map(
        async path => {
          const response = await page.request.get(api + path, {
            headers: target.operator,
          });
          expect(response.status()).toBe(401);
          return { path, status: response.status() };
        }
      )
    );
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-pause-workspace.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          synthetic: true,
          four_native_destinations_reused: true,
          availability_URL_reload: true,
          writes,
          errors,
          native_reads: reads,
          denied,
          contrast,
          screenshots,
          provider_operation: false,
          whole_figure_or_Part1_accepted: false,
        },
        null,
        2
      ) + '\n'
    );
  } finally {
    page.off('request', track);
    page.off('pageerror', pageError);
  }
}
