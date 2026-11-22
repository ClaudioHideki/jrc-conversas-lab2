import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { verifyNativeQueueCalendarBindings } from './call-center-queue-calendar-native.mjs';

// Called inside the existing fifteen-card case. A dedicated synthetic account and owned tab
// preserve the other 61 scenarios and their authenticated native graphs.
export async function verifyNativeCalendars(parent, info, target, foreignUnit) {
  const page = await parent.context().newPage();
  const errors = [];
  const forbidden = [];
  let theme;
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        request.url()
      ) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      forbidden.push(new URL(request.url()).pathname);
  });
  await page.addInitScript(
    ({ auth, dark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', dark)
      );
    },
    { auth: target.scoped, dark: info.project.name.endsWith('dark') }
  );
  const api = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/unit_calendars`;
  const query = `unit_id=${target.allowed_unit_id}`;
  const headers = target.scoped;
  const prefix = `SYNTHETIC ${info.project.name} calendar`;
  const list = async () => {
    const response = await page.request.get(`${api}?${query}`, { headers });
    expect(response.status()).toBe(200);
    return response.json();
  };
  const screenshot = async name => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    const dialog = page.getByRole('dialog');
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
    await expect(page.locator('html')).toHaveClass(
      info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
    );
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-calendar-${name}.png`,
      fullPage: false,
    });
  };
  try {
    let catalog = await list();
    expect(catalog.meta.total).toBe(0);
    const definition = {
      name: '',
      description: 'SYNTHETIC internal calendar only',
      timezone: 'America/Sao_Paulo',
      weekly: Object.fromEntries(
        [1, 2, 3, 4, 5, 6, 7].map(day => [
          String(day),
          day <= 5
            ? [
                ['08:00', '12:00'],
                ['13:00', '17:00'],
              ]
            : [],
        ])
      ),
      holidays: [],
      exceptions: [],
    };
    for (let index = 0; index < 21; index += 1) {
      const response = await page.request.post(api, {
        headers,
        data: {
          unit_id: String(target.allowed_unit_id),
          expected_revision: catalog.revision,
          calendar: {
            id: randomUUID(),
            active: false,
            definition: {
              ...definition,
              name: `${prefix} ${String(index).padStart(2, '0')}`,
            },
          },
        },
      });
      expect(response.status()).toBe(201);
      catalog = await response.json();
    }
    const address = `/app/accounts/${target.account_id}/contact-center/control-desk/hours?calendar_unit=${target.allowed_unit_id}`;
    await page.goto(address);
    const library = page.locator('[data-unit-calendar-library]');
    await expect(library).toBeVisible();
    await expect(library.getByRole('navigation')).toContainText('Total 21');
    await library.locator('[data-calendar-next]').click();
    await expect(library.locator('[data-unit-calendar]')).toHaveCount(1);
    await expect(library.getByRole('navigation')).toContainText('Página 2');
    await library
      .getByRole('button', { name: 'Limpar filtros', exact: true })
      .click();
    await expect(library.locator('[data-unit-calendar]')).toHaveCount(20);
    await library.locator('[data-calendar-search]').fill('SYNTHETIC no match');
    await library
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    await expect(library.locator('[data-unit-calendar]')).toHaveCount(0);
    await library
      .getByRole('button', { name: 'Limpar filtros', exact: true })
      .click();
    await expect(library.locator('[data-unit-calendar]')).toHaveCount(20);
    await library.locator('[data-new-unit-calendar]').click();
    const dialog = page.getByRole('dialog');
    const save = dialog.locator('[data-save-unit-calendar]');
    await expect(save).toBeDisabled();
    await dialog
      .locator('[data-calendar-name]')
      .fill(`${prefix} created in UI`);
    await dialog.locator('[data-calendar-tab="weekly"]').click();
    const hours = dialog.locator('[data-calendar-weekday="1"] input');
    await hours.fill('08:00-12:00;11:00-17:00');
    await expect(dialog.getByRole('alert')).toContainText(
      'não podem se sobrepor'
    );
    await expect(save).toBeDisabled();
    await hours.fill('08:00-12:00;13:00-17:00');
    for (const day of ['2', '3', '4', '5'])
      await dialog
        .locator(`[data-calendar-weekday="${day}"] input`)
        .fill('08:00-12:00;13:00-17:00');
    await dialog.locator('[data-calendar-tab="holidays"]').click();
    for (const date of ['2026-11-23', '2026-11-24']) {
      await dialog.locator('[data-calendar-holiday-date]').fill(date);
      await dialog.locator('[data-add-calendar-holiday]').click();
      const holiday = dialog.locator(`[data-calendar-holiday="${date}"]`);
      await holiday
        .locator('[data-calendar-date-name]')
        .fill(`SYNTHETIC selected holiday ${date}`);
      await holiday
        .locator('[data-calendar-holiday-kind]')
        .selectOption('internal');
      await holiday
        .locator('[data-calendar-holiday-type]')
        .selectOption('movable');
    }
    await dialog.locator('[data-calendar-tab="exceptions"]').click();
    await dialog.locator('[data-calendar-exception-date]').fill('2026-11-23');
    await dialog.locator('[data-add-calendar-exception]').click();
    const exception = dialog.locator('[data-calendar-exception="2026-11-23"]');
    await exception
      .locator('[data-calendar-date-name]')
      .fill('SYNTHETIC explicit duty');
    await exception
      .getByLabel('Períodos da exceção', { exact: true })
      .fill('10:00-11:00');
    await dialog.locator('[data-review-unit-calendar]').check();
    await expect(save).toBeEnabled();
    theme = await dialog
      .locator('[data-calendar-date-name]')
      .evaluate(input => {
        const css = getComputedStyle(input);
        const pixel = value => {
          const canvas = document.createElement('canvas');
          canvas.width = 1;
          canvas.height = 1;
          const context = canvas.getContext('2d');
          context.fillStyle = value;
          context.fillRect(0, 0, 1, 1);
          return Array.from(context.getImageData(0, 0, 1, 1).data);
        };
        return {
          background: css.backgroundColor,
          foreground: css.color,
          bg: pixel(css.backgroundColor),
          fg: pixel(css.color),
        };
      });
    expect(theme.bg[3]).toBe(255);
    const brightness =
      theme.bg.slice(0, 3).reduce((sum, value) => sum + value, 0) / 765;
    expect(
      info.project.name.endsWith('dark') ? brightness < 0.5 : brightness > 0.5
    ).toBe(true);
    await screenshot('reviewed-exception');
    const createdResponse = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === new URL(api).pathname &&
        response.request().method() === 'POST'
    );
    await save.click();
    const created = await createdResponse;
    expect(created.status()).toBe(201);
    const receipt = await created.json();
    await expect(dialog).not.toBeVisible();
    await page.reload();
    await library
      .locator('[data-calendar-search]')
      .fill(`${prefix} created in UI`);
    await library
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    const item = library.locator(`[data-unit-calendar="${receipt.item.id}"]`);
    await expect(item).toBeVisible();
    await item.locator('[data-edit-unit-calendar]').click();
    await expect(dialog.locator('[data-calendar-name]')).toHaveValue(
      `${prefix} created in UI`
    );
    await dialog
      .locator('[data-calendar-name]')
      .fill(`${prefix} reviewed local edit`);
    const concurrent = {
      ...receipt.item,
      definition: {
        ...receipt.item.definition,
        name: `${prefix} concurrent committed`,
      },
    };
    const changed = await page.request.patch(`${api}/${receipt.item.id}`, {
      headers,
      data: {
        unit_id: String(target.allowed_unit_id),
        expected_revision: receipt.revision,
        calendar: concurrent,
      },
    });
    expect(changed.status()).toBe(200);
    await dialog.locator('[data-review-unit-calendar]').check();
    const staleResponse = page.waitForResponse(
      response =>
        new URL(response.url()).pathname ===
          `${new URL(api).pathname}/${receipt.item.id}` &&
        response.request().method() === 'PATCH'
    );
    await save.click();
    expect((await staleResponse).status()).toBe(409);
    await expect(dialog.locator('[data-calendar-name]').first()).toHaveValue(
      `${prefix} reviewed local edit`
    );
    await dialog.locator('[data-reload-calendar-revision]').click();
    const comparison = dialog.locator('[data-calendar-revision-conflict]');
    await expect(comparison.locator('[data-calendar-name]')).toHaveValue(
      `${prefix} concurrent committed`
    );
    await expect(save).toBeDisabled();
    await comparison.locator('[data-calendar-tab="weekly"]').click();
    await expect(
      comparison.locator('[data-calendar-weekday="1"] input')
    ).toBeDisabled();
    await expect(
      comparison.locator('[data-calendar-weekday="1"] input')
    ).toHaveValue('08:00-12:00;13:00-17:00');
    await screenshot('revision-comparison');
    await dialog.locator('[data-review-calendar-revision]').check();
    await dialog.locator('[data-review-unit-calendar]').check();
    const updatedResponse = page.waitForResponse(
      response =>
        new URL(response.url()).pathname ===
          `${new URL(api).pathname}/${receipt.item.id}` &&
        response.request().method() === 'PATCH'
    );
    await save.click();
    expect((await updatedResponse).status()).toBe(200);
    await expect(dialog).not.toBeVisible();
    await library
      .getByRole('button', { name: 'Limpar filtros', exact: true })
      .click();
    await library
      .locator('[data-calendar-search]')
      .fill(`${prefix} reviewed local edit`);
    await library
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    await expect(item).toBeVisible();
    await item.locator('[data-preview-unit-calendar]').click();
    const previews = [];
    for (const [date, precedence, seconds] of [
      ['2026-11-23', 'exception', 3600],
      ['2026-11-24', 'holiday', 0],
      ['2026-11-25', 'weekly', 28800],
    ]) {
      await dialog.locator('[data-calendar-preview-date]').fill(String(date));
      const calculated = page.waitForResponse(
        response =>
          new URL(response.url()).pathname ===
          `${new URL(api).pathname}/${receipt.item.id}/preview`
      );
      await dialog
        .getByRole('button', { name: 'Calcular prévia', exact: true })
        .click();
      const response = await calculated;
      expect(response.status()).toBe(200);
      const result = (await response.json()).preview;
      expect(result).toMatchObject({
        precedence,
        working_seconds: seconds,
        local_only: true,
        pabx_confirmed: false,
      });
      previews.push(result);
      await expect(
        dialog.locator('[data-calendar-preview-result]')
      ).toContainText(`${seconds} segundos`);
    }
    await screenshot('native-preview');
    await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
    const deniedUnit = await page.request.get(
      `${api}?unit_id=${target.denied_unit_id}`,
      { headers }
    );
    const deniedAccount = await page.request.get(
      `${api}?unit_id=${foreignUnit}`,
      { headers }
    );
    const deniedPermission = await page.request.get(`${api}?${query}`, {
      headers: target.observer,
    });
    expect([
      deniedUnit.status(),
      deniedAccount.status(),
      deniedPermission.status(),
    ]).toEqual([404, 404, 401]);
    const final = await page.request.get(`${api}/${receipt.item.id}?${query}`, {
      headers,
    });
    expect(final.status()).toBe(200);
    const stored = await final.json();
    expect(stored.item.definition.name).toBe(`${prefix} reviewed local edit`);
    expect(stored.item.definition.exceptions).toEqual(
      receipt.item.definition.exceptions
    );
    expect(errors).toEqual([]);
    expect(forbidden).toEqual([]);
    await verifyNativeQueueCalendarBindings(
      page,
      info,
      target,
      stored.item,
      foreignUnit
    );
    expect(errors).toEqual([]);
    expect(forbidden).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-calendar-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          external_homologation: false,
          account_id: target.account_id,
          unit_id: target.allowed_unit_id,
          calendar_id: receipt.item.id,
          create_status: 201,
          conflict_status: 409,
          update_status: 200,
          final: stored,
          previews,
          denials: [
            deniedUnit.status(),
            deniedAccount.status(),
            deniedPermission.status(),
          ],
          ui_pages: [1, 2, 1],
          initial_total: 21,
          theme_css: theme,
          page_errors: errors,
          provider_writes: forbidden,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
