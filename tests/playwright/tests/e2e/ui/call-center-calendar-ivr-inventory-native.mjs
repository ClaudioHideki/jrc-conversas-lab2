import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

// Own synthetic records and tab. No intercepted API, provider commands or inherited test evidence.
export async function verifyCalendarIvrInventory(
  parent,
  info,
  target,
  foreignUnit
) {
  const page = await parent.context().newPage();
  const unit = String(target.allowed_unit_id);
  const base = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const headers = target.scoped;
  const errors = [];
  const forbidden = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        request.url()
      )
    ) {
      forbidden.push(new URL(request.url()).pathname);
    }
  });
  await page.addInitScript(
    ({ auth, dark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', dark)
      );
    },
    { auth: headers, dark: info.project.name.endsWith('dark') }
  );
  const calendar = {
    id: randomUUID(),
    active: true,
    definition: {
      name: `SYNTHETIC ${info.project.name} usage inventory`,
      description: '',
      timezone: 'America/Sao_Paulo',
      weekly: Object.fromEntries(
        [1, 2, 3, 4, 5, 6, 7].map(day => [
          String(day),
          day === 1 ? [['08:00', '12:00']] : [],
        ])
      ),
      holidays: [],
      exceptions: [],
    },
  };
  const usagesPath = `${base}/unit_calendars/${calendar.id}/ivr_usages`;
  const observe = (filters = {}) => {
    const params = new URLSearchParams({
      q: '',
      status: 'all',
      page: '1',
      per_page: '10',
      ...filters,
      unit_id: unit,
    });
    return page.waitForResponse(response =>
      isBrowserApiResponse(
        response,
        page.url(),
        `${usagesPath}?${params}`,
        'GET'
      )
    );
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
      path: `.codex/call-center-native-e2e/${info.project.name}-calendar-ivr-inventory-${suffix}.png`,
    });
  };
  const dto = async response => {
    expect(response.status()).toBe(200);
    const result = await response.json();
    expect(result).toMatchObject({
      account_id: String(target.account_id),
      calendar_id: calendar.id,
      unit_id: unit,
      local_only: true,
      pabx_confirmed: false,
      coverage: 'current_local_ivr_drafts_only',
      provider_configuration_verified: false,
    });
    return result;
  };
  try {
    const before = await page.request.get(
      `${base}/unit_calendars?unit_id=${unit}`,
      { headers }
    );
    expect(before.status()).toBe(200);
    const created = await page.request.post(`${base}/unit_calendars`, {
      headers,
      data: {
        unit_id: unit,
        calendar,
        expected_revision: (await before.json()).revision,
      },
    });
    expect(created.status()).toBe(201);
    const detail = await page.request.get(
      `${base}/unit_calendars/${calendar.id}?unit_id=${unit}`,
      { headers }
    );
    expect(detail.status()).toBe(200);
    const pin = (await detail.json()).ivr_reference;
    const graph = {
      schema_version: 3,
      start: 'hours',
      nodes: [
        {
          id: 'hours',
          type: 'calendar',
          calendar_reference: pin,
          on_open: 'done',
          on_closed: 'done',
        },
        { id: 'done', type: 'end' },
      ],
    };
    const records = [];
    for (let index = 0; index < 12; index += 1) {
      const draft = {
        name: `SYNTHETIC ${info.project.name} usage ${String(index).padStart(2, '0')}`,
        unit_id: unit,
        status: 'draft',
        definition: graph,
        expected_revision: 0,
        request_id: randomUUID(),
      };
      const response = await page.request.post(`${base}/ivr_drafts`, {
        headers,
        data: { ivr_draft: draft },
      });
      expect(response.status()).toBe(201);
      records.push((await response.json()).item);
    }
    const current = await page.request.get(
      `${base}/unit_calendars?unit_id=${unit}`,
      { headers }
    );
    expect(current.status()).toBe(200);
    const editedName = `${calendar.definition.name} edited source`;
    const edited = await page.request.patch(
      `${base}/unit_calendars/${calendar.id}`,
      {
        headers,
        data: {
          unit_id: unit,
          calendar: {
            ...calendar,
            definition: { ...calendar.definition, name: editedName },
          },
          expected_revision: (await current.json()).revision,
        },
      }
    );
    expect(edited.status()).toBe(200);
    const location = `/app/accounts/${target.account_id}/contact-center/control-desk/hours?calendar_unit=${unit}&calendar_q=${encodeURIComponent(editedName)}`;
    const enter = async () => {
      await page.goto(location);
      const row = page.locator(`[data-unit-calendar="${calendar.id}"]`);
      await expect(row).toBeVisible();
      const request = observe();
      await row.locator('[data-calendar-ivr-usages-open]').click();
      return dto(await request);
    };
    const first = await enter();
    const dialog = page.getByRole('dialog');
    const rows = dialog.locator('[data-calendar-ivr-draft]');
    expect(first.meta).toEqual({ page: 1, per_page: 10, total: 12, pages: 2 });
    await expect(rows).toHaveCount(10);
    expect(
      first.items.every(row =>
        row.references.every(
          reference =>
            reference.sha256 === pin.sha256 &&
            reference.calendar_changed === true
        )
      )
    ).toBe(true);
    await expect(dialog).toContainText(
      'Não comprova configuração ou uso no PABX'
    );
    await expect(dialog).toContainText('mantém seu snapshot histórico');
    await screenshot('current-heads');
    const next = observe({ page: '2' });
    await dialog.locator('[data-calendar-ivr-next]').click();
    const second = await dto(await next);
    expect(second.meta).toEqual({ page: 2, per_page: 10, total: 12, pages: 2 });
    await expect(rows).toHaveCount(2);
    expect([...first.items, ...second.items].map(row => row.draft_id)).toEqual(
      records.toReversed().map(row => String(row.id))
    );
    await screenshot('page-two');
    await dialog.locator('[data-calendar-ivr-query]').fill(records[0].name);
    const searching = observe({ q: records[0].name });
    await dialog.locator('[data-calendar-ivr-query]').press('Enter');
    const searched = await dto(await searching);
    expect(searched.meta.total).toBe(1);
    expect(searched.items[0].draft_id).toBe(String(records[0].id));
    await expect(rows).toHaveCount(1);
    await dialog.locator('[data-calendar-ivr-list]').click();
    await expect(page).toHaveURL(new RegExp(`/contact-center/ura\\?`));
    const query = new URL(page.url()).searchParams;
    expect(query.get('ivr_unit')).toBe(unit);
    expect(query.get('ivr_q')).toBe(records[0].name);
    await expect(
      page.locator(`[data-ivr-draft="${records[0].id}"]`)
    ).toBeVisible();
    const detached = records.at(-1);
    const unlink = await page.request.patch(
      `${base}/ivr_drafts/${detached.id}`,
      {
        headers,
        data: {
          ivr_draft: {
            name: detached.name,
            status: 'draft',
            expected_revision: 1,
            request_id: randomUUID(),
            definition: {
              schema_version: 1,
              start: 'done',
              nodes: [{ id: 'done', type: 'end' }],
            },
          },
        },
      }
    );
    expect(unlink.status()).toBe(200);
    const archived = records.at(-2);
    const archive = await page.request.patch(
      `${base}/ivr_drafts/${archived.id}`,
      {
        headers,
        data: {
          ivr_draft: {
            name: archived.name,
            status: 'archived',
            definition: graph,
            expected_revision: 1,
            request_id: randomUUID(),
          },
        },
      }
    );
    expect(archive.status()).toBe(200);
    const after = await enter();
    expect(after.meta.total).toBe(11);
    expect(after.items.map(row => row.draft_id)).not.toContain(
      String(detached.id)
    );
    await dialog.locator('[data-calendar-ivr-status]').selectOption('archived');
    const filtering = observe({ status: 'archived' });
    await dialog.locator('[data-calendar-ivr-filter]').click();
    const filtered = await dto(await filtering);
    expect(filtered.meta.total).toBe(1);
    expect(filtered.items[0]).toMatchObject({
      draft_id: String(archived.id),
      status: 'archived',
      provider_applied: false,
    });
    await expect(rows).toHaveCount(1);
    await expect(rows).toContainText('Arquivada internamente');
    await screenshot('archived');
    const clearing = observe();
    await dialog.locator('[data-calendar-ivr-clear]').click();
    const cleared = await dto(await clearing);
    expect(cleared.meta).toEqual({
      page: 1,
      per_page: 10,
      total: 11,
      pages: 2,
    });
    await expect(rows).toHaveCount(10);
    await screenshot('history-preserved');
    const historical = await page.request.get(
      `${base}/ivr_drafts/${detached.id}/versions/1`,
      { headers }
    );
    expect(historical.status()).toBe(200);
    expect((await historical.json()).item.definition).toEqual(graph);
    const denied = [];
    for (const foreign of [target.denied_unit_id, foreignUnit]) {
      const response = await page.request.get(
        `${usagesPath}?unit_id=${foreign}`,
        { headers }
      );
      denied.push(response.status());
    }
    const viewer = await page.request.get(`${usagesPath}?unit_id=${unit}`, {
      headers: target.observer,
    });
    denied.push(viewer.status());
    expect(denied).toEqual([404, 404, 401]);
    expect(errors).toEqual([]);
    expect(forbidden).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-calendar-ivr-inventory-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          external_homologation: false,
          account_id: target.account_id,
          unit_id: unit,
          calendar_id: calendar.id,
          exact_historical_pin: pin,
          first,
          second,
          searched,
          after_unlink: after,
          archived: filtered,
          cleared,
          original_version_preserved: true,
          denied_statuses: denied,
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
