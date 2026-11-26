import { verifyInactiveServiceDeskSource } from './call-center-ending-service-desk-inactive-native.mjs';
import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Actual existing Vue selectors, HTTP authorization and PostgreSQL. No route
// fulfills, fake response, fake policy, Ticket creation or provider command.
export async function verifyEndingServiceDesk(
  parent,
  info,
  target,
  foreignHeaders
) {
  const page = await parent.context().newPage();
  const dark = info.project.name.endsWith('dark');
  const prefix = `/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = `http://127.0.0.1:5387${prefix}/acw_policy/ending_rules`;
  const errors = [];
  const forbidden = [];
  const writes = [];
  const screenshots = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (
      new URL(request.url()).pathname === `${prefix}/acw_policy/ending_rules` &&
      request.method() === 'POST'
    )
      writes.push(request.postDataJSON());
  });
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    const prohibited =
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration|tickets|tasks)(?:[/?]|$)/.test(
        url.pathname
      );
    if (outside || prohibited) {
      forbidden.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  await page.addInitScript(
    ({ auth, isDark }) => {
      Reflect.set(window, '__SYNTHETIC_AUTH__', auth);
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: target.administrator, isDark: dark }
  );
  const openEditor = async () => {
    await page.locator('[data-manage-ending-reasons]').click();
    await page.locator('[data-ending-automations-open]').click();
    await expect(
      page.getByRole('dialog', {
        name: 'Configurar automações e integrações',
        exact: true,
      })
    ).toBeVisible();
    return page.locator('[data-ending-automation-editor]');
  };
  const capture = async (name, element) => {
    await element.scrollIntoViewIfNeeded();
    const image = `.codex/call-center-native-e2e/${info.project.name}-ending-sd-${name}.png`;
    await page.screenshot({ path: image });
    screenshots.push(image);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
  };
  const persist = async editor => {
    await editor.locator('[data-ending-rule-reviewed]').check();
    const result = page.waitForResponse(
      response =>
        new URL(response.url()).pathname ===
          `${prefix}/acw_policy/ending_rules` &&
        response.request().method() === 'POST'
    );
    await editor.locator('[data-ending-rule-save]').click();
    return (await result).status();
  };
  const proof = () => {
    const raw = execFileSync(
      'bundle',
      [
        'exec',
        'rails',
        'runner',
        'script/jrc_call_center_ending_service_desk_evidence.rb',
        String(target.account_id),
      ],
      { encoding: 'utf8', timeout: 90000, maxBuffer: 1024 * 1024 }
    );
    return JSON.parse(raw.trim().split('\n').at(-1));
  };
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/closures`
  );
  expect(
    await page.evaluate(() =>
      document.documentElement.classList.contains('dark')
    )
  ).toBe(dark);
  let editor = await openEditor();
  await editor.locator('[data-ending-rule-new]').click();
  await editor.locator('[data-ending-rule-code]').fill('SYNTHETIC_SD_BROWSER');
  await editor
    .locator('[data-ending-rule-name]')
    .fill('SYNTHETIC reviewed native SD rule');
  await editor
    .locator('[data-ending-rule-reason]')
    .selectOption(target.automation_reason);
  await editor.locator('[data-ending-rule-timing]').selectOption('call_end');
  await editor
    .locator('[data-ending-execution-mode]')
    .selectOption('agent_confirmation');
  await editor
    .locator('[data-acw-rule-target] select')
    .selectOption(String(target.queue_id));
  await expect(
    editor.locator('[data-ending-configure-destination="service_desk"]')
  ).toBeEnabled();
  await editor.locator('[data-ending-rule-active]').check();
  await editor
    .locator('[data-ending-configure-destination="service_desk"]')
    .click();
  let form = editor.locator('[data-ending-service-desk-configuration]');
  await expect(form.locator('input:disabled').first()).toHaveValue(
    target.service_desk_unit_name
  );
  await form
    .locator('[data-ending-service-desk-title]')
    .fill('SYNTHETIC persisted native SD title');
  await form
    .locator('[data-ending-service-desk-description]')
    .fill('SYNTHETIC persisted native SD description');
  await form
    .locator('[data-ending-sd-lookup="priorities"] select')
    .selectOption(target.service_desk_priority_id);
  await expect(form.locator('[data-ending-service-desk-apply]')).toBeDisabled();
  await capture('fields', form.locator('[data-ending-service-desk-title]'));
  await form.locator('[data-ending-service-desk-reviewed]').check();
  await capture('review', form.locator('[data-ending-service-desk-apply]'));
  await form.locator('[data-ending-service-desk-apply]').click();
  expect(writes).toHaveLength(0);
  expect(await persist(editor)).toBe(200);
  await expect(editor.locator('[data-ending-rule-saved]')).toBeVisible();
  expect(writes).toHaveLength(1);
  expect(writes[0].private_rule.actions).toHaveLength(1);
  expect(writes[0].private_rule.actions[0]).toMatchObject({
    kind: 'service_desk',
    parameters: {
      unit_id: target.service_desk_unit_id,
      service_id: null,
      attributes: {
        status_id: target.service_desk_status_id,
        priority_id: target.service_desk_priority_id,
        title: 'SYNTHETIC persisted native SD title',
      },
    },
  });
  const first = proof();
  expect(first.version_ids).toHaveLength(1);
  expect([first.tickets, first.task_effects, first.attempts]).toEqual([
    0, 0, 0,
  ]);
  await capture('saved', editor.locator('[data-ending-rule-saved]'));
  await page.reload();
  editor = await openEditor();
  await expect(editor.locator('[data-ending-rule-entry]')).toContainText(
    'SYNTHETIC reviewed native SD rule'
  );
  await editor.locator('[data-ending-rule-edit]').click();
  await editor
    .locator('[data-ending-configure-destination="service_desk"]')
    .click();
  form = editor.locator('[data-ending-service-desk-configuration]');
  await expect(form.locator('[data-ending-service-desk-title]')).toHaveValue(
    'SYNTHETIC persisted native SD title'
  );
  await expect(
    form.locator('[data-ending-sd-lookup="priorities"] select')
  ).toHaveValue(target.service_desk_priority_id);
  await form
    .locator('[data-ending-service-desk-description]')
    .fill('SYNTHETIC second reviewed native SD description');
  await form.locator('[data-ending-service-desk-reviewed]').check();
  await form.locator('[data-ending-service-desk-apply]').click();
  expect(await persist(editor)).toBe(200);
  const final = proof();
  expect(final.source_sha).toBe(process.env.GITHUB_SHA);
  expect(final.account_id).toBe(String(target.account_id));
  expect(final.version_ids).toHaveLength(2);
  expect(final.private_version_hashes[first.version_ids[0]]).toBe(
    first.private_version_hashes[first.version_ids[0]]
  );
  expect([final.tickets, final.task_effects, final.attempts]).toEqual([
    0, 0, 0,
  ]);
  const foreign = await page.request.get(endpoint, { headers: foreignHeaders });
  expect([401, 403, 404]).toContain(foreign.status());
  expect(await foreign.text()).not.toContain(
    'SYNTHETIC persisted native SD title'
  );
  const refused = await page.request.post(endpoint, {
    headers: target.operator,
    data: writes[0],
  });
  expect([401, 403]).toContain(refused.status());
  expect(proof()).toEqual(final);
  const [contrast] = await editor
    .locator('h3')
    .first()
    .evaluate(measureTextContrast);
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await capture('reloaded', editor.locator('[data-ending-rule-saved]'));
  const closedSource = await verifyInactiveServiceDeskSource({
    page,
    target,
    prefix,
    endpoint,
    openEditor,
    persist,
    proof,
    capture,
    writes,
    previous: final,
  });
  expect(errors).toEqual([]);
  expect(forbidden).toEqual([]);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ending-sd-native.json`,
    JSON.stringify({
      sha: process.env.GITHUB_SHA,
      synthetic: true,
      project: info.project.name,
      account_id: String(target.account_id),
      actual_dark_theme: dark,
      theme_asserted_in_browser: true,
      native_lookup_and_catalogue_used: true,
      review_without_automatic_save: true,
      persist_and_edit_status: [200, 200],
      foreign_status: foreign.status(),
      current_operator_denied_status: refused.status(),
      previous_version_preserved: true,
      first,
      final,
      closed_source_deactivation: closedSource,
      contrast,
      screenshots,
      no_ticket_task_or_attempt_created: true,
      errors,
      forbidden_writes: forbidden,
    })
  );
  await page.close();
}
