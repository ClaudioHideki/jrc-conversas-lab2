import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureTextContrast } from './call-center-text-contrast.mjs';
import { verifyScopedEndingEditor } from './call-center-ending-scoped-editor-native.mjs';

// Production Vue, real scoped APIs and PostgreSQL. No mocked response or destination execution.
export async function verifyEndingEditor(parent, info, target, foreignHeaders) {
  const page = await parent.context().newPage();
  const dark = info.project.name.endsWith('dark');
  const prefix = `/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = `http://127.0.0.1:5387${prefix}/acw_policy/ending_rules`;
  const location = `/app/accounts/${target.account_id}/contact-center/control-desk/closures`;
  const errors = [];
  const forbidden = [];
  const writes = [];
  const screenshots = [];
  const configurationScreenshots = [];
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
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: target.administrator, isDark: dark }
  );
  await page.goto(location);
  const actualDarkTheme = await page.evaluate(() =>
    document.documentElement.classList.contains('dark')
  );
  expect(actualDarkTheme).toBe(dark);
  await page.locator('[data-manage-ending-reasons]').click();
  await page.locator('[data-ending-automations-open]').click();
  await expect(
    page.getByRole('dialog', {
      name: 'Configurar automações e integrações',
      exact: true,
    })
  ).toBeVisible();
  let editor = page.locator('[data-ending-automation-editor]');
  await expect(
    editor.locator('[data-ending-configuration-only]')
  ).toContainText('Salvar só altera a configuração');
  await editor.locator('[data-ending-rule-new]').click();
  await expect(editor.locator('[data-ending-rule-save]')).toBeDisabled();
  await editor
    .locator('[data-ending-rule-code]')
    .fill('SYNTHETIC_BROWSER_AUTOMATION');
  await editor
    .locator('[data-ending-rule-name]')
    .fill('SYNTHETIC reviewed browser automation');
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
  await expect(editor.locator('[data-ending-rule-source]')).toContainText(
    'SYNTHETIC pause unit'
  );
  await editor.locator('[data-ending-rule-active]').check();
  await editor.locator('[data-ending-rule-code]').scrollIntoViewIfNeeded();
  const fieldsImage = `.codex/call-center-native-e2e/${info.project.name}-ending-automation-fields.png`;
  await page.screenshot({ path: fieldsImage });
  configurationScreenshots.push(fieldsImage);
  for (const kind of ['crm', 'service_desk', 'notifications', 'nico'])
    await expect(
      editor.locator(`[data-ending-configure-destination="${kind}"]`)
    ).toBeDisabled();
  await editor
    .locator('[data-ending-configure-destination="project_task"]')
    .click();
  const task = editor.locator('[data-ending-project-configuration]');
  await task
    .locator('[data-ending-project]')
    .selectOption(target.automation_project_id);
  const projectResponse = await page.request.get(
    `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/projects/projects/${target.automation_project_id}`,
    { headers: target.administrator }
  );
  expect(projectResponse.status()).toBe(200);
  const { data: reviewedProject } = await projectResponse.json();
  expect(String(reviewedProject.id)).toBe(target.automation_project_id);
  expect(reviewedProject.capabilities).toContain('projects.task.assign');
  expect(
    reviewedProject.members.some(
      member => String(member.user_id) === target.automation_assignee_id
    )
  ).toBe(true);
  await expect(task.locator('[data-ending-task-assignee]')).toBeVisible();
  await task
    .locator('[data-ending-task-title]')
    .fill('SYNTHETIC private persisted title');
  await task
    .locator('[data-ending-task-column]')
    .selectOption(target.automation_column_id);
  await task.locator('[data-ending-task-priority]').selectOption('medium');
  await task.locator('[data-ending-task-due]').fill('0');
  await task
    .locator('[data-ending-task-assignee]')
    .selectOption(target.automation_assignee_id);
  await task.locator('[data-ending-project]').scrollIntoViewIfNeeded();
  const parametersImage = `.codex/call-center-native-e2e/${info.project.name}-ending-automation-project.png`;
  await page.screenshot({ path: parametersImage });
  configurationScreenshots.push(parametersImage);
  await task.locator('[data-ending-task-apply]').scrollIntoViewIfNeeded();
  const actionsImage = `.codex/call-center-native-e2e/${info.project.name}-ending-automation-project-actions.png`;
  await page.screenshot({ path: actionsImage });
  configurationScreenshots.push(actionsImage);
  await task.locator('[data-ending-task-apply]').click();
  await expect(editor.locator('[data-ending-rule-save]')).toBeDisabled();
  await editor.locator('[data-ending-rule-reviewed]').check();
  const savedResponse = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `${prefix}/acw_policy/ending_rules` &&
      response.request().method() === 'POST'
  );
  await editor.locator('[data-ending-rule-save]').click();
  expect((await savedResponse).status()).toBe(200);
  await expect(editor.locator('[data-ending-rule-saved]')).toBeVisible();
  await expect(editor.locator('[data-ending-rule-activation]')).toBeVisible();
  expect(writes).toHaveLength(1);
  expect(writes[0].private_rule).toMatchObject({
    execution_mode: 'agent_confirmation',
    destination_schema_version: 2,
    timing: 'call_end',
    active: true,
  });
  expect(writes[0].private_rule.actions[0].parameters.due_after_days).toBe(0);
  const [contrast] = await editor
    .locator('h3')
    .first()
    .evaluate(measureTextContrast);
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  const image = `.codex/call-center-native-e2e/${info.project.name}-ending-automation-editor.png`;
  await editor.locator('[data-ending-rule-preview]').scrollIntoViewIfNeeded();
  await page.screenshot({ path: image });
  screenshots.push(image);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await page.reload();
  await page.locator('[data-manage-ending-reasons]').click();
  await page.locator('[data-ending-automations-open]').click();
  await expect(
    page.getByRole('dialog', {
      name: 'Configurar automações e integrações',
      exact: true,
    })
  ).toBeVisible();
  editor = page.locator('[data-ending-automation-editor]');
  await expect(editor.locator('[data-ending-rule-entry]')).toContainText(
    'SYNTHETIC reviewed browser automation'
  );
  await editor.locator('[data-ending-rule-edit]').click();
  await expect(editor.locator('[data-ending-execution-mode]')).toHaveValue(
    'agent_confirmation'
  );
  await editor
    .locator('[data-ending-rule-name]')
    .fill('SYNTHETIC final reviewed name');
  const original = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(original.status()).toBe(200);
  const { items, revision } = await original.json();
  const current = items[0];
  expect(current.actions[0].parameters.attributes.assignee_id).toBe(
    target.automation_assignee_id
  );
  await editor
    .locator('[data-ending-configure-destination="project_task"]')
    .click();
  await expect(editor.locator('[data-ending-task-assignee]')).toHaveValue(
    target.automation_assignee_id
  );
  await editor
    .locator('[data-ending-project-configuration]')
    .getByRole('button', { name: 'Voltar', exact: true })
    .click();
  const { scope, ...input } = current;
  const concurrent = await page.request.post(endpoint, {
    headers: target.administrator,
    data: {
      expected_revision: revision,
      private_rule: {
        ...input,
        scope_revision: scope.integrity_sha256,
        name: 'SYNTHETIC concurrent edit',
      },
    },
  });
  expect(concurrent.status()).toBe(200);
  await editor.locator('[data-ending-rule-reviewed]').check();
  const stale = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `${prefix}/acw_policy/ending_rules` &&
      response.request().method() === 'POST'
  );
  await editor.locator('[data-ending-rule-save]').click();
  expect((await stale).status()).toBe(409);
  await expect(editor.locator('[data-ending-rule-name]')).toHaveValue(
    'SYNTHETIC final reviewed name'
  );
  await editor
    .locator('[data-configuration-conflict]')
    .getByRole('button')
    .click();
  await expect(editor.locator('[data-configuration-latest]')).toContainText(
    'SYNTHETIC concurrent edit'
  );
  await editor.locator('[data-configuration-review]').check();
  await editor.locator('[data-ending-rule-reviewed]').check();
  const revised = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `${prefix}/acw_policy/ending_rules` &&
      response.request().method() === 'POST'
  );
  await editor.locator('[data-ending-rule-save]').click();
  expect((await revised).status()).toBe(200);
  const foreign = await page.request.get(endpoint, { headers: foreignHeaders });
  const scoped = await page.request.get(endpoint, { headers: target.scoped });
  const operator = await page.request.get(endpoint, {
    headers: target.operator,
  });
  expect([401, 403, 404]).toContain(foreign.status());
  expect(scoped.status()).toBe(200);
  expect((await scoped.json()).items).toEqual([]);
  expect(await scoped.text()).not.toContain(
    'SYNTHETIC private persisted title'
  );
  expect([401, 403]).toContain(operator.status());
  expect(await foreign.text()).not.toContain(
    'SYNTHETIC private persisted title'
  );
  await editor.locator('[data-ending-rule-name]').fill('SYNTHETIC denied edit');
  await editor.locator('[data-ending-rule-reviewed]').check();
  await page.evaluate(
    auth =>
      Object.assign(Reflect.get(window, 'axios').defaults.headers.common, auth),
    target.operator
  );
  const refused = page.waitForResponse(
    response =>
      new URL(response.url()).pathname ===
        `${prefix}/acw_policy/ending_rules` &&
      response.request().method() === 'POST'
  );
  await editor.locator('[data-ending-rule-save]').click();
  expect([401, 403]).toContain((await refused).status());
  await expect(editor.locator('[data-ending-rule-preview]')).toHaveCount(0);
  await expect(editor).not.toContainText('SYNTHETIC private persisted title');
  const final = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect((await final.json()).items[0].name).toBe(
    'SYNTHETIC final reviewed name'
  );
  expect(errors).toEqual([]);
  expect(forbidden).toEqual([]);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ending-editor-native.json`,
    JSON.stringify({
      sha: process.env.GITHUB_SHA,
      synthetic: true,
      project: info.project.name,
      account_id: String(target.account_id),
      initial_save: 200,
      persisted_mode: 'agent_confirmation',
      native_project_assignee_selected_and_reloaded: true,
      native_project_assignee_id: target.automation_assignee_id,
      stale_status: 409,
      reviewed_save: 200,
      denied_status: operator.status(),
      scoped_status: scoped.status(),
      explicit_manual_destination_schema: current.destination_schema_version,
      foreign_status: foreign.status(),
      effects_executed: false,
      configuration_only: true,
      actual_dark_theme: actualDarkTheme,
      theme_asserted_in_browser: true,
      contrast,
      screenshots,
      configuration_screenshots: configurationScreenshots,
      errors,
      provider_or_destination_writes: forbidden,
    })
  );
  await verifyScopedEndingEditor(parent, info, target);
  await page.close();
}
