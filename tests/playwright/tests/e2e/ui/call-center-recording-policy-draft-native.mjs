import { expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Actual scoped APIs and native configuration audit. No PABX or retention action.
export async function verifyNativeRecordingPolicyDraft(
  parent,
  info,
  target,
  foreignUnit
) {
  const page = await parent.context().newPage();
  const account = String(target.account_id),
    unit = String(target.allowed_unit_id);
  const origin = 'http://127.0.0.1:5387';
  const base = `${origin}/api/v1/accounts/${account}/jrc_contact_center`;
  const path = `${base}/unit_recording_policy_drafts/${unit}`;
  const dark = info.project.name.endsWith('dark');
  const key = 'jrc_contact_center_recording_policy_draft_v1';
  const errors = [],
    prohibited = [],
    screenshots = [],
    writes = [];
  let loseNextResponse = false,
    committedLostResponse = null;
  const notice = `SYNTHETIC ${info.project.name} recording notice`;
  const headers = target.scoped;
  const read = async () => {
    const response = await page.request.get(path, { headers });
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toMatchObject({
      account_id: account,
      unit_id: unit,
      applied: false,
      provider_state: 'not_verified',
    });
    return data;
  };
  const units = async () => {
    const response = await page.request.get(`${base}/units`, { headers });
    expect(response.status()).toBe(200);
    const data = await response.json();
    const row = data.items.find(item => String(item.id) === unit);
    expect(row).toBeTruthy();
    expect(row.settings).not.toHaveProperty(key);
    expect(JSON.stringify(data)).not.toContain(notice);
    return row.settings;
  };
  const commands = async () => {
    const response = await page.request.get(`${base}/commands`, {
      headers: target.administrator,
    });
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data.account_id).toBe(account);
    expect(Array.isArray(data.items)).toBe(true);
    // The native endpoint returns a bounded items list, not pagination metadata.
    // This dedicated synthetic account must have no commands at any observation.
    expect(data.items).toEqual([]);
    return data.items.length;
  };
  const capture = async stage => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(dark);
    const name = `.codex/call-center-native-e2e/${info.project.name}-recording-policy-draft-${stage}.png`;
    await page.screenshot({ path: name, fullPage: true });
    screenshots.push(name);
  };
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const request = route.request(),
      url = new URL(request.url());
    const local = [origin, 'http://127.0.0.1:5386'].includes(url.origin);
    const save =
      local &&
      request.method() === 'PATCH' &&
      url.pathname === new URL(path).pathname;
    if (
      (!local && ['http:', 'https:'].includes(url.protocol)) ||
      (!['GET', 'HEAD'].includes(request.method()) && !save)
    ) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    if (save) {
      const body = request.postDataJSON();
      expect(Object.keys(body).sort()).toEqual([
        'expected_revision',
        'recording_policy_draft',
      ]);
      expect(body.expected_revision).toMatch(/^[a-f0-9]{64}$/);
      writes.push(body);
      if (loseNextResponse) {
        loseNextResponse = false;
        const response = await route.fetch();
        expect(response.status()).toBe(200);
        committedLostResponse = await response.json();
        return route.abort('failed');
      }
    }
    return route.continue();
  });
  await page.addInitScript(
    ({ auth, isDark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: headers, isDark: dark }
  );
  const open = async () => {
    await page.locator('[data-open-recording-policy-draft]').click();
    await page.locator('[data-recording-policy-unit]').selectOption(unit);
    await expect(page.locator('[data-recording-policy-mode]')).toBeVisible();
  };
  try {
    const before = {
      draft: (await read()).draft,
      settings: await units(),
      commands: await commands(),
    };
    expect(before.draft).toBeNull();
    expect(before.commands).toBe(0);
    const address = `/app/accounts/${account}/contact-center/control-desk/general`;
    await page.goto(address);
    await open();
    await expect(page.locator('[data-recording-policy-mode]')).toHaveValue('');
    await expect(page.locator('[data-recording-policy-retention]')).toHaveValue(
      ''
    );
    await page
      .locator('[data-recording-policy-mode]')
      .selectOption('on_demand');
    await page
      .locator('[data-recording-policy-scope]')
      .selectOption('selected_queues');
    await expect(page.locator('[data-recording-policy-queue]')).toHaveCount(20);
    await page
      .locator(`[data-recording-policy-queue="${target.queue_id}"]`)
      .check();
    await page.locator('[data-recording-policy-queue-next]').click();
    await expect(page.locator('[data-recording-policy-queue]')).toHaveCount(1);
    const secondQueue = await page
      .locator('[data-recording-policy-queue]')
      .getAttribute('data-recording-policy-queue');
    await page.locator('[data-recording-policy-queue]').check();
    await page.locator('[data-recording-policy-notice]').fill(notice);
    const saved = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === new URL(path).pathname &&
        response.request().method() === 'PATCH'
    );
    await page.locator('[data-save-recording-policy-draft]').click();
    expect((await saved).status()).toBe(200);
    await expect(page.locator('[data-recording-policy-saved]')).toBeVisible();
    const first = await read();
    expect(first.draft).toMatchObject({
      schema_version: 1,
      mode: 'on_demand',
      queue_scope: 'selected_queues',
      notice,
      retention_days: null,
    });
    expect(first.draft.queue_ids.sort()).toEqual(
      [String(target.queue_id), secondQueue].sort()
    );
    const contrast = [
      await measureLocatorTextContrast(
        page.locator('[data-recording-policy-saved]')
      ),
    ];
    expect(contrast[0].ratio).toBeGreaterThanOrEqual(4.5);
    await capture('saved');
    await page.reload();
    await open();
    await expect(page.locator('[data-recording-policy-notice]')).toHaveValue(
      notice
    );
    await expect(page.locator('[data-recording-policy-queue]')).toHaveCount(20);
    await capture('reloaded');
    await page
      .locator(`[data-remove-recording-policy-queue="${secondQueue}"]`)
      .click();
    await expect(
      page.locator(`[data-remove-recording-policy-queue="${secondQueue}"]`)
    ).toHaveCount(0);
    await page.locator('[data-recording-policy-queue-next]').click();
    await expect(
      page.locator(`[data-recording-policy-queue="${secondQueue}"]`)
    ).not.toBeChecked();
    await page
      .locator(`[data-recording-policy-queue="${secondQueue}"]`)
      .check();
    const concurrent = { ...first.draft, notice: `${notice} concurrent edit` };
    delete concurrent.schema_version;
    delete concurrent.scope_snapshot;
    const changed = await page.request.patch(path, {
      headers,
      data: {
        recording_policy_draft: concurrent,
        expected_revision: first.revision,
      },
    });
    expect(changed.status()).toBe(200);
    const stale = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === new URL(path).pathname &&
        response.request().method() === 'PATCH'
    );
    await page
      .locator('[data-recording-policy-notice]')
      .fill(`${notice} stale form`);
    await page.locator('[data-save-recording-policy-draft]').click();
    expect((await stale).status()).toBe(409);
    await expect(
      page.locator('[data-save-recording-policy-draft]')
    ).toBeDisabled();
    await capture('conflict');
    await page.locator('[data-reload-recording-policy-draft]').click();
    await expect(page.locator('[data-recording-policy-notice]')).toHaveValue(
      concurrent.notice
    );
    await expect(
      page.locator('[data-save-recording-policy-draft]')
    ).toBeEnabled();
    loseNextResponse = true;
    await page
      .locator('[data-recording-policy-notice]')
      .fill(`${notice} committed before response loss`);
    await page.locator('[data-save-recording-policy-draft]').click();
    await expect(
      page.locator('[data-recording-policy-draft] [role="alert"]')
    ).toContainText('Não foi possível confirmar o resultado');
    await expect(
      page.locator('[data-save-recording-policy-draft]')
    ).toBeDisabled();
    await capture('uncertain');
    expect(committedLostResponse).not.toBeNull();
    await page.locator('[data-reload-recording-policy-draft]').click();
    await expect(page.locator('[data-recording-policy-notice]')).toHaveValue(
      committedLostResponse.draft.notice
    );
    await capture('recovered');
    const deniedUnit = await page.request.get(
      `${base}/unit_recording_policy_drafts/${target.denied_unit_id}`,
      { headers }
    );
    const foreign = await page.request.get(
      `${base}/unit_recording_policy_drafts/${foreignUnit}`,
      { headers }
    );
    const observer = await page.request.get(path, { headers: target.observer });
    expect([deniedUnit.status(), foreign.status(), observer.status()]).toEqual([
      404, 404, 401,
    ]);
    const auditResponse = await page.request.get(
      `${base}/configuration_audits?history=true&resource_type=unit&resource_id=${unit}&page=1&per_page=100`,
      { headers: target.administrator }
    );
    expect(auditResponse.status()).toBe(200);
    const audit = await auditResponse.json();
    const rows = audit.items.filter(
      row => row.operation === 'update' && row.after?.settings?.[key]
    );
    expect(rows).toHaveLength(3);
    expect(
      rows.every(
        row =>
          String(row.actor_id) === String(target.scoped_user_id) &&
          row.correlation_id &&
          String(row.scopes.after.unit_id) === unit
      )
    ).toBe(true);
    expect(JSON.stringify(audit)).not.toContain(notice);
    const final = await read();
    expect(rows[0].after.settings[key].notice_sha256).toBe(
      createHash('sha256').update(final.draft.notice).digest('hex')
    );
    expect(await units()).toEqual(before.settings);
    expect(await commands()).toBe(before.commands);
    expect(writes).toHaveLength(3);
    await page.evaluate(async auth => {
      Object.assign(window.axios.defaults.headers.common, auth);
      await Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')();
    }, target.observer);
    await expect(page.locator('[data-recording-policy-draft]')).toHaveCount(0);
    await expect(
      page.locator('[data-open-recording-policy-draft]')
    ).toHaveCount(0);
    await capture('denied');
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recording-policy-draft.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          synthetic: true,
          account_id: account,
          unit_id: unit,
          actual_dark_theme: dark,
          native_before: before,
          native_after: final,
          native_queue_pages: [20, 1],
          selected_queue_ids: first.draft.queue_ids,
          stale_status: 409,
          denials: [404, 404, 401],
          native_audits: rows,
          lost_response_after_real_commit: true,
          recovered_same_committed_revision:
            committedLostResponse.revision === final.revision,
          browser_write_count: writes.length,
          commands_after: await commands(),
          native_general_access_without_recordings_permission: true,
          contrast,
          screenshots,
          errors,
          prohibited,
          no_provider_application_or_retention_action: true,
          external_homologation: false,
          whole_figure_or_Part1_accepted: false,
        },
        null,
        2
      ) + '\n'
    );
  } catch (error) {
    await page
      .screenshot({
        path: `.codex/call-center-native-e2e/${info.project.name}-recording-policy-draft-failure.png`,
        fullPage: true,
        timeout: 5000,
      })
      .catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
