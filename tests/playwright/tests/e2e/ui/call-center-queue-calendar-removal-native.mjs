import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

// Prepared only: actual execution requires the reviewed typed native removal endpoint and UI.
export async function verifyNativeQueueCalendarRemoval(
  page,
  info,
  target,
  calendarId,
  screenshot
) {
  const base = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const headers = target.scoped;
  const unit = String(target.allowed_unit_id);
  const queueId = String(target.queue_id);
  const bindingUrl = `${base}/queue_calendars/${queueId}`;
  const browserUrl = page.url();
  const dialog = page.getByRole('dialog');
  const calendarBefore = await page.request.get(
    `${base}/unit_calendars/${calendarId}?unit_id=${unit}`,
    { headers }
  );
  expect(calendarBefore.status()).toBe(200);
  const calendar = await calendarBefore.json();
  const read = await page.request.get(`${bindingUrl}?unit_id=${unit}`, {
    headers,
  });
  expect(read.status()).toBe(200);
  const old = (await read.json()).binding;
  expect(old.calendar_snapshot.id).toBe(calendarId);
  await page.locator(`[data-queue-calendar-bindings="${calendarId}"]`).click();
  await dialog
    .locator('[data-calendar-queue-search]')
    .fill('concurrently reviewed queue');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog.locator(`[data-review-queue-calendar="${queueId}"]`).click();
  await dialog.locator('[data-review-calendar-removal]').click();
  await expect(dialog.locator('[data-submit-calendar-removal]')).toBeDisabled();
  await expect(dialog.locator('[data-save-queue-calendar]')).toBeDisabled();
  await dialog.locator('[data-confirm-calendar-removal]').check();
  const changed = await page.request.patch(`${base}/queues/${queueId}`, {
    headers,
    data: { queue: { name: 'SYNTHETIC removal conflict queue' } },
  });
  expect(changed.status()).toBe(200);
  const staleResponse = page.waitForResponse(response =>
    isBrowserApiResponse(response, browserUrl, bindingUrl, 'DELETE')
  );
  await dialog.locator('[data-submit-calendar-removal]').click();
  expect((await staleResponse).status()).toBe(409);
  await expect(dialog.locator('[data-reload-calendar-removal]')).toBeVisible();
  await dialog.locator('[data-calendar-removal]').scrollIntoViewIfNeeded();
  await screenshot('removal-conflict');
  await dialog.locator('[data-reload-calendar-removal]').click();
  await expect(dialog.locator('[data-review-calendar-removal]')).toBeVisible();
  await dialog.locator('[data-calendar-queue-search]').fill('');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await dialog.locator('[data-calendar-link-filter="linked"]').click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog.locator(`[data-review-queue-calendar="${queueId}"]`).click();
  await dialog.locator('[data-review-calendar-removal]').click();
  await expect(
    dialog.locator('[data-confirm-calendar-removal]')
  ).not.toBeChecked();
  await dialog.locator('[data-confirm-calendar-removal]').check();
  const removeResponse = page.waitForResponse(response =>
    isBrowserApiResponse(response, browserUrl, bindingUrl, 'DELETE')
  );
  await dialog.locator('[data-submit-calendar-removal]').click();
  const removed = await removeResponse;
  expect(removed.status()).toBe(200);
  const request = removed.request().postDataJSON();
  const receipt = await removed.json();
  expect(receipt).toMatchObject({
    account_id: String(target.account_id),
    unit_id: unit,
    queue_id: queueId,
    removed_binding_id: old.id,
    removed_calendar_digest: old.calendar_digest,
    historical_receipt: true,
    idempotency_key: request.idempotency_key,
    local_only: true,
    pabx_confirmed: false,
    external_impact: 'unknown',
  });
  expect(receipt.audit_id).toMatch(/^[1-9][0-9]*$/);
  await expect(dialog.locator('[data-calendar-removal-current]')).toContainText(
    'Sem vínculo interno de calendário'
  );
  await dialog
    .locator('[data-calendar-removal-receipt]')
    .scrollIntoViewIfNeeded();
  await screenshot('removal-confirmed');
  await dialog.locator('[data-finish-calendar-removal]').click();
  await expect(dialog.locator('[data-review-calendar-removal]')).toHaveCount(0);
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(0);
  await expect(dialog).toContainText('Nenhum vínculo interno de fila');
  await dialog.locator('[data-calendar-link-tabs]').scrollIntoViewIfNeeded();
  await screenshot('linked-after-removal');
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  const replay = await page.request.delete(bindingUrl, {
    headers,
    data: request,
  });
  expect(replay.status()).toBe(200);
  expect(await replay.json()).toEqual(receipt);
  const unbound = await page.request.get(`${bindingUrl}?unit_id=${unit}`, {
    headers,
  });
  expect(unbound.status()).toBe(200);
  const empty = await unbound.json();
  expect(empty.binding).toBeNull();
  const source = await page.request.get(
    `${base}/unit_calendars/${calendarId}?unit_id=${unit}`,
    { headers }
  );
  expect(source.status()).toBe(200);
  expect((await source.json()).item).toEqual(calendar.item);
  const rebind = await page.request.patch(bindingUrl, {
    headers,
    data: {
      unit_id: unit,
      queue_id: queueId,
      calendar_id: calendarId,
      calendar_revision: calendar.revision,
      queue_revision: empty.queue_revision,
      idempotency_key: randomUUID(),
      reviewed: true,
    },
  });
  expect(rebind.status()).toBe(200);
  const newer = await rebind.json();
  expect(newer.binding.id).not.toBe(old.id);
  const lateReplay = await page.request.delete(bindingUrl, {
    headers,
    data: request,
  });
  expect(lateReplay.status()).toBe(200);
  expect(await lateReplay.json()).toEqual(receipt);
  const finalRead = await page.request.get(`${bindingUrl}?unit_id=${unit}`, {
    headers,
  });
  expect(finalRead.status()).toBe(200);
  const final = await finalRead.json();
  expect(final.binding).toEqual(newer.binding);
  expect(final.queue_revision).toBe(newer.queue_revision);
  const denied = await page.request.delete(bindingUrl, {
    headers: target.observer,
    data: request,
  });
  expect(denied.status()).toBe(401);
  const hidden = await page.request.delete(bindingUrl, {
    headers,
    data: { ...request, unit_id: String(target.denied_unit_id) },
  });
  expect(hidden.status()).toBe(404);
  await page.locator(`[data-queue-calendar-bindings="${calendarId}"]`).click();
  await dialog
    .locator('[data-calendar-queue-search]')
    .fill('removal conflict queue');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await dialog.locator(`[data-review-queue-calendar="${queueId}"]`).click();
  await expect(dialog.locator('[data-calendar-queue-review]')).toContainText(
    newer.binding.calendar_snapshot.definition.name
  );
  await dialog.locator('[data-calendar-queue-review]').scrollIntoViewIfNeeded();
  await screenshot('removal-newer-binding-preserved');
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-queue-calendar-removal-native.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        synthetic: true,
        external_homologation: false,
        account_id: String(target.account_id),
        unit_id: unit,
        queue_id: queueId,
        calendar_id: calendarId,
        stale_status: 409,
        removal_status: 200,
        linked_inventory_ui_empty_after_confirmed_removal: true,
        replay_status: 200,
        rebind_status: 200,
        late_replay_status: 200,
        denials: [401, 404],
        old_binding: old,
        request_body: request,
        receipt,
        unbound: empty,
        newer,
        final,
      },
      null,
      2
    )
  );
}
