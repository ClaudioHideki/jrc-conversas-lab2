import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureTextContrast } from './call-center-text-contrast.mjs';
import { endingActivationURL, isEndingActivationRequest } from './call-center-ending-activation-request.mjs';

// Own per-project synthetic account, real Vue/CSS and authenticated native APIs.
// Activation writes prospective metadata only. No call/provider is simulated as
// operational traffic and no destination write is allowed from this browser.
export async function verifyEndingActivation(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}`;
  const endpoint = `${root}/jrc_contact_center/acw_policy/ending_rules`;
  const location = `/app/accounts/${account}/contact-center/control-desk/closures`;
  const headers = target.administrator;
  const dark = info.project.name.endsWith('dark');
  const posts = [];
  const violations = [];
  const errors = [];
  const screenshots = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (isEndingActivationRequest(request, account))
      posts.push(request.postDataJSON());
  });
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const external =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    const prohibited =
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration|tasks)(?:[/?]|$)/.test(url.pathname);
    if (external || prohibited) {
      violations.push(url.origin + url.pathname);
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
    { auth: headers, isDark: dark }
  );

  const current = async () => {
    const response = await page.request.get(endpoint, { headers });
    expect(response.status()).toBe(200);
    return response.json();
  };
  const taskTotal = async () => {
    const response = await page.request.get(
      `${root}/projects/projects/${target.automation_project_id}/tasks`,
      { headers }
    );
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(Number.isInteger(data.meta.total)).toBe(true);
    return data.meta.total;
  };
  const tasksBefore = await taskTotal();
  const source = await page.request.get(`${endpoint}/source_context`, {
    headers,
    params: { queue_id: String(target.queue_id) },
  });
  expect(source.status()).toBe(200);
  const sourceData = await source.json();
  const rule = {
    code: 'SYNTHETIC_BROWSER_ACTIVATION',
    name: 'SYNTHETIC explicitly reviewed activation',
    reason_code: target.automation_reason,
    queue_id: String(target.queue_id),
    scope_revision: sourceData.item.scope_revision,
    timing: 'acw_completed',
    execution_mode: 'automatic',
    active: true,
    conditions: { outcome_codes: [] },
    actions: [{
      kind: 'project_task',
      parameters: {
        project_id: target.automation_project_id,
        due_after_days: null,
        attributes: {
          title: 'SYNTHETIC no destination effect from activation',
          priority: 'medium',
          estimated_minutes: 0,
          board_column_id: target.automation_column_id,
        },
      },
    }],
  };
  const save = async document => {
    const latest = await current();
    const response = await page.request.post(endpoint, {
      headers,
      data: { private_rule: document, expected_revision: latest.revision },
    });
    expect(response.status()).toBe(200);
    return response.json();
  };
  await save(rule);
  const open = async (name, reviewed = false) => {
    await page.goto(location);
    await page.locator('[data-manage-ending-reasons]').click();
    await page.locator('[data-ending-automations-open]').click();
    const editor = page.locator('[data-ending-automation-editor]');
    await editor.locator('[data-ending-rule-search]').fill(name);
    await editor.locator('[data-ending-rule-filters] button[type=submit]').click();
    const entry = editor.locator('[data-ending-rule-entry]').filter({ hasText: name });
    await expect(entry).toHaveCount(1);
    await entry.locator('[data-ending-rule-edit]').click();
    const panel = editor.locator('[data-ending-rule-activation]');
    await expect(panel).toBeVisible();
    if (reviewed)
      await expect(panel.locator('[data-ending-activation-receipt]')).toBeVisible();
    else
      await expect(panel.locator('[data-ending-activation-reviewed]')).toBeEnabled();
    await panel.scrollIntoViewIfNeeded();
    return panel;
  };
  const capture = async label => {
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-activation-${label}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  };
  let panel = await open(rule.name);
  expect(posts).toHaveLength(0);
  await expect(panel.locator('[data-ending-activation-confirm]')).toBeDisabled();
  const [contrast] = await panel.locator('h4').evaluate(measureTextContrast);
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await capture('review');
  await panel.locator('[data-ending-activation-reviewed]').check();
  const acknowledged = page.waitForResponse(response => response.url() === endingActivationURL(account) && isEndingActivationRequest(response.request(), account));
  await panel.locator('[data-ending-activation-confirm]').click();
  const response = await acknowledged;
  expect(response.status()).toBe(200);
  const receipt = (await response.json()).item;
  expect(receipt).toMatchObject({ rule_code: rule.code, prospective_only: true });
  expect(receipt.version_id).toMatch(/^[1-9][0-9]*$/);
  await expect(panel.locator('[data-ending-activation-receipt]')).toBeVisible();
  expect(posts).toHaveLength(1);
  await capture('recorded');
  const replay = await page.request.post(`${endpoint}/activate`, {
    headers,
    data: posts[0],
  });
  expect(replay.status()).toBe(200);
  expect((await replay.json()).item).toEqual(receipt);
  panel = await open(rule.name, true);
  await expect(panel.locator('[data-ending-activation-receipt]')).toBeVisible();
  const persisted = await page.request.get(`${endpoint}/readiness`, {
    headers,
    params: { rule_code: rule.code, expected_revision: (await current()).revision },
  });
  expect(persisted.status()).toBe(200);
  expect((await persisted.json()).applicable_review).toEqual(receipt);
  expect(posts).toHaveLength(1);
  expect(await taskTotal()).toBe(tasksBefore);

  const staleRule = { ...rule, code: 'SYNTHETIC_BROWSER_STALE_ACTIVATION', name: 'SYNTHETIC stale activation' };
  await save(staleRule);
  panel = await open(staleRule.name);
  await save({ ...staleRule, name: 'SYNTHETIC changed after browser review' });
  await panel.locator('[data-ending-activation-reviewed]').check();
  const rejected = page.waitForResponse(item => item.url() === endingActivationURL(account) && isEndingActivationRequest(item.request(), account));
  await panel.locator('[data-ending-activation-confirm]').click();
  expect((await rejected).status()).toBe(409);
  await expect(panel.locator('[data-ending-activation-confirm]')).toBeDisabled();
  await expect(panel.locator('[data-ending-activation-reload]')).toBeVisible();
  expect(posts).toHaveLength(2);
  await capture('stale');
  const latest = await current();
  const denied = await page.request.post(`${endpoint}/activate`, {
    headers: target.operator,
    data: { ...posts[1], expected_revision: latest.revision },
  });
  expect([401, 403]).toContain(denied.status());
  expect(await denied.text()).not.toContain('SYNTHETIC no destination effect');
  expect(await taskTotal()).toBe(tasksBefore);
  const actualDark = await page.evaluate(() => document.documentElement.classList.contains('dark'));
  expect(actualDark).toBe(dark);
  expect(errors).toEqual([]);
  expect(violations).toEqual([]);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ending-activation-native.json`,
    JSON.stringify({
      sha: process.env.GITHUB_SHA,
      synthetic: true,
      project: info.project.name,
      account_id: account,
      activation_status: 200,
      receipt_id: receipt.id,
      version_id: receipt.version_id,
      reviewed_revision: posts[0].expected_revision,
      persisted_reload_verified: true,
      explicit_same_key_replay_verified: true,
      no_implicit_UI_post: true,
      UI_post_count: posts.length,
      stale_status: 409,
      denied_status: denied.status(),
      native_task_count_before: tasksBefore,
      native_task_count_after: await taskTotal(),
      actual_dark_theme: actualDark,
      contrast,
      screenshots,
      errors,
      prohibited_provider_or_destination_writes: violations,
      call_or_broker_operations_claimed: false,
    })
  );
  await page.close();
}
