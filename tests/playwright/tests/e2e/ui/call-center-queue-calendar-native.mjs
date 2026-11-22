import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { verifyNativeQueueCalendarRemoval } from './call-center-queue-calendar-removal-native.mjs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

// The caller owns this tab and its independent synthetic account. No intercepted or simulated API.
export async function verifyNativeQueueCalendarBindings(
  page,
  info,
  target,
  template,
  foreignUnit
) {
  const base = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const headers = target.scoped;
  const unit = String(target.allowed_unit_id);
  const originalUrl = page.url();
  const browserOrigin = new URL(originalUrl).origin;
  const sourceList = await page.request.get(
    `${base}/unit_calendars?unit_id=${unit}`,
    { headers }
  );
  expect(sourceList.status()).toBe(200);
  const identity = randomUUID();
  const entry = {
    ...template,
    id: identity,
    definition: {
      ...template.definition,
      name: `SYNTHETIC ${info.project.name} binding calendar`,
    },
  };
  const created = await page.request.post(`${base}/unit_calendars`, {
    headers,
    data: {
      unit_id: unit,
      calendar: entry,
      expected_revision: (await sourceList.json()).revision,
    },
  });
  expect(created.status()).toBe(201);
  for (let index = 0; index < 20; index += 1) {
    const result = await page.request.post(`${base}/queues`, {
      headers,
      data: {
        queue: {
          unit_id: unit,
          code: `SYNTHETIC-CALENDAR-${index}`,
          name: `SYNTHETIC queue calendar ${String(index).padStart(2, '0')}`,
        },
      },
    });
    expect(result.status()).toBe(201);
  }
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/hours?calendar_unit=${unit}&calendar_q=${encodeURIComponent(entry.definition.name)}`
  );
  expect(new URL(page.url()).origin).toBe(browserOrigin);
  await expect(page.locator('[data-unit-calendar-library]')).toBeVisible();
  await expect(
    page.locator(`[data-unit-calendar="${identity}"]`)
  ).toBeVisible();
  await page.locator(`[data-queue-calendar-bindings="${identity}"]`).click();
  const dialog = page.getByRole('dialog');
  await dialog.locator('[data-calendar-link-filter="linked"]').click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(0);
  await expect(dialog).toContainText('Nenhum vínculo interno de fila');
  const beforeLinks = await page.request.get(
    `${base}/queue_calendars?unit_id=${unit}&calendar_id=${identity}&binding_filter=linked`,
    { headers }
  );
  expect(beforeLinks.status()).toBe(200);
  const linkedBefore = await beforeLinks.json();
  expect(linkedBefore.meta.total).toBe(0);
  expect(linkedBefore.items).toEqual([]);
  await dialog.locator('[data-calendar-link-filter="all"]').click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(20);
  await dialog.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog.getByRole('button', { name: 'Anterior', exact: true }).click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(20);
  await dialog
    .locator('[data-calendar-queue-search]')
    .fill('SYNTHETIC IVR voice');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog
    .locator(`[data-review-queue-calendar="${target.queue_id}"]`)
    .click();
  await expect(dialog.locator('[data-calendar-queue-review]')).toBeVisible();
  await expect(dialog.locator('[data-save-queue-calendar]')).toBeDisabled();
  await dialog.locator('[data-confirm-queue-calendar]').check();
  const concurrent = await page.request.patch(
    `${base}/queues/${target.queue_id}`,
    {
      headers,
      data: { queue: { name: 'SYNTHETIC concurrently reviewed queue' } },
    }
  );
  expect(concurrent.status()).toBe(200);
  const bindingUrl = `${base}/queue_calendars/${target.queue_id}`;
  const observed = [];
  const matchesMutation = response => {
    const url = new URL(response.url());
    if (url.pathname === new URL(bindingUrl).pathname && observed.length < 20) {
      observed.push({
        origin: url.origin,
        path: url.pathname,
        method: response.request().method(),
        status: response.status(),
      });
      fs.writeFileSync(
        `.codex/call-center-native-e2e/${info.project.name}-queue-calendar-observed.json`,
        JSON.stringify(
          {
            sha: process.env.GITHUB_SHA,
            browser_origin: browserOrigin,
            observed,
          },
          null,
          2
        )
      );
    }
    return isBrowserApiResponse(response, originalUrl, bindingUrl, 'PATCH');
  };
  const conflictResult = page.waitForResponse(matchesMutation);
  await dialog.locator('[data-save-queue-calendar]').click();
  expect((await conflictResult).status()).toBe(409);
  await expect(dialog.locator('[data-reload-queue-calendar]')).toBeVisible();
  const screenshot = async name => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    const box = await dialog.boundingBox();
    const viewport = page.viewportSize();
    expect(
      Boolean(
        box &&
          viewport &&
          box.x >= 0 &&
          box.y >= 0 &&
          box.x + box.width <= viewport.width &&
          box.y + box.height <= viewport.height
      )
    ).toBe(true);
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-queue-calendar-${name}.png`,
      fullPage: false,
    });
  };
  await screenshot('conflict-review');
  await dialog.locator('[data-reload-queue-calendar]').click();
  await expect(
    dialog.locator('[data-confirm-queue-calendar]')
  ).not.toBeChecked();
  await expect(dialog.locator('[data-calendar-queue-review]')).toContainText(
    'SYNTHETIC concurrently reviewed queue'
  );
  await dialog.locator('[data-confirm-queue-calendar]').check();
  const acceptedResult = page.waitForResponse(matchesMutation);
  await dialog.locator('[data-save-queue-calendar]').click();
  const accepted = await acceptedResult;
  expect(accepted.status()).toBe(200);
  const receipt = await accepted.json();
  const requestBody = accepted.request().postDataJSON();
  expect(receipt).toMatchObject({
    unit_id: unit,
    queue_id: String(target.queue_id),
    calendar_changed: false,
    local_only: true,
    pabx_confirmed: false,
    external_impact: 'unknown',
  });
  expect(receipt.binding.calendar_snapshot).toEqual(entry);
  expect(receipt.binding.scope_snapshot).toMatchObject({
    account_id: String(target.account_id),
    unit_id: unit,
    queue_id: String(target.queue_id),
  });
  await expect(dialog.locator('[data-queue-calendar-confirmed]')).toContainText(
    'Aplicação no PABX não confirmada'
  );
  await expect(dialog.locator('[data-current-queue-calendar]')).toHaveText(
    entry.definition.name
  );
  await screenshot('confirmed');
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  const replay = await page.request.patch(bindingUrl, {
    headers,
    data: requestBody,
  });
  expect(replay.status()).toBe(200);
  expect(await replay.json()).toEqual(receipt);
  const current = await page.request.get(
    `${base}/unit_calendars/${identity}?unit_id=${unit}`,
    { headers }
  );
  expect(current.status()).toBe(200);
  const changed = {
    ...entry,
    definition: {
      ...entry.definition,
      description:
        'SYNTHETIC later catalog edit without changing the pinned queue snapshot',
    },
  };
  const edited = await page.request.patch(
    `${base}/unit_calendars/${identity}`,
    {
      headers,
      data: {
        unit_id: unit,
        calendar: changed,
        expected_revision: (await current.json()).revision,
      },
    }
  );
  expect(edited.status()).toBe(200);
  const persisted = await page.request.get(`${bindingUrl}?unit_id=${unit}`, {
    headers,
  });
  expect(persisted.status()).toBe(200);
  const final = await persisted.json();
  expect(final.binding).toEqual(receipt.binding);
  expect(final.calendar_changed).toBe(true);
  await page.reload();
  await page.locator(`[data-queue-calendar-bindings="${identity}"]`).click();
  await expect(
    dialog.locator(`[data-calendar-queue="${target.queue_id}"]`)
  ).toContainText('O calendário do catálogo mudou');
  await screenshot('pinned-after-source-edit');
  await dialog.locator('[data-calendar-link-filter="linked"]').click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await expect(
    dialog.locator(`[data-calendar-queue="${target.queue_id}"]`)
  ).toContainText('O calendário do catálogo mudou');
  await expect(dialog).toContainText(
    'Este painel consulta somente vínculos internos de filas autorizadas'
  );
  const afterLinks = await page.request.get(
    `${base}/queue_calendars?unit_id=${unit}&calendar_id=${identity}&binding_filter=linked`,
    { headers }
  );
  expect(afterLinks.status()).toBe(200);
  const linkedAfter = await afterLinks.json();
  expect(linkedAfter.meta).toMatchObject({ total: 1, pages: 1, page: 1 });
  expect(linkedAfter.items.map(row => row.queue_id)).toEqual([
    String(target.queue_id),
  ]);
  expect(linkedAfter.items[0].binding).toEqual(receipt.binding);
  await dialog.locator('[data-calendar-link-tabs]').scrollIntoViewIfNeeded();
  await screenshot('linked-inventory');
  await dialog
    .locator('[data-calendar-queue-search]')
    .fill('SYNTHETIC no matching linked queue');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(0);
  await expect(dialog).toContainText('Nenhum vínculo interno de fila');
  await dialog
    .locator('[data-calendar-queue-search]')
    .fill('concurrently reviewed');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog.locator('[data-calendar-queue-search]').fill('');
  await dialog
    .getByRole('button', { name: 'Aplicar pesquisa', exact: true })
    .click();
  await expect(dialog.locator('[data-calendar-queue]')).toHaveCount(1);
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  const denials = [];
  for (const value of [target.denied_unit_id, foreignUnit]) {
    const response = await page.request.get(`${bindingUrl}?unit_id=${value}`, {
      headers,
    });
    denials.push(response.status());
  }
  const denied = await page.request.get(`${bindingUrl}?unit_id=${unit}`, {
    headers: target.observer,
  });
  denials.push(denied.status());
  expect(denials).toEqual([404, 404, 401]);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-queue-calendar-native.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        synthetic: true,
        external_homologation: false,
        account_id: target.account_id,
        unit_id: unit,
        queue_id: String(target.queue_id),
        calendar_id: identity,
        create_status: 201,
        conflict_status: 409,
        bind_status: 200,
        replay_status: 200,
        source_edit_status: 200,
        initial_queue_total: 21,
        linked_inventory: {
          before: linkedBefore,
          after: linkedAfter,
          ui_search_counts: [0, 1, 1],
        },
        ui_pages: [1, 2, 1],
        receipt,
        final,
        denials,
        request_body: requestBody,
      },
      null,
      2
    )
  );
  await verifyNativeQueueCalendarRemoval(
    page,
    info,
    target,
    identity,
    screenshot
  );
  await page.goto(originalUrl);
  await expect(
    page.locator(`[data-unit-calendar="${template.id}"]`)
  ).toBeVisible();
}
