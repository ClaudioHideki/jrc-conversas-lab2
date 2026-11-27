import { proveOwnedMediaFailure } from './call-center-owned-media-failure.mjs';
import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureLocatorTextContrast as measureTextContrast } from './call-center-text-contrast.mjs';

// Extend the same four native quality cases, using existing authenticated call and customer-master APIs.
export async function verifyNativeRecordingContext(
  page,
  listener,
  info,
  target,
  capture
) {
  await page
    .locator('[data-quality-review]')
    .getByRole('button', { name: 'Cancelar', exact: true })
    .click();
  const fetched = page.waitForResponse(response =>
    new URL(response.url()).pathname.startsWith(
      `/api/v1/accounts/${target.account_id}/jrc_contact_center/call_sessions/`
    )
  );
  await page.locator('[data-recording-context-open]').click();
  const response = await fetched;
  expect(response.status()).toBe(200);
  const context = await response.json();
  expect(String(context.account_id)).toBe(String(target.account_id));
  expect(context.item.external_session_id).toBe(
    target.recordings.allowed.call_id
  );
  expect(context.item.customer.status).toBe('identified');
  expect(context.item.customer.identity_source).toBe('call_contact_link');
  expect(context.item.customer.ambiguous).toBe(false);
  expect(context.item.customer.contacts).toHaveLength(1);
  expect(context.item.customer.directory.contact_id).toBe(
    String(context.item.contact_id)
  );
  const panel = page.locator('[data-recording-call-context]');
  await expect(panel.locator('[data-recording-context-contact]')).toHaveText(
    'SYNTHETIC linked recording customer'
  );
  await expect(panel.locator('[data-recording-context-company]')).toHaveText(
    context.item.customer.contacts[0].company.name
  );
  const contrast = await measureTextContrast(
    panel.locator('[data-recording-context-contact]')
  );
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await panel.scrollIntoViewIfNeeded();
  await capture(page, 'native-call-context');
  await panel.locator('[data-open-linked-master]').click();
  const master = page.getByRole('dialog').last();
  await expect(
    master.getByRole('heading', {
      name: 'SYNTHETIC linked recording customer',
      exact: true,
    })
  ).toBeVisible();
  await capture(page, 'existing-native-customer-master');
  await master.press('Escape');
  const historyButton = panel.locator('[data-open-linked-history]');
  await expect(historyButton).toBeVisible();
  const historyContrast = await measureTextContrast(historyButton);
  expect(historyContrast.ratio).toBeGreaterThanOrEqual(4.5);
  const timelinePath = `/api/v1/accounts/${target.account_id}/customers/contacts/${context.item.contact_id}/timeline`;
  const timelineResponse = page.waitForResponse(
    item =>
      item.request().method() === 'GET' &&
      new URL(item.url()).pathname === timelinePath
  );
  await historyButton.click();
  const nativeHistoryResponse = await timelineResponse;
  expect(nativeHistoryResponse.status()).toBe(200);
  const nativeHistory = await nativeHistoryResponse.json();
  expect(Array.isArray(nativeHistory.payload)).toBe(true);
  const nativeHistoryPanel = page.locator('[data-native-contact-history]');
  await expect(nativeHistoryPanel).toBeVisible();
  await expect(nativeHistoryPanel.locator('ol > li')).toHaveCount(
    nativeHistory.payload.length
  );
  await capture(page, 'existing-native-customer-history');
  await page.getByRole('dialog').last().press('Escape');
  await expect(panel).toBeVisible();

  // Real browser resource failure, not an intercepted API or a manufactured error event.
  // This proves local media/transcript independence, never external PABX availability.
  const mediaFailure = await listener
    .locator('[data-recording-selected] audio')
    .evaluate(proveOwnedMediaFailure);
  expect(Number.isInteger(mediaFailure.code)).toBe(true);
  expect(mediaFailure.code).toBeGreaterThan(0);
  expect(mediaFailure.trusted_browser_event).toBe(true);
  expect(mediaFailure.actual_authorized_audio_bytes).toBeGreaterThan(0);
  expect(mediaFailure.revoked_before_first_load).toBe(true);
  await expect(listener.locator('[data-recording-selected] audio')).toHaveCount(
    0
  );
  await expect(
    listener.locator('[data-recording-selected] > [role="alert"]')
  ).toBeVisible();
  await expect(listener.locator('[data-transcript-text]')).toHaveText(
    'SYNTHETIC original transcript never changed'
  );
  await capture(listener, 'transcript-after-real-media-resource-failure');
  const reads = [];
  listener.on('request', request => {
    if (new URL(request.url()).pathname.includes('/call_sessions/'))
      reads.push(request.url());
  });
  await listener.locator('[data-recording-context-open]').click();
  const denied = listener.locator('[data-recording-call-context]');
  await expect(denied.getByRole('alert')).toContainText('não está autorizado');
  await expect(denied.locator('[data-open-linked-master]')).toHaveCount(0);
  await expect(denied.locator('[data-open-linked-history]')).toHaveCount(0);
  await expect(denied).not.toContainText('SYNTHETIC linked recording customer');
  expect(reads).toEqual([]);
  await capture(listener, 'native-call-context-restricted');
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-recording-context-native.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: String(target.account_id),
        recording_id: target.recordings.allowed.id,
        synthetic: true,
        context,
        contrast,
        actual_dark_theme: await page.evaluate(() =>
          document.documentElement.classList.contains('dark')
        ),
        reused_existing_call_API: true,
        explicit_native_call_contact_link_verified: true,
        native_directory_permission_separate_from_recording_listen: true,
        real_existing_master_dialog_loaded: true,
        native_full_history: {
          exact_account_and_contact_path: timelinePath,
          actual_native_GET: true,
          status: nativeHistoryResponse.status(),
          items: nativeHistory.payload.length,
          native_panel_items_match_response: true,
          no_new_customer_module_route_or_grant: true,
          contrast: historyContrast,
        },
        media_failure: mediaFailure,
        authorized_transcript_remained_visible_after_actual_blob_failure: true,
        listener_without_operate_received_no_customer_context: true,
        no_new_customer_module_or_provider_operation: true,
        screenshots: [
          'native-call-context',
          'existing-native-customer-master',
          'existing-native-customer-history',
          'transcript-after-real-media-resource-failure',
          'native-call-context-restricted',
        ].map(
          name =>
            `.codex/call-center-native-e2e/${info.project.name}-quality-${name}.png`
        ),
        complete_five_tab_composition_accepted: false,
        whole_figure21_accepted: false,
      },
      null,
      2
    )
  );
}
