import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Reuse the real existing ending history UI/API. Synthetic source setup is not task-creation evidence.
export async function verifyNativeRecordingActions(
  parent,
  page,
  info,
  target,
  capture
) {
  const account = String(target.account_id);
  const source = target.ending_context;
  const unexpectedOperations = [];
  const observe = request => {
    const pathname = new URL(request.url()).pathname;
    if (
      pathname.startsWith(
        `/api/v1/accounts/${account}/jrc_contact_center/qualifications/`
      ) &&
      (/\/ending_destinations(?:\/|$)/.test(pathname) ||
        request.method() !== 'GET')
    ) {
      unexpectedOperations.push({ method: request.method(), pathname });
    }
  };
  page.on('request', observe);
  expect(source.recording_id).toBe(target.quality_history_record.id);
  const contextPath = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${source.recording_id}/ending_context`;
  const endpoint = `http://127.0.0.1:5387${contextPath}`;
  const denied = await parent.request.get(endpoint, { headers: target.scoped });
  expect(denied.status()).toBe(401);
  const deniedBody = await denied.json();
  expect(deniedBody.items).toBeUndefined();
  await page.locator('[data-recording-actions-open]').click();
  const panel = page.locator('[data-recording-ending-actions]');
  await expect(panel).toBeVisible();
  const requested = page.waitForResponse(
    response => new URL(response.url()).pathname === contextPath
  );
  await panel.locator('[data-recording-actions-load]').click();
  const response = await requested;
  expect(response.status()).toBe(200);
  const context = await response.json();
  expect(context.account_id).toBe(account);
  expect(context.recording_id).toBe(source.recording_id);
  expect(context.call_session_id).toBe(source.call_session_id);
  expect(context.call_id).toBe(source.call_id);
  expect(context.items).toEqual([
    {
      id: source.qualification_id,
      account_user_id: source.account_user_id,
      started_at: null,
      completed_at: null,
    },
  ]);
  expect(context.meta).toEqual({ page: 1, per_page: 20, total: 1, pages: 1 });
  const selected = panel.locator(
    `[data-recording-actions-select="${source.qualification_id}"]`
  );
  await selected.click();
  const history = panel.locator('[data-ending-attempt-history]');
  const historyPath = `/api/v1/accounts/${account}/jrc_contact_center/qualifications/${source.qualification_id}/ending_attempts`;
  const historyRequest = page.waitForResponse(
    result => new URL(result.url()).pathname === historyPath
  );
  await history.locator('[data-open-ending-attempt-history]').click();
  const historyResponse = await historyRequest;
  expect(historyResponse.status()).toBe(200);
  const receipt = await historyResponse.json();
  expect(receipt.contract_version).toBe(2);
  expect(receipt.call_session_id).toBe(source.call_session_id);
  expect(receipt.items).toEqual([]);
  expect(receipt.meta.total).toBe(0);
  await expect(history.locator('[data-ending-attempt-target]')).toHaveCount(0);
  await expect(history.locator('[data-manual-ending-actions]')).toHaveCount(0);
  await expect(
    history.locator('[data-review-selected-ending-pending]')
  ).toHaveCount(0);
  const contrast = await measureLocatorTextContrast(panel.locator('h3'));
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await panel.scrollIntoViewIfNeeded();
  await capture(page, 'existing-native-ending-controls');
  await page.reload();
  await expect(page.locator('[data-recording-row]')).toHaveCount(1);
  await page.locator('[data-recording-details]').click();
  await page.locator('[data-recording-actions-open]').click();
  const reloaded = page.locator('[data-recording-ending-actions]');
  const refresh = page.waitForResponse(
    result => new URL(result.url()).pathname === contextPath
  );
  await reloaded.locator('[data-recording-actions-load]').click();
  expect(await (await refresh).json()).toEqual(context);
  await reloaded.scrollIntoViewIfNeeded();
  await capture(page, 'existing-native-ending-context-reloaded');
  const raw = execFileSync(
    'bundle',
    [
      'exec',
      'rails',
      'runner',
      'script/jrc_call_center_recording_actions_evidence.rb',
      account,
      source.recording_id,
      source.qualification_id,
    ],
    {
      cwd: process.env.GITHUB_WORKSPACE,
      env: process.env,
      timeout: 45000,
      maxBuffer: 64 * 1024,
      encoding: 'utf8',
    }
  );
  const native = JSON.parse(raw.trim().split('\n').at(-1));
  expect(native.source_sha).toBe(process.env.GITHUB_SHA);
  expect(native.qualification_id).toBe(source.qualification_id);
  expect(native.native_qualification_count).toBe(1);
  expect(native.started_at).toBeNull();
  expect(native.completed_at).toBeNull();
  expect(native.native_action_origin_count).toBe(0);
  expect(native.provider_command_count).toBe(0);
  page.off('request', observe);
  expect(unexpectedOperations).toEqual([]);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-recording-native-actions.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: account,
        synthetic: true,
        source,
        context,
        native,
        receipt,
        contrast,
        actual_dark_theme: await page.evaluate(() =>
          document.documentElement.classList.contains('dark')
        ),
        existing_controls_and_current_native_policies_reused: true,
        reading_did_not_start_or_complete_ACW_or_create_actions: true,
        read_only_native_receipt_widget: true,
        unexpectedOperations,
        no_new_task_creation_or_full_figure22_acceptance_claimed: true,
        screenshots: [
          'existing-native-ending-controls',
          'existing-native-ending-context-reloaded',
        ].map(
          name =>
            `.codex/call-center-native-e2e/${info.project.name}-quality-${name}.png`
        ),
      },
      null,
      2
    )
  );
}
