import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Real production Vue and scoped Rails APIs, with an inactive synthetic rule only.
export async function verifyScopedEndingEditor(parent, info, target) {
  const page = await parent.context().newPage();
  const dark = info.project.name.endsWith('dark');
  const prefix = `/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const path = `${prefix}/acw_policy/ending_rules`;
  const endpoint = `http://127.0.0.1:5387${path}`;
  const location = `/app/accounts/${target.account_id}/contact-center/control-desk/closures`;
  const errors = [];
  const forbidden = [];
  const writes = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (new URL(request.url()).pathname === path && request.method() === 'POST')
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
      /\/(commands|sync_calls|telephony_integration|tasks)(?:[/?]|$)/.test(
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
    { auth: target.scoped, isDark: dark }
  );
  await page.goto(location);
  expect(
    await page.evaluate(() =>
      document.documentElement.classList.contains('dark')
    )
  ).toBe(dark);
  await expect(page.locator('[data-manage-ending-reasons]')).toHaveCount(0);
  await expect(page.locator('[data-manage-acw-forms]')).toHaveCount(0);
  await expect(page.locator('[data-create]')).toHaveCount(0);
  await page.locator('[data-manage-scoped-ending-rules]').click();
  let editor = page.locator('[data-ending-automation-editor]');
  await expect(editor.locator('[data-ending-rule-new]')).toBeEnabled();
  await expect(editor).not.toContainText('SYNTHETIC private persisted title');
  const initial = await page.request.get(endpoint, { headers: target.scoped });
  expect(initial.status()).toBe(200);
  expect((await initial.json()).items).toEqual([]);
  const globalEndpoint = `http://127.0.0.1:5387${prefix}/acw_policy`;
  const global = await page.request.get(globalEndpoint, {
    headers: target.scoped,
  });
  expect(global.status()).toBe(200);
  const publicPolicy = (await global.json()).item;
  expect(Object.keys(publicPolicy).sort()).toEqual([
    'enabled',
    'id',
    'limits',
    'require_reason',
    'require_result',
    'revision',
    'voice_required',
  ]);
  expect(JSON.stringify(publicPolicy)).not.toContain(
    'SYNTHETIC private persisted title'
  );
  const deniedGlobal = await page.request.patch(globalEndpoint, {
    headers: target.scoped,
    data: {
      limits: {
        voice: publicPolicy.limits.voice === 120 ? 121 : 120,
        whatsapp: publicPolicy.limits.whatsapp,
      },
      expected_revision: publicPolicy.revision,
    },
  });
  expect([401, 403]).toContain(deniedGlobal.status());
  const afterDenied = await page.request.get(globalEndpoint, {
    headers: target.scoped,
  });
  expect(afterDenied.status()).toBe(200);
  expect((await afterDenied.json()).item).toEqual(publicPolicy);
  const other = await page.request.get(
    `${endpoint}/source_context?queue_id=${target.denied_queue_id}`,
    { headers: target.scoped }
  );
  expect(other.status()).toBe(404);
  const privateProject = await page.request.get(
    `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/projects/projects/${target.automation_project_id}`,
    { headers: target.scoped }
  );
  expect([401, 403, 404]).toContain(privateProject.status());
  expect(await privateProject.text()).not.toContain(
    target.automation_project_name
  );
  await editor.locator('[data-ending-rule-new]').click();
  await editor
    .locator('[data-ending-rule-code]')
    .fill('SYNTHETIC_SCOPED_BROWSER_DRAFT');
  await editor
    .locator('[data-ending-rule-name]')
    .fill('SYNTHETIC owned unit inactive draft');
  await editor
    .locator('[data-ending-rule-reason]')
    .selectOption(target.automation_reason);
  await editor
    .locator('[data-ending-rule-timing]')
    .selectOption('acw_completed');
  await editor
    .locator('[data-ending-execution-mode]')
    .selectOption('agent_confirmation');
  const queue = editor.locator('[data-acw-rule-target] select');
  await expect(
    queue.locator(`option[value="${target.denied_queue_id}"]`)
  ).toHaveCount(0);
  await queue.selectOption(String(target.queue_id));
  await expect(editor.locator('[data-ending-rule-source]')).toContainText(
    'SYNTHETIC pause unit'
  );
  await expect(editor.locator('[data-ending-rule-active]')).not.toBeChecked();
  await expect(editor.locator('[data-ending-rule-save]')).toBeDisabled();
  await editor.locator('[data-ending-rule-reviewed]').check();
  await expect(editor.locator('[data-ending-rule-save]')).toBeEnabled();
  const result = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === path &&
      response.request().method() === 'POST'
  );
  await editor.locator('[data-ending-rule-save]').click();
  expect((await result).status()).toBe(200);
  await expect(editor.locator('[data-ending-rule-saved]')).toBeVisible();
  expect(writes).toHaveLength(1);
  expect(writes[0].private_rule).toMatchObject({
    code: 'SYNTHETIC_SCOPED_BROWSER_DRAFT',
    active: false,
    actions: [],
    queue_id: String(target.queue_id),
    timing: 'acw_completed',
    execution_mode: 'agent_confirmation',
  });
  const [contrast] = await editor
    .locator('h3')
    .first()
    .evaluate(measureTextContrast);
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await editor.locator('[data-ending-rule-code]').scrollIntoViewIfNeeded();
  const screenshot = `.codex/call-center-native-e2e/${info.project.name}-ending-scoped-editor.png`;
  await page.screenshot({ path: screenshot });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await page.reload();
  await page.locator('[data-manage-scoped-ending-rules]').click();
  editor = page.locator('[data-ending-automation-editor]');
  await expect(editor).toContainText('SYNTHETIC owned unit inactive draft');
  await expect(editor).not.toContainText('SYNTHETIC private persisted title');
  const persisted = await page.request.get(endpoint, {
    headers: target.scoped,
  });
  expect(persisted.status()).toBe(200);
  const data = await persisted.json();
  expect(data.items).toHaveLength(1);
  expect(data.items[0]).toMatchObject({
    code: 'SYNTHETIC_SCOPED_BROWSER_DRAFT',
    active: false,
    actions: [],
  });
  expect(errors).toEqual([]);
  expect(forbidden).toEqual([]);
  const receipt = {
    sha: process.env.GITHUB_SHA,
    synthetic: true,
    project: info.project.name,
    account_id: String(target.account_id),
    scoped_rule_saved_and_reloaded: true,
    current_source_authorized: true,
    other_source_status: other.status(),
    global_policy_status: deniedGlobal.status(),
    global_public_read_status: global.status(),
    global_public_read_private_configuration_absent: true,
    global_policy_unchanged_after_denied_write: true,
    private_project_status: privateProject.status(),
    private_template_unexposed: true,
    native_configure_not_group: true,
    inactive_rule_only: true,
    effects_executed: false,
    actual_dark_theme: dark,
    theme_asserted_in_browser: true,
    horizontal_overflow_absent: true,
    contrast,
    screenshots: [screenshot],
    errors,
    provider_or_destination_writes: forbidden,
  };
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ending-scoped-editor-native.json`,
    JSON.stringify(receipt)
  );
  await page.close();
  return receipt;
}
