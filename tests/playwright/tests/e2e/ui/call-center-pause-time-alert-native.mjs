import { expect } from '@playwright/test';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Extend the existing owned duration case after its original assertions. The
// existing explicitly synthetic zero-minute threshold gives a real elapsed
// observation without changing clocks, SQL rows, historic events or the PABX.
export async function verifyNativePauseTimeAlert(page, info, target) {
  const account = String(target.account_id);
  const api = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center`;
  const endpoint = api + '/pause_catalog';
  const screenshots = [];
  const writes = [];
  const errors = [];
  const transitions = [];
  const contrast = [];
  const actor = await page.context().newPage();
  const dark = info.project.name.endsWith('dark');
  const track = request => {
    if (['GET', 'HEAD'].includes(request.method())) return;
    writes.push({
      path: new URL(request.url()).pathname,
      method: request.method(),
    });
  };
  const error = value => errors.push(value.message);
  page.on('request', track);
  page.on('pageerror', error);
  actor.on('request', track);
  actor.on('pageerror', error);
  await actor.addInitScript(
    ({ auth, isDark }) => {
      Reflect.set(window, '__SYNTHETIC_AUTH__', auth);
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: target.operator, isDark: dark }
  );

  const capture = async (tab, state) => {
    expect(
      await tab.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    expect(
      await tab
        .locator('html')
        .evaluate(element => element.classList.contains('dark'))
    ).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-pause-time-alert-${state}.png`;
    await tab.screenshot({ path, fullPage: false });
    screenshots.push(path);
  };
  const state = async () => {
    const response = await page.request.get(api + '/agent_state', {
      headers: target.operator,
    });
    expect(response.status()).toBe(200);
    return (await response.json()).item;
  };
  const transition = async (value, version) => {
    const response = await page.request.patch(api + '/agent_state', {
      headers: target.operator,
      data: {
        agent_state: {
          state: value,
          queue_id: target.queue_id,
          command_id: randomUUID(),
          expected_state_version: version,
          ...(value === 'paused'
            ? {
                reason_code: 'synthetic_duration',
                justification: 'SYNTHETIC PRIVATE alert QA',
              }
            : {}),
        },
      },
    });
    expect(response.status()).toBe(200);
    const item = (await response.json()).item;
    expect(item).toMatchObject({
      state: value,
      provider_confirmed: false,
      eligible: false,
    });
    transitions.push({
      state: value,
      version: item.state_version,
      explicit_owned_fixture_action: true,
    });
    return item;
  };
  const observed = async enabled => {
    let value;
    await expect
      .poll(
        async () => {
          const response = await page.request.get(api + '/supervisor', {
            headers: target.administrator,
          });
          expect(response.status()).toBe(200);
          value = (await response.json()).agents.find(
            row => String(row.account_user_id) === String(target.operator_id)
          );
          return (
            value?.pause_notice?.exceeded === true &&
            value.pause_notice.time_alert_enabled === enabled
          );
        },
        { timeout: 15000 }
      )
      .toBe(true);
    expect(value.state).toBe('paused');
    expect(value.pause_notice.elapsed_seconds).toBeGreaterThan(0);
    return value;
  };
  const configure = async (enabled, takeCapture = false) => {
    await page.goto(
      `/app/accounts/${account}/contact-center/control-desk/pauses?native_navigation=1`
    );
    const catalog = page.locator('[data-pause-catalog]');
    await catalog
      .locator('article')
      .filter({ hasText: 'SYNTHETIC duration notice' })
      .getByRole('button', { name: 'Editar', exact: true })
      .click();
    const dialog = page.getByRole('dialog');
    const checkbox = dialog.locator('[data-pause-time-alert]');
    await checkbox.setChecked(enabled);
    await checkbox.scrollIntoViewIfNeeded();
    if (takeCapture) {
      const label = dialog.locator('label').filter({ has: checkbox });
      const measured = await measureLocatorTextContrast(
        label.locator('span.block').first()
      );
      expect(measured.ratio).toBeGreaterThanOrEqual(4.5);
      contrast.push({ key: 'configuration-label', ...measured });
      await capture(page, 'configuration-off');
    }
    const saved = page.waitForResponse(response =>
      isBrowserApiResponse(response, page.url(), endpoint, 'PATCH')
    );
    await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
    expect((await saved).status()).toBe(200);
    await expect(dialog).toBeHidden();
    const response = await page.request.get(endpoint, {
      headers: target.administrator,
    });
    expect(response.status()).toBe(200);
    const document = (await response.json()).item;
    expect(document.enforced).toBe(true);
    expect(document.entries).toHaveLength(1);
    const reason = document.entries[0];
    expect(reason).toMatchObject({
      code: 'synthetic_duration',
      time_alert_enabled: enabled,
      minimum_minutes: 0,
      default_minutes: 0,
      maximum_minutes: 0,
      justification_required: true,
      unit_ids: [target.unit_id],
      custom_role_ids: [target.operator_role_id],
    });
    return document;
  };
  try {
    const before = await state();
    expect(before.state).toBe('available');
    const disabled = await configure(false, true);
    await page.reload();
    await page
      .locator('[data-pause-catalog] article')
      .getByRole('button', { name: 'Editar', exact: true })
      .click();
    await expect(page.locator('[data-pause-time-alert]')).not.toBeChecked();
    await page
      .getByRole('dialog')
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    const first = await transition('paused', before.state_version);
    expect(first.pause_definition.time_alert_enabled).toBe(false);
    const oldNotice = await observed(false);
    await actor.goto(
      `/app/accounts/${account}/contact-center/operacao?native_navigation=1`
    );
    const panel = actor.locator('[data-agent-state="paused"]');
    await expect(panel.getByRole('timer')).toBeVisible();
    await expect(panel.locator('[data-pause-exceeded]')).toHaveCount(0);
    await panel.getByRole('timer').scrollIntoViewIfNeeded();
    await capture(actor, 'operator-off');
    await page.goto(
      `/app/accounts/${account}/contact-center/supervisor?native_navigation=1`
    );
    const notice = page.locator('[data-supervisor-pause-notice]');
    await expect(notice).toContainText('Tempo em pausa:');
    await expect(notice.getByRole('status')).toHaveCount(0);
    await notice.scrollIntoViewIfNeeded();
    await capture(page, 'supervisor-off');
    const enabled = await configure(true);
    expect(enabled.revision).not.toBe(disabled.revision);
    const immutable = await state();
    expect(immutable.state_version).toBe(first.state_version);
    expect(immutable.pause_definition.time_alert_enabled).toBe(false);
    await observed(false);
    const available = await transition('available', first.state_version);
    const next = await transition('paused', available.state_version);
    expect(next.pause_definition.time_alert_enabled).toBe(true);
    const currentNotice = await observed(true);
    await actor.reload();
    const warning = actor.locator('[data-pause-exceeded]');
    await expect(warning).toBeVisible();
    await warning.scrollIntoViewIfNeeded();
    const measured = await measureLocatorTextContrast(warning);
    expect(measured.ratio).toBeGreaterThanOrEqual(4.5);
    contrast.push({ key: 'operator-warning', ...measured });
    await capture(actor, 'operator-on');
    await page.goto(
      `/app/accounts/${account}/contact-center/supervisor?native_navigation=1`
    );
    await expect(notice.getByRole('status')).toContainText(
      'A pausa continua ativa'
    );
    await notice.scrollIntoViewIfNeeded();
    await capture(page, 'supervisor-on');
    const final = await transition('available', next.state_version);
    expect(writes).toEqual(
      Array.from({ length: 2 }, () => ({
        path: new URL(endpoint).pathname,
        method: 'PATCH',
      }))
    );
    expect(errors).toEqual([]);
    const denied = await page.request.get(endpoint, {
      headers: target.operator,
    });
    expect(denied.status()).toBe(401);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-pause-time-alert.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          actual_dark_theme: await page
            .locator('html')
            .evaluate(element => element.classList.contains('dark')),
          actual_operator_dark_theme: await actor
            .locator('html')
            .evaluate(element => element.classList.contains('dark')),
          ACW_behavior_unchanged: true,
          account_id: account,
          synthetic: true,
          existing_native_zero_threshold_reused: true,
          no_clock_or_SQL_or_old_event_manipulation: true,
          configuration_persisted_and_reopened: true,
          old_pause_policy_preserved_after_catalog_change: true,
          disabled_pause_version: first.state_version,
          new_enabled_pause_version: next.state_version,
          final_explicit_available_version: final.state_version,
          transitions,
          writes,
          errors,
          contrast,
          screenshots,
          original_factual_exceeded_observations: [
            oldNotice.pause_notice,
            currentNotice.pause_notice,
          ],
          catalog_read_denied_to_operator: 401,
          no_PABX_or_external_operation: true,
          disabled_catalog_revision: disabled.revision,
          enabled_catalog_revision: enabled.revision,
          whole_figure_or_Part1_accepted: false,
        },
        null,
        2
      ) + '\n'
    );
  } finally {
    page.off('request', track);
    page.off('pageerror', error);
    await actor.close();
  }
}
