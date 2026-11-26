import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Native UI -> authenticated HTTP -> own Redis -> actual Sidekiq -> native
// Project command. No intercepted success or direct invocation of a job.
export async function verifyPublicEndingExecution(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}`;
  const qualification = `${root}/jrc_contact_center/qualifications/${target.qualification_id}`;
  const history = `${qualification}/ending_attempts`;
  const dark = info.project.name.endsWith('dark');
  const errors = [];
  const prohibited = [];
  const writes = [];
  const screenshots = [];
  const contrasts = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    const writing = !['GET', 'HEAD'].includes(request.method());
    const own =
      url.pathname === new URL(qualification).pathname ||
      url.pathname.startsWith(new URL(qualification).pathname + '/');
    if (outside || (writing && !own)) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    if (writing)
      writes.push({
        path: url.pathname,
        method: request.method(),
        body: request.postDataJSON(),
      });
    return route.continue();
  });
  await page.addInitScript(
    ({ auth, isDark }) => {
      Reflect.set(window, '__SYNTHETIC_AUTH__', auth);
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: target.operator, isDark: dark }
  );
  const read = async () => {
    const response = await page.request.get(history, {
      headers: target.operator,
      params: { history_contract: 2 },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.contract_version).toBe(2);
    expect(body.account_id).toBe(account);
    expect(body.qualification_id).toBe(String(target.qualification_id));
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
  const attendance = async () => {
    const response = await page.request.get(
      `${root}/jrc_contact_center/qualifications`,
      {
        headers: target.operator,
        params: { call_session_id: target.call_session_id },
      }
    );
    expect(response.status()).toBe(200);
    return (await response.json()).items.find(
      row => String(row.id) === String(target.qualification_id)
    );
  };
  const capture = async suffix => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    expect(
      await page
        .locator('html')
        .evaluate(node => node.classList.contains('dark'))
    ).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-public-${suffix}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
  };
  const nativeRunner = script => {
    const path = fs.readFileSync(
      '/tmp/call-center-public-ending-control-path.txt',
      'utf8'
    );
    expect(path).toMatch(/^\/tmp\/jrc-cc-public-ending-[0-9a-f]{24}\.private$/);
    return execFileSync(
      'bundle',
      ['exec', 'rails', 'runner', script, account],
      {
        cwd: process.env.GITHUB_WORKSPACE,
        env: { ...process.env, JRC_CC_PUBLIC_QUEUE_CONTROL: path },
        timeout: 45000,
        maxBuffer: 512 * 1024,
        encoding: 'utf8',
      }
    );
  };
  const reviewAndSubmit = async button => {
    await button.click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    const submit = dialog.locator('[data-run-selected-ending-pending]');
    await expect(submit).toBeDisabled();
    const [contrast] = await dialog
      .locator('[data-ending-pending-review] > p.font-semibold')
      .evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    contrasts.push(contrast);
    await capture(
      'explicit-review-' +
        writes.filter(row => row.path.includes('ending_destination')).length
    );
    await dialog.locator('[data-ending-pending-confirmed]').check();
    const acknowledgement = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname.startsWith(
          new URL(qualification).pathname + '/ending_destinations'
        )
    );
    await submit.click();
    expect((await acknowledgement).status()).toBe(202);
    await expect(dialog).toBeHidden();
  };
  try {
    const profileResponse = await page.request.get(
      'http://127.0.0.1:5387/api/v1/profile',
      { headers: target.operator }
    );
    expect(profileResponse.status()).toBe(200);
    const profile = await profileResponse.json();
    expect(String(profile.id)).toBe(String(target.original_operator_user_id));
    const membership = profile.accounts.find(row => String(row.id) === account);
    expect(membership.role).toBe('agent');
    expect(membership.permissions).not.toContain(
      'jrc_contact_center_configure'
    );
    expect(await taskTotal()).toBe(0);
    expect(await read()).toEqual([]);
    await page.goto(
      `/app/accounts/${account}/synthetic-hoya-acw/${target.call_session_id}`
    );
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    const form = page.locator('[data-pending-qualification-form]:visible');
    await form
      .locator('[data-qualification-field="reason"]')
      .selectOption(target.ending_reason_code);
    await form.locator('[data-confirm-ending-reason]').click();
    const classified = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname ===
          new URL(qualification).pathname + '/confirm_reason'
    );
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Confirmar motivo', exact: true })
      .click();
    expect((await classified).status()).toBe(200);
    await expect(form.locator('[data-ending-reason-confirmed]')).toBeVisible();
    expect((await attendance()).completed_at).toBeNull();
    expect(await taskTotal()).toBe(0);
    const panel = page.locator('[data-ending-attempt-history]:visible');
    await panel.locator('[data-open-ending-attempt-history]').click();
    const manual = panel
      .locator('[data-manual-ending-actions] article')
      .filter({ hasText: target.manual_rule_code });
    await expect(manual).toBeVisible();
    const preview = await page.request.get(
      `${qualification}/ending_destinations`,
      {
        headers: target.operator,
      }
    );
    expect(preview.status()).toBe(200);
    const choice = (await preview.json()).items.find(
      row => row.rule_code === target.manual_rule_code
    );
    expect(choice).toBeTruthy();
    const denied = await page.request.post(
      `${qualification}/ending_destinations`,
      {
        headers: target.administrator,
        data: {
          origin_id: choice.origin_id,
          rule_code: choice.rule_code,
          destination_kind: choice.destination_kind,
          request_key: randomUUID(),
          review: {
            confirmed: true,
            expected_readiness_id: choice.readiness_id,
            expected_version_id: choice.version_id,
            expected_rule_sha256: choice.rule_sha256,
          },
        },
      }
    );
    expect([401, 403, 404]).toContain(denied.status());
    expect(await taskTotal()).toBe(0);
    expect(await read()).toEqual([]);
    await capture('classified-without-consent');
    await reviewAndSubmit(manual.locator('[data-review-manual-ending-action]'));
    await expect
      .poll(async () => (await read()).map(row => row.outcome))
      .toEqual(['failed']);
    expect(await taskTotal()).toBe(0);
    expect((await attendance()).completed_at).toBeNull();
    await panel.locator('[data-refresh-ending-attempts]').click();
    const failed = panel
      .locator('[data-ending-attempt-row]')
      .filter({ hasText: target.manual_rule_code });
    await expect(
      failed.locator('[data-retry-selected-ending-destination]')
    ).toBeVisible();
    await capture('real-failure-rollback');
    const beforeRetry = await read();
    nativeRunner('script/jrc_call_center_ending_public_release_fault.rb');
    await reviewAndSubmit(
      failed.locator('[data-retry-selected-ending-destination]')
    );
    await expect
      .poll(
        async () =>
          (await read()).filter(row => row.outcome === 'succeeded').length
      )
      .toBe(1);
    expect(await taskTotal()).toBe(1);
    const retried = await read();
    const immutableOutcome = ({
      id,
      request_id,
      version_id,
      rule_code,
      outcome,
      result_code,
      execution_id,
      finished_at,
    }) => ({
      id,
      request_id,
      version_id,
      rule_code,
      outcome,
      result_code,
      execution_id,
      finished_at,
    });
    expect(
      immutableOutcome(retried.find(row => row.id === beforeRetry[0].id))
    ).toEqual(immutableOutcome(beforeRetry[0]));
    expect((await attendance()).completed_at).toBeNull();
    await panel.locator('[data-refresh-ending-attempts]').click();
    await capture('selected-retry-only');
    await form
      .locator('[data-qualification-field="result"]')
      .selectOption('completed');
    const completed = page.waitForResponse(
      response =>
        response.request().method() === 'PATCH' &&
        new URL(response.url()).pathname === new URL(qualification).pathname
    );
    await form.locator('[data-complete-qualification]').click();
    expect((await completed).status()).toBe(200);
    await expect
      .poll(
        async () =>
          (await read()).filter(row => row.outcome === 'succeeded').length
      )
      .toBe(2);
    expect(await taskTotal()).toBe(2);
    expect((await attendance()).completed_at).toBeTruthy();
    const final = await read();
    expect(final).toHaveLength(3);
    expect(
      immutableOutcome(final.find(row => row.id === beforeRetry[0].id))
    ).toEqual(immutableOutcome(beforeRetry[0]));
    await page.reload();
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    await page.locator('[data-open-ending-attempt-history]:visible').click();
    await expect(page.locator('[data-ending-attempt-row]:visible')).toHaveCount(
      3
    );
    expect(await taskTotal()).toBe(2);
    expect(await read()).toEqual(final);
    await capture('durable-reload');
    const raw = nativeRunner(
      'script/jrc_call_center_ending_public_evidence.rb'
    );
    const receipt = JSON.parse(raw.trim().split('\n').at(-1));
    expect(receipt.source_sha).toBe(process.env.GITHUB_SHA);
    expect(receipt.account_id).toBe(Number(account));
    expect(receipt.native_task_count).toBe(2);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    const selectedCommands = writes.filter(row =>
      row.path.includes('/ending_destinations')
    );
    expect(selectedCommands).toHaveLength(2);
    expect(
      new Set(selectedCommands.map(row => row.body.request_key)).size
    ).toBe(2);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ending-public-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          synthetic: true,
          account_id: account,
          actual_dark_theme: await page
            .locator('html')
            .evaluate(node => node.classList.contains('dark')),
          horizontal_overflow_absent: await page.evaluate(
            () => document.documentElement.scrollWidth <= window.innerWidth
          ),
          contrasts,
          original_operator_nonadministrator: true,
          authenticated_profile_user_id: String(profile.id),
          authenticated_profile_role: membership.role,
          different_actor_denied_status: denied.status(),
          explicit_reason_and_separate_action_consent: true,
          actual_native_rollback_before_selected_retry: true,
          successful_ACW_automatic_destination: true,
          reload_preserved: true,
          real_worker: receipt,
          selected_commands: selectedCommands,
          screenshots,
          errors,
          prohibited,
          public_CRM_or_Service_Desk_flow_accepted: false,
          whole_figure10_accepted: false,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
