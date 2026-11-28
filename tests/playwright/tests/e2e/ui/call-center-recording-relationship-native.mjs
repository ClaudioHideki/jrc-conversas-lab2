import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Real native APIs, persisted activities/actions, shared form and current profiles.
// Only the established synthetic original-analysis/media boundary is reused.
export async function verifyNativeRecordingRelationship(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const record = target.recordings.allowed;
  const destination = target.customer_records_context.relationship_context;
  const origin = 'http://127.0.0.1:5387';
  const path = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${record.id}/relationship_activities`;
  const url = `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.call_id)}`;
  const dark = info.project.name.endsWith('dark');
  const screenshots = [], errors = [], prohibited = [], posts = [];
  const witness = () => {
    const raw = execFileSync('bundle', ['exec', 'rails', 'runner', 'script/jrc_call_center_recording_relationship_evidence.rb', account, record.id], {
      cwd: process.env.GITHUB_WORKSPACE, env: process.env, timeout: 45000, maxBuffer: 256 * 1024, encoding: 'utf8',
    });
    const row = JSON.parse(raw.trim().split('\n').at(-1));
    expect(row.source_sha).toBe(process.env.GITHUB_SHA);
    expect(row.account_id).toBe(account);
    expect(row.recording_id).toBe(record.id);
    expect(row.actor_role).toBe('agent');
    expect(row.read_only_witness).toBe(true);
    return row;
  };
  const capture = async stage => {
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    expect(await page.evaluate(() => document.documentElement.classList.contains('dark'))).toBe(dark);
    const name = `.codex/call-center-native-e2e/${info.project.name}-recording-relationship-${stage}.png`;
    await page.screenshot({ path: name, fullPage: true });
    screenshots.push(name);
  };
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const requested = new URL(request.url());
    const local = [origin, 'http://127.0.0.1:5386'].includes(requested.origin);
    const create = local && request.method() === 'POST' && requested.pathname === path;
    if (create) {
      const body = request.postDataJSON();
      expect(Object.keys(body)).toEqual(['relationship_activity']);
      const input = body.relationship_activity;
      expect(Object.keys(input).sort()).toEqual(['assignment_id', 'due_at', 'origin_revision', 'request_id', 'title']);
      expect(input.assignment_id).toBe(destination.assignment_id);
      posts.push(input);
    }
    if ((['http:', 'https:'].includes(requested.protocol) && !local) || (!['GET', 'HEAD'].includes(request.method()) && !create)) {
      prohibited.push(`${request.method()} ${requested.origin}${requested.pathname}`);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  await page.addInitScript(({ headers, isDark }) => {
    Reflect.set(window, '__SYNTHETIC_AUTH__', headers);
    document.addEventListener('DOMContentLoaded', () => document.documentElement.classList.toggle('dark', isDark));
  }, { headers: target.operator, isDark: dark });
  try {
    const before = witness();
    expect(before.activity_count).toBe(0);
    await page.goto(url);
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-context-open]').click();
    const entry = page.locator('[data-open-recording-relationship]');
    await expect(entry).toBeVisible();
    const contrast = await measureLocatorTextContrast(entry);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    const previewResponse = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === path);
    await entry.click();
    const preview = await previewResponse;
    expect(preview.status()).toBe(200);
    const source = await preview.json();
    expect(source.user_id).toBe(before.actor_id);
    expect(source.call_id).toBe(record.call_id);
    expect(source.meta).toEqual({ page: 1, per_page: 20, total: 1, pages: 1 });
    expect(source.items.map(row => row.id)).toEqual([destination.assignment_id]);
    expect(before.native_portfolio_group_count).toBe(2);
    expect(before.native_portfolio_link_count).toBe(2);
    expect(source.items.map(row => row.id)).not.toContain(destination.private_assignment_id);
    const dialog = page.getByRole('dialog').filter({ has: page.locator('[data-recording-relationship-editor]') });
    await expect(dialog).toBeVisible();
    const select = dialog.locator('[data-recording-relationship-portfolio]');
    await expect(select).toHaveValue('');
    expect(posts).toHaveLength(0);
    // Native Assignment is unique per company/contact. Multiple named groups
    // share this same identity; they never manufacture extra destination rows.
    const pageTwo = await page.request.get(`${origin}${path}?page=2`, { headers: target.operator });
    expect(pageTwo.status()).toBe(200);
    const secondPage = await pageTwo.json();
    expect(secondPage.meta).toEqual({ page: 2, per_page: 20, total: 1, pages: 1 });
    expect(secondPage.items).toEqual([]);
    await expect(select.locator('option')).toHaveCount(2);
    await expect(dialog.locator('[data-recording-relationship-next]')).toHaveCount(0);
    await expect(select).toHaveValue('');
    await select.selectOption(destination.assignment_id);
    const title = `SYNTHETIC recording Relationship ${info.project.name}`;
    await dialog.locator('[data-native-relationship-activity-title]').fill(title);
    await dialog.locator('[data-native-relationship-activity-deadline]').fill('2026-12-18T10:30');
    await capture('reviewed-existing-form');
    const created = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === path);
    await dialog.locator('form button[type="submit"]').click();
    const response = await created;
    expect(response.status()).toBe(201);
    const receipt = await response.json();
    expect(receipt.replayed).toBe(false);
    expect(receipt.assignment_id).toBe(destination.assignment_id);
    await expect(dialog.locator('[data-recording-relationship-receipt]')).toContainText(receipt.activity_id);
    expect(posts).toHaveLength(1);
    const after = witness();
    expect(after.activity_count).toBe(1);
    expect(after.activities[0]).toMatchObject({ id: receipt.activity_id, assignment_id: destination.assignment_id, title, status: 'scheduled', activity_type: 'call', user_id: before.actor_id });
    expect(after.activities[0].source_manifest.activities.map(String)).toContain(receipt.activity_id);
    const link = dialog.locator('[data-recording-relationship-target]');
    await expect(link).toBeVisible();
    const shown = page.waitForResponse(result => result.request().method() === 'GET' && new URL(result.url()).pathname === `/api/v1/accounts/${account}/crm/activities/${receipt.activity_id}`);
    await link.click();
    expect((await shown).status()).toBe(200);
    await expect(page.getByTestId('activity-title')).toHaveValue(title);
    await expect.poll(() => new URL(page.url()).searchParams.get('activityId')).toBe(receipt.activity_id);
    await expect(page.getByText(title, { exact: true })).toBeVisible();
    await page.reload();
    await expect(page.getByText(title, { exact: true })).toBeVisible();
    await expect(page.getByTestId('activity-title')).toHaveValue(title);
    await capture('native-persisted-activity');
    await page.evaluate(async headers => {
      Object.assign(window.axios.defaults.headers.common, headers);
      await Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')();
    }, target.scoped);
    await expect(page.getByTestId('activity-title')).toHaveCount(0);
    await page.evaluate(async headers => {
      Object.assign(window.axios.defaults.headers.common, headers);
      await Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')();
    }, target.operator);
    const replay = await page.request.post(origin + path, { headers: target.operator, data: { relationship_activity: posts[0] } });
    expect(replay.status()).toBe(201);
    expect(await replay.json()).toMatchObject({ activity_id: receipt.activity_id, replayed: true });
    const conflict = await page.request.post(origin + path, { headers: target.operator, data: { relationship_activity: { ...posts[0], title: title + ' changed' } } });
    expect(conflict.status()).toBe(409);
    const denied = await page.request.post(origin + path, { headers: target.scoped, data: { relationship_activity: posts[0] } });
    expect(denied.status()).toBe(401);
    await page.goto(url);
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-context-open]').click();
    await page.locator('[data-open-recording-relationship]').click();
    await expect(page.locator('[data-recording-relationship-portfolio]')).toBeVisible();
    await page.evaluate(async headers => {
      Object.assign(window.axios.defaults.headers.common, headers);
      await Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')();
    }, target.scoped);
    await expect(page.locator('[data-recording-relationship-editor]')).toHaveCount(0);
    await expect(page.locator('[data-open-recording-relationship]')).toHaveCount(0);
    await capture('current-profile-denied');
    const final = witness();
    expect(final.activities).toEqual(after.activities);
    for (const key of ['qualifications_semantic_sha256', 'ending_attempt_count', 'native_project_tasks', 'PABX_commands', 'native_portfolio_group_count', 'native_portfolio_link_count', 'native_portfolio_links_sha256']) expect(final[key]).toBe(before[key]);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(`.codex/call-center-native-e2e/${info.project.name}-recording-relationship.json`, JSON.stringify({
      sha: process.env.GITHUB_SHA, project: info.project.name, synthetic: true, actual_dark_theme: dark,
      source, receipt, explicit_portfolio_selection: true, native_form_reused: true, native_pagination_verified: false,
      native_unique_identity_verified: true, named_groups_preserved: true,
      native_out_of_range_page: { status: pageTwo.status(), meta: secondPage.meta, items: secondPage.items },
      persisted_and_reloaded_native_activity: true, original_actor_nonadministrator: true,
      native_activity_dialog_reloaded: true, native_activity_profile_withdrawal_cleared: true,
      replay_status: replay.status(), conflict_status: conflict.status(), denied_status: denied.status(),
      current_profile_withdrawal_cleared_private_draft: true, browser_POST_count: posts.length,
      native_before: before, native_after: final, contrast, screenshots, errors, prohibited,
      external_homologation: false, whole_figure_or_Part1_accepted: false,
    }, null, 2) + '\n');
  } catch (error) {
    await page.screenshot({ path: `.codex/call-center-native-e2e/${info.project.name}-recording-relationship-failure.png`, fullPage: true, timeout: 5000 }).catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
