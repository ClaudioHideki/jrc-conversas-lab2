import { expect } from '@playwright/test';
import { openLoadedNativeTask } from './call-center-native-loaded-task-view.mjs';
import fs from 'node:fs';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Production Hoya/history/Projects components, real Rails/PostgreSQL and CSS.
// All writes are denied in this browser: reads cannot act as execution/retry.
export async function verifyEndingAttemptHistory(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}`;
  const endpoint = `${root}/jrc_contact_center/qualifications/${target.qualification_id}/ending_attempts`;
  const browserPath = new URL(endpoint).pathname;
  const headers = target.administrator;
  const location = `/app/accounts/${account}/synthetic-hoya-acw/${target.call_session_id}`;
  const dark = info.project.name.endsWith('dark');
  const screenshots = [];
  const requests = [];
  const prohibited = [];
  const errors = [];
  const stateContrast = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.origin === 'http://127.0.0.1:5386' && url.pathname === browserPath)
      requests.push(request.method());
  });
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    if (outside || !['GET', 'HEAD'].includes(request.method())) {
      prohibited.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  await page.addInitScript(
    ({ auth, isDark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: headers, isDark: dark }
  );
  const taskTotal = async () => {
    const response = await page.request.get(
      `${root}/projects/projects/${target.automation_project_id}/tasks`,
      { headers }
    );
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Number.isInteger(body.meta.total)).toBe(true);
    return body.meta.total;
  };
  const read = async (number = 1) => {
    const response = await page.request.get(endpoint, {
      headers,
      params: { page: number },
    });
    expect(response.status()).toBe(200);
    expect(response.headers()['cache-control']).toBe('no-store');
    const data = await response.json();
    expect(data.account_id).toBe(account);
    expect(data.qualification_id).toBe(String(target.qualification_id));
    return data;
  };
  const capture = async label => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    expect(
      await page
        .locator('html')
        .evaluate(node => node.classList.contains('dark'))
    ).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-history-${label}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
  };
  const showHistory = async () => {
    await page.goto(location);
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    const panel = page.locator('[data-ending-attempt-history]:visible');
    await expect(panel).toHaveCount(1);
    await panel.locator('[data-open-ending-attempt-history]').click();
    await expect(panel.locator('[data-ending-attempt-row]')).toHaveCount(20);
    return panel;
  };
  try {
    const before = [await read(), await read(2)];
    const beforeTasks = await taskTotal();
    expect(beforeTasks).toBe(1);
    expect(before[0].meta).toMatchObject({
      page: 1,
      per_page: 20,
      total: 23,
      pages: 2,
    });
    expect(before[0].items.every(row => row.outcome === 'pending')).toBe(true);
    expect(before[1].items.map(row => row.outcome).sort()).toEqual([
      'blocked',
      'failed',
      'succeeded',
    ]);
    expect(requests).toEqual([]);
    let panel = await showHistory();
    expect(requests).toEqual(['GET']);
    const [contrast] = await panel.locator('h4').evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    stateContrast.push(
      ...(await panel
        .locator('[data-ending-attempt-state]')
        .first()
        .evaluate(measureTextContrast))
    );
    await capture('pending-page');
    await panel.getByRole('button', { name: 'Próxima', exact: true }).click();
    await expect(panel.locator('[data-ending-attempt-row]')).toHaveCount(3);
    await expect(panel.getByText('Concluída', { exact: true })).toBeVisible();
    await expect(panel.getByText('Bloqueada', { exact: true })).toBeVisible();
    await expect(panel.getByText('Falha', { exact: true })).toBeVisible();
    for (const state of await panel
      .locator('[data-ending-attempt-state]')
      .all()) {
      stateContrast.push(...(await state.evaluate(measureTextContrast)));
    }
    expect(stateContrast).toHaveLength(4);
    expect(
      stateContrast.every(row => row.ratio >= 4.5),
      `Actual native history state contrast: ${JSON.stringify(stateContrast)}`
    ).toBe(true);
    await expect(panel.locator('[data-ending-attempt-target]')).toHaveCount(1);
    await capture('independent-outcomes');
    panel = await showHistory();
    await panel.getByRole('button', { name: 'Próxima', exact: true }).click();
    await expect(panel.locator('[data-ending-attempt-row]')).toHaveCount(3);
    expect([await read(), await read(2)]).toEqual(before);
    const denied = await page.request.get(endpoint, {
      headers: target.operator,
    });
    expect([401, 403]).toContain(denied.status());
    expect(await denied.text()).not.toContain('SYNTHETIC_HISTORY_RULE');
    const link = panel.locator('[data-ending-attempt-target]');
    const href = new URL(
      await link.getAttribute('href'),
      'http://127.0.0.1:5386'
    );
    expect(href.pathname).toBe(
      `/app/accounts/${account}/projetos/${target.automation_project_id}`
    );
    expect(href.searchParams.get('taskId')).toBe(
      String(target.history_task_id)
    );
    const nativeTaskView = await openLoadedNativeTask(page, {
      link,
      accountId: account,
      projectId: target.automation_project_id,
      taskId: target.history_task_id,
      title: 'SYNTHETIC private history task',
    });
    await capture('native-task');
    expect(await taskTotal()).toBe(beforeTasks);
    expect([await read(), await read(2)]).toEqual(before);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    expect(requests.every(method => method === 'GET')).toBe(true);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ending-history-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          project: info.project.name,
          account_id: account,
          qualification_id: String(target.qualification_id),
          native_immutable_attempts: 23,
          pending: 20,
          succeeded: 1,
          blocked: 1,
          failed: 1,
          synthetic_persistence_fault_injection: true,
          native_task_total_before: beforeTasks,
          native_task_total_after: await taskTotal(),
          persisted_after_reload: true,
          ordinary_other_agent_status: denied.status(),
          native_task_view: nativeTaskView,
          native_task_route_opened: true,
          prohibited_mutations_or_external_calls: prohibited,
          page_errors: errors,
          actual_dark: dark,
          contrast_ratio: contrast.ratio,
          state_contrast_ratios: stateContrast.map(row => row.ratio),
          screenshots,
          whole_figure10_or_Part1_accepted: false,
        },
        null,
        2
      )
    );
  } catch (error) {
    await page
      .screenshot({
        path: `.codex/call-center-native-e2e/${info.project.name}-ending-history-failure-before-close.png`,
      })
      .catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
