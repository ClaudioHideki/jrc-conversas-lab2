import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

// A separate owned tab and existing synthetic per-project account. No intercepted or fabricated API response.
export async function verifyNativeIvrCalendar(
  parent,
  info,
  target,
  foreignUnit
) {
  const page = await parent.context().newPage();
  const errors = [];
  const forbidden = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        request.url()
      )
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
  const base = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const headers = target.scoped;
  const unit = String(target.allowed_unit_id);
  const identity = randomUUID();
  const name = `SYNTHETIC ${info.project.name} immutable URA calendar`;
  const entry = {
    id: identity,
    active: true,
    definition: {
      name,
      description: 'SYNTHETIC calendar simulation; no live routing',
      timezone: 'America/Sao_Paulo',
      weekly: Object.fromEntries(
        [1, 2, 3, 4, 5, 6, 7].map(day => [
          String(day),
          day <= 5 ? [['08:00', '17:00']] : [],
        ])
      ),
      holidays: [
        {
          date: '2026-11-23',
          name: 'SYNTHETIC dated holiday',
          kind: 'internal',
          type: 'movable',
        },
      ],
      exceptions: [
        {
          date: '2026-11-23',
          name: 'SYNTHETIC explicit duty',
          intervals: [['10:00', '11:00']],
        },
      ],
    },
  };
  const getCatalog = async () => {
    const response = await page.request.get(
      `${base}/unit_calendars?unit_id=${unit}`,
      { headers }
    );
    expect(response.status()).toBe(200);
    return response.json();
  };
  const screenshot = async suffix => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    await expect(page.locator('html')).toHaveClass(
      info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
    );
    const bounds = await page.getByRole('dialog').boundingBox();
    const viewport = page.viewportSize();
    expect(
      bounds &&
        bounds.x >= 0 &&
        bounds.y >= 0 &&
        bounds.x + bounds.width <= viewport.width &&
        bounds.y + bounds.height <= viewport.height
    ).toBe(true);
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-ivr-calendar-${suffix}.png`,
      fullPage: false,
    });
  };
  const observe = (url, method) =>
    page.waitForResponse(response =>
      isBrowserApiResponse(response, page.url(), url, method)
    );
  try {
    const catalog = await getCatalog();
    const createdCalendar = await page.request.post(`${base}/unit_calendars`, {
      headers,
      data: {
        unit_id: unit,
        expected_revision: catalog.revision,
        calendar: entry,
      },
    });
    expect(createdCalendar.status()).toBe(201);
    const detail = await page.request.get(
      `${base}/unit_calendars/${identity}?unit_id=${unit}`,
      { headers }
    );
    expect(detail.status()).toBe(200);
    const pin = (await detail.json()).ivr_reference;
    expect(pin.snapshot).toEqual(entry);
    const location = `/app/accounts/${target.account_id}/contact-center/ura?ivr_q=${encodeURIComponent(name)}`;
    await page.goto(location);
    await page.locator('[data-ivr-new]').click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await dialog.locator('#ivr-name').fill(name);
    await dialog.locator('#ivr-unit').selectOption(unit);
    await dialog.locator('[data-ivr-add="calendar"]').click();
    await dialog.locator('[data-ivr-add="end"]').click();
    await dialog.locator('[data-ivr-add="end"]').click();
    await dialog.locator('#ivr-start').selectOption('node_1');
    await dialog.locator('[data-ivr-calendar-choose]').click();
    await dialog.locator('[data-ivr-calendar-search]').fill(name);
    await dialog
      .locator('[data-ivr-calendar-chooser]')
      .getByRole('button', { name: 'Buscar', exact: true })
      .click();
    await expect(dialog.locator('[data-ivr-calendar-row]')).toHaveCount(1);
    await dialog.locator(`[data-ivr-calendar-select="${identity}"]`).click();
    await expect(dialog.locator('[data-ivr-calendar-use]')).toBeDisabled();
    await dialog.locator('[data-ivr-calendar-confirm]').check();
    await dialog.locator('[data-ivr-calendar-use]').click();
    await expect(dialog.locator('[data-ivr-calendar-pinned]')).toContainText(
      name
    );
    await dialog.locator('#ivr-on_open-0').selectOption('node_2');
    await dialog.locator('#ivr-on_closed-0').selectOption('node_3');
    await dialog.locator('[data-ivr-calendar-pinned]').scrollIntoViewIfNeeded();
    await screenshot('reviewed');
    const saving = observe(`${base}/ivr_drafts`, 'POST');
    await dialog.locator('[data-ivr-save]').click();
    const saved = await saving;
    expect(saved.status()).toBe(201);
    const created = await saved.json();
    const originalRequest = saved.request().postDataJSON();
    await expect(dialog.locator('[data-ivr-saved]')).toBeVisible();
    const id = created.item.id;
    const originalGraph = created.item.definition;
    expect(originalGraph.schema_version).toBe(3);
    expect(originalGraph.nodes[0].calendar_reference).toEqual(pin);
    await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
    await expect(dialog).not.toBeVisible();
    const currentCatalog = await getCatalog();
    const edited = await page.request.patch(
      `${base}/unit_calendars/${identity}`,
      {
        headers,
        data: {
          unit_id: unit,
          expected_revision: currentCatalog.revision,
          calendar: {
            ...entry,
            definition: {
              ...entry.definition,
              name: `${name} SOURCE EDIT`,
              exceptions: [],
            },
          },
        },
      }
    );
    expect(edited.status()).toBe(200);
    await page.reload();
    await page.locator(`[data-ivr-draft="${id}"]`).getByRole('button').click();
    await expect(dialog.locator('[data-ivr-calendar-pinned]')).toContainText(
      name
    );
    await expect(
      dialog.locator('[data-ivr-calendar-pinned]')
    ).not.toContainText('SOURCE EDIT');
    await dialog.locator('[data-ivr-calendar-pinned]').scrollIntoViewIfNeeded();
    await screenshot('historical-pin');
    await dialog.getByRole('tab', { name: 'Simulação', exact: true }).click();
    await expect(dialog.locator('#ivr-simulation-local')).toHaveValue('');
    await dialog.locator('#ivr-simulation-local').fill('2026-11-23T10:30');
    await dialog
      .locator('#ivr-simulation-zone')
      .selectOption('America/Sao_Paulo');
    const openedRequest = observe(`${base}/ivr_drafts/preview`, 'POST');
    await dialog.locator('[data-ivr-simulate]').click();
    const opened = await openedRequest;
    expect(opened.status()).toBe(200);
    const openResult = (await opened.json()).simulation;
    expect(openResult.trace.at(-1).node_id).toBe('node_2');
    expect(openResult.trace[0].calendar).toMatchObject({
      sha256: pin.sha256,
      precedence: 'exception',
      open: true,
      instant: '2026-11-23T13:30:00Z',
      local_only: true,
      provider_applied: false,
    });
    await dialog
      .locator('[data-ivr-calendar-decision]')
      .scrollIntoViewIfNeeded();
    await screenshot('open');
    await dialog.locator('#ivr-simulation-local').fill('2026-11-23T11:00');
    await expect(dialog.locator('[data-ivr-simulation]')).toHaveCount(0);
    const closedRequest = observe(`${base}/ivr_drafts/preview`, 'POST');
    await dialog.locator('[data-ivr-simulate]').click();
    const closed = await closedRequest;
    expect(closed.status()).toBe(200);
    const closedResult = (await closed.json()).simulation;
    expect(closedResult.trace.at(-1).node_id).toBe('node_3');
    expect(closedResult.trace[0].calendar).toMatchObject({
      sha256: pin.sha256,
      precedence: 'exception',
      open: false,
    });
    await dialog
      .locator('[data-ivr-calendar-decision]')
      .scrollIntoViewIfNeeded();
    await screenshot('closed');
    const historical = await page.request.get(
      `${base}/ivr_drafts/${id}/versions/1`,
      { headers }
    );
    expect(historical.status()).toBe(200);
    expect((await historical.json()).item.definition).toEqual(originalGraph);
    const replay = await page.request.post(`${base}/ivr_drafts`, {
      headers,
      data: originalRequest,
    });
    expect(replay.status()).toBe(200);
    expect((await replay.json()).replayed).toBe(true);
    const unproven = await page.request.post(`${base}/ivr_drafts/preview`, {
      headers,
      data: {
        ivr_preview: {
          unit_id: unit,
          definition: originalGraph,
          dtmf: '',
          at: '2026-11-23T13:30:00Z',
        },
      },
    });
    expect(unproven.status()).toBe(409);
    expect((await unproven.json()).error).toBe('ivr_calendar_changed');
    const denials = [];
    for (const value of [target.denied_unit_id, foreignUnit]) {
      const response = await page.request.post(`${base}/ivr_drafts/preview`, {
        headers,
        data: {
          ivr_preview: {
            unit_id: String(value),
            definition: originalGraph,
            dtmf: '',
            at: '2026-11-23T13:30:00Z',
          },
        },
      });
      denials.push(response.status());
    }
    const denied = await page.request.post(
      `${base}/ivr_drafts/${id}/simulate`,
      {
        headers: target.observer,
        data: {
          ivr_simulation: { revision: 1, dtmf: '', at: '2026-11-23T13:30:00Z' },
        },
      }
    );
    denials.push(denied.status());
    expect(denials).toEqual([404, 404, 401]);
    expect(errors).toEqual([]);
    expect(forbidden).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ivr-calendar-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          external_homologation: false,
          account_id: target.account_id,
          unit_id: unit,
          draft_id: id,
          calendar_id: identity,
          exact_pin: pin,
          definition: originalGraph,
          create_status: saved.status(),
          source_edit_status: edited.status(),
          open_result: openResult,
          closed_result: closedResult,
          original_version_preserved: true,
          replay_status: replay.status(),
          unproven_status: unproven.status(),
          denials,
          provider_writes: forbidden,
          page_errors: errors,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
