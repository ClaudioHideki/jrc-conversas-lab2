import { expect } from '@playwright/test';
import { openLoadedNativeTask } from './call-center-native-loaded-task-view.mjs';
import fs from 'node:fs';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Real Hoya/confirmation/Projects components, CSS and native Rails API. Never
// intercept a response or synthesize a successful automation result.
export async function verifySelectedPendingEnding(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}`;
  const history = `${root}/jrc_contact_center/qualifications/${target.qualification_id}/ending_attempts`;
  const command = `${history}/${target.selected_attempt_id}/reprocess`;
  const browserCommand = new URL(
    new URL(command).pathname,
    'http://127.0.0.1:5386'
  ).href;
  const location = `/app/accounts/${account}/synthetic-hoya-acw/${target.call_session_id}`;
  const dark = info.project.name.endsWith('dark');
  const screenshots = [];
  const mutations = [];
  const prohibited = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    const writing = !['GET', 'HEAD'].includes(request.method());
    if (
      outside ||
      (writing &&
        (request.url() !== browserCommand || request.method() !== 'POST'))
    ) {
      prohibited.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    if (writing) mutations.push(JSON.parse(request.postData()));
    return route.continue();
  });
  await page.addInitScript(
    ({ auth, isDark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: target.operator, isDark: dark }
  );
  const read = async () => {
    const response = await page.request.get(history, {
      headers: target.operator,
    });
    expect(response.status()).toBe(200);
    expect(response.headers()['cache-control']).toBe('no-store');
    const body = await response.json();
    expect(body.account_id).toBe(account);
    expect(body.qualification_id).toBe(String(target.qualification_id));
    expect(body.meta.total).toBe(2);
    return body.items;
  };
  const taskTotal = async () => {
    const response = await page.request.get(
      `${root}/projects/projects/${target.automation_project_id}/tasks`,
      { headers: target.administrator }
    );
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(Number.isInteger(body.meta.total)).toBe(true);
    return body.meta.total;
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
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-pending-${label}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
  };
  const showHistory = async () => {
    await page.goto(location);
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    const panel = page.locator('[data-ending-attempt-history]:visible');
    await panel.locator('[data-open-ending-attempt-history]').click();
    await expect(panel.locator('[data-ending-attempt-row]')).toHaveCount(2);
    return panel;
  };
  const review = {
    confirmed: true,
    expected_request_key: target.selected_request_id,
    expected_version_id: String(target.selected_version_id),
  };
  try {
    expect(await taskTotal()).toBe(0);
    const before = await read();
    expect(
      before.every(
        row => row.outcome === 'pending' && row.can_reprocess_pending
      )
    ).toBe(true);
    const denied = await page.request.post(command, {
      headers: target.administrator,
      data: review,
    });
    expect([401, 403]).toContain(denied.status());
    expect(await denied.text()).not.toContain(target.selected_request_id);
    expect(await read()).toEqual(before);
    const panel = await showHistory();
    expect(mutations).toEqual([]);
    const selected = panel
      .locator('[data-ending-attempt-row]')
      .filter({ hasText: 'SYNTHETIC_SELECTED_PENDING' });
    await selected.locator('[data-review-selected-ending-pending]').click();
    const dialog = page.getByRole('dialog', {
      name: 'Reprocessar esta pendência',
      exact: true,
    });
    await expect(dialog).toBeVisible();
    const submit = dialog.locator('[data-run-selected-ending-pending]');
    await expect(submit).toBeDisabled();
    expect(await taskTotal()).toBe(0);
    expect(mutations).toEqual([]);
    await expect(
      dialog.getByText(String(target.selected_version_id), { exact: true })
    ).toBeVisible();
    await expect(
      dialog.getByText(target.selected_request_id, { exact: true })
    ).toBeVisible();
    await capture('explicit-review');
    const [contrast] = await dialog
      .locator('[data-ending-pending-review] > p.font-semibold')
      .evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await dialog.locator('[data-ending-pending-confirmed]').check();
    await expect(submit).toBeEnabled();
    const acknowledgement = page.waitForResponse(
      response =>
        response.url() === browserCommand &&
        response.request().method() === 'POST'
    );
    await submit.click();
    expect((await acknowledgement).status()).toBe(200);
    await expect(dialog).toBeHidden();
    await expect(
      selected.getByText('Concluída', { exact: true })
    ).toBeVisible();
    expect(mutations).toEqual([review]);
    expect(await taskTotal()).toBe(1);
    const after = await read();
    const completed = after.find(
      row => row.id === String(target.selected_attempt_id)
    );
    const other = after.find(
      row => row.id !== String(target.selected_attempt_id)
    );
    expect(completed).toMatchObject({
      outcome: 'succeeded',
      result_code: 'completed',
      can_reprocess_pending: false,
    });
    expect(other).toEqual(before.find(row => row.id === other.id));
    await capture('selected-only-outcome');
    await showHistory();
    expect(await read()).toEqual(after);
    const replay = await page.request.post(command, {
      headers: target.operator,
      data: review,
    });
    expect(replay.status()).toBe(409);
    expect((await replay.json()).error).toBe(
      'ending_attempt_no_longer_pending'
    );
    expect(await taskTotal()).toBe(1);
    const link = page.locator('[data-ending-attempt-target]');
    const href = new URL(
      await link.getAttribute('href'),
      'http://127.0.0.1:5386'
    );
    expect(href.pathname).toBe(
      `/app/accounts/${account}/projetos/${target.automation_project_id}`
    );
    expect(href.searchParams.get('taskId')).toBe(completed.target.id);
    const nativeTaskView = await openLoadedNativeTask(page, {
      link,
      accountId: account,
      projectId: target.automation_project_id,
      taskId: completed.target.id,
      title: 'SYNTHETIC_SELECTED_PENDING native task',
    });
    await capture('native-task');
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ending-pending-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          project: info.project.name,
          account_id: account,
          qualification_id: String(target.qualification_id),
          selected_attempt_id: String(target.selected_attempt_id),
          original_actor_nonadministrator: true,
          only_selected_POST: true,
          explicit_confirmation: true,
          native_task_view: nativeTaskView,
          native_tasks_before: 0,
          native_tasks_after: await taskTotal(),
          immutable_other_pending_preserved: true,
          persisted_after_reload: true,
          completed_replay_status: replay.status(),
          another_agent_denied_status: denied.status(),
          actual_dark: dark,
          contrast_ratio: contrast.ratio,
          mutations,
          prohibited_mutations_or_external_calls: prohibited,
          page_errors: errors,
          screenshots,
          whole_figure10_or_Part1_accepted: false,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
