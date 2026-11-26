import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Invoked only after the original Project flow saved its complete independent receipt.
// Uses its same four nonce-owned accounts, real Redis/Sidekiq and native destination services.
export async function verifyMixedNativeEnding(parent, info, target) {
  const account = String(target.account_id);
  const control = operation => {
    const filename = fs.readFileSync(
      '/tmp/call-center-public-ending-control-path.txt',
      'utf8'
    );
    expect(filename).toMatch(
      /^\/tmp\/jrc-cc-public-ending-[0-9a-f]{24}\.private$/
    );
    const raw = execFileSync(
      'bundle',
      [
        'exec',
        'rails',
        'runner',
        'script/jrc_call_center_mixed_ending_control.rb',
        account,
        operation,
      ],
      {
        cwd: process.env.GITHUB_WORKSPACE,
        env: { ...process.env, JRC_CC_PUBLIC_QUEUE_CONTROL: filename },
        encoding: 'utf8',
        timeout: 45000,
        maxBuffer: 1024 * 1024,
      }
    );
    return JSON.parse(raw.trim().split('\n').at(-1));
  };
  const prepared = control('prepare');
  expect(prepared.CRM_reuses_existing_unit_mapped_Lead).toBe(true);
  const page = await parent.context().newPage();
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}`;
  const qualification = `${root}/jrc_contact_center/qualifications/${prepared.qualification_id}`;
  const errors = [];
  const prohibited = [];
  const writes = [];
  const screenshots = [];
  const dark = info.project.name.endsWith('dark');
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const writing = !['GET', 'HEAD'].includes(request.method());
    const owned =
      url.pathname === new URL(qualification).pathname ||
      url.pathname.startsWith(new URL(qualification).pathname + '/');
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    if (outside || (writing && !owned)) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    if (writing)
      writes.push({
        method: request.method(),
        path: url.pathname,
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
  const history = async () => {
    const response = await page.request.get(
      `${qualification}/ending_attempts`,
      { headers: target.operator, params: { history_contract: 2 } }
    );
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.account_id).toBe(account);
    expect(body.qualification_id).toBe(String(prepared.qualification_id));
    expect(body.contract_version).toBe(2);
    return body.items.filter(row => row.rule_code === prepared.rule_code);
  };
  const capture = async suffix => {
    expect(
      await page
        .locator('html')
        .evaluate(node => node.classList.contains('dark'))
    ).toBe(dark);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-mixed-${suffix}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
  };
  const immutable = row =>
    Object.fromEntries(
      [
        'id',
        'request_id',
        'version_id',
        'rule_code',
        'outcome',
        'result_code',
        'execution_id',
        'finished_at',
        'destination_kind',
        'operation',
        'target',
      ].map(key => [key, row[key]])
    );
  try {
    const profile = await page.request.get(
      'http://127.0.0.1:5387/api/v1/profile',
      { headers: target.operator }
    );
    expect(profile.status()).toBe(200);
    const actor = await profile.json();
    const member = actor.accounts.find(row => String(row.id) === account);
    expect(member.role).toBe('agent');
    expect(member.permissions).not.toContain('jrc_contact_center_configure');
    await page.goto(
      `/app/accounts/${account}/synthetic-hoya-acw/${prepared.call_session_id}`
    );
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    const form = page.locator('[data-pending-qualification-form]:visible');
    await form
      .locator('[data-qualification-field="reason"]')
      .selectOption(prepared.reason_code);
    expect(await history()).toEqual([]);
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
    await expect
      .poll(
        async () => {
          const rows = await history();
          return (
            rows.length === 2 &&
            rows.some(
              row =>
                row.destination_kind === 'crm' && row.outcome === 'succeeded'
            ) &&
            rows.some(
              row =>
                row.destination_kind === 'service_desk' &&
                row.outcome === 'failed'
            )
          );
        },
        { timeout: 30000 }
      )
      .toBe(true);
    const first = await history();
    const succeeded = first.find(row => row.destination_kind === 'crm');
    const failed = first.find(row => row.destination_kind === 'service_desk');
    expect(succeeded.target).toBeTruthy();
    expect(failed.execution_id).toBeNull();
    const before = control('evidence');
    expect(before.existing_unit_mapped_Lead_unchanged).toBe(true);
    expect(before.native_lead_count).toBe(1);
    expect(before.native_ticket_count).toBe(0);
    expect(before.native_Project_task_count_preserved).toBe(2);
    expect(before.ACW_completed).toBe(false);
    const panel = page.locator('[data-ending-attempt-history]:visible');
    await panel.locator('[data-open-ending-attempt-history]').click();
    await expect(panel.locator('[data-ending-attempt-row]')).toHaveCount(2);
    await capture('independent-results');
    const restored = control('allow_selected_retry');
    expect(restored.own_failure_removed).toBe(true);
    expect(restored.business_records_changed).toBe(false);
    await panel.locator('[data-refresh-ending-attempts]').click();
    await panel.locator('[data-retry-selected-ending-destination]').click();
    const dialog = page.getByRole('dialog');
    const submit = dialog.locator('[data-run-selected-ending-pending]');
    await expect(submit).toBeDisabled();
    const [contrast] = await dialog
      .locator('[data-ending-pending-review] > p.font-semibold')
      .evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await capture('selected-SD-review');
    await dialog.locator('[data-ending-pending-confirmed]').check();
    const accepted = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname.startsWith(
          new URL(qualification).pathname + '/ending_destinations/'
        )
    );
    await submit.click();
    expect((await accepted).status()).toBe(202);
    await expect(dialog).toBeHidden();
    await expect
      .poll(
        async () => {
          const rows = await history();
          return (
            rows.length === 3 &&
            rows.filter(row => row.outcome === 'succeeded').length === 2
          );
        },
        { timeout: 30000 }
      )
      .toBe(true);
    const final = await history();
    expect(immutable(final.find(row => row.id === succeeded.id))).toEqual(
      immutable(succeeded)
    );
    expect(immutable(final.find(row => row.id === failed.id))).toEqual(
      immutable(failed)
    );
    const retried = final.find(
      row =>
        row.destination_kind === 'service_desk' && row.outcome === 'succeeded'
    );
    expect(retried.target).toBeTruthy();
    const commands = writes.filter(row =>
      row.path.includes('/ending_destinations/')
    );
    expect(commands).toHaveLength(1);
    expect(commands[0].body.destination_kind).toBeUndefined();
    expect(commands[0].path.endsWith(`/${failed.attempt_id}/retry`)).toBe(true);
    expect(commands[0].body.review.confirmed).toBe(true);
    expect(commands[0].body.review.expected_request_id).toBe(failed.request_id);
    await page.reload();
    await page.locator('[data-workspace-tab="CLOSING"]:visible').click();
    await page.locator('[data-open-ending-attempt-history]:visible').click();
    await expect(page.locator('[data-ending-attempt-row]:visible')).toHaveCount(
      3
    );
    expect(await history()).toEqual(final);
    await capture('durable-results');
    const receipt = control('evidence');
    expect(receipt.source_sha).toBe(process.env.GITHUB_SHA);
    expect(receipt.original_operator_user_id).toBe(actor.id);
    expect(receipt.original_actor_role).toBe('agent');
    expect(receipt.original_corporate_unit_scope_preserved).toBe(true);
    expect(receipt.existing_unit_mapped_Lead_unchanged).toBe(true);
    expect(receipt.native_lead_count).toBe(1);
    expect(receipt.native_ticket_count).toBe(1);
    expect(receipt.native_Project_task_count_preserved).toBe(2);
    expect(receipt.ACW_completed).toBe(false);
    const tickets = receipt.attempts.filter(
      row => row.destination_kind === 'service_desk'
    );
    expect(tickets).toHaveLength(2);
    expect(tickets[1].retry_of_id).toBe(tickets[0].id);
    expect(tickets[0].outcome).toBe('failed');
    expect(tickets[0].execution_id).toBeNull();
    expect(tickets[1].outcome).toBe('succeeded');
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ending-mixed-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          synthetic: true,
          account_id: account,
          actual_dark_theme: dark,
          contrast,
          explicit_reason_before_automatic_actions: true,
          original_operator_nonadministrator: true,
          current_native_permissions_and_unit_scope: true,
          CRM_reused_existing_unit_mapped_Lead: true,
          unscoped_new_Lead_creation_not_claimed: true,
          independent_CRM_success_and_native_SD_rollback: true,
          selected_SD_only_retry: true,
          successful_CRM_and_failed_SD_receipts_preserved: true,
          independent_open_ACW: true,
          before,
          final: receipt,
          commands,
          screenshots,
          errors,
          prohibited,
          whole_figure10_accepted: false,
          external_homologation: false,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
