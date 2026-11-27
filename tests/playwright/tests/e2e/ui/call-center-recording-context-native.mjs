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
  // Real browser resource failure, not an intercepted API or a manufactured error event.
  // This proves local media/transcript independence, never external PABX availability.
  const mediaFailure = await listener
    .locator('[data-recording-selected] audio')
    .evaluate(audio => {
      const resource = audio.currentSrc;
      if (!resource.startsWith('blob:'))
        throw new Error('Expected the owned native media blob');
      return new Promise(resolve => {
        audio.addEventListener(
          'error',
          () =>
            resolve({
              source: 'revoked_owned_browser_blob',
              code: audio.error?.code,
            }),
          { once: true }
        );
        URL.revokeObjectURL(resource);
        audio.load();
      });
    });
  expect(Number.isInteger(mediaFailure.code)).toBe(true);
  expect(mediaFailure.code).toBeGreaterThan(0);
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
        media_failure: mediaFailure,
        authorized_transcript_remained_visible_after_actual_blob_failure: true,
        listener_without_operate_received_no_customer_context: true,
        no_new_customer_module_or_provider_operation: true,
        screenshots: [
          'native-call-context',
          'existing-native-customer-master',
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
