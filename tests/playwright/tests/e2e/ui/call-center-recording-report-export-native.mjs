import { expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Extend the existing recording/quality scenario; no additional call cohort,
// provider request, browser case, public URL or production grant is created.
export async function verifyNativeRecordingReportExport(page, info, target, foreignHeaders) {
  const account = String(target.account_id);
  const member = String(target.operator_id);
  expect(account).toMatch(/^[1-9][0-9]*$/);
  expect(member).toMatch(/^[1-9][0-9]*$/);
  const base = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center`;
  const endpoint = `${base}/reports/recordings/export`;
  const screenshots = [];
  const downloads = [];
  const mediaRequests = [];
  const trackMedia = request => {
    const path = new URL(request.url()).pathname;
    if (/\/recordings\/[^/]+\/(?:playback|download|reproduce)$/.test(path)) mediaRequests.push(path);
  };
  const onDownload = value => downloads.push(value);
  page.on('download', onDownload);
  const dark = info.project.name.endsWith('dark');
  const authority = (operation, original) => {
    const args = ['exec', 'rails', 'runner', 'script/jrc_call_center_recording_report_access.rb', account, member, operation];
    if (original) args.push(JSON.stringify(original));
    const raw = execFileSync('bundle', args, {
      cwd: process.env.GITHUB_WORKSPACE, env: process.env,
      timeout: 45000, maxBuffer: 512 * 1024, encoding: 'utf8',
    });
    const result = JSON.parse(raw.trim().split('\n').at(-1));
    expect(result.source_sha).toBe(process.env.GITHUB_SHA);
    expect(result.account_id).toBe(account);
    expect(result.member_id).toBe(member);
    expect(result.operation).toBe(operation);
    expect(result.synthetic).toBe(true);
    expect(result.external_operations).toBe(false);
    return result;
  };
  const context = async () => {
    const response = await page.request.get(`${base}/context`, { headers: target.operator });
    expect(response.status()).toBe(200);
    const value = await response.json();
    expect(value.account_id).toBe(account);
    expect(value.capabilities.recordings_view).toBe(true);
    return value;
  };
  const capture = async stage => {
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    expect(await page.evaluate(() => document.documentElement.classList.contains('dark'))).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-recording-report-export-${stage}.png`;
    await page.screenshot({ path, fullPage: true });
    screenshots.push(path);
  };
  const readCSV = async expectedIds => {
    const button = page.locator('[data-export-recording-report]');
    await expect(button).toBeEnabled();
    const [response, download] = await Promise.all([
      page.waitForResponse(value => value.url().split('?')[0].replace(':5386/', ':5387/') === endpoint),
      page.waitForEvent('download'),
      button.click(),
    ]);
    expect(response.status()).toBe(200);
    expect(response.headers()['cache-control']).toContain('no-store');
    expect(response.headers()['x-jrc-recording-account']).toBe(account);
    expect(response.headers()['x-jrc-recording-count']).toBe(String(expectedIds.length));
    expect(await download.failure()).toBeNull();
    expect(download.suggestedFilename()).toBe('call-center-gravacoes.csv');
    const file = await download.path();
    const bytes = fs.readFileSync(file);
    expect(bytes.length).toBeGreaterThan(0);
    expect(bytes.length).toBeLessThan(1024 * 1024);
    const digest = createHash('sha256').update(bytes).digest('hex');
    expect(digest).toBe(response.headers()['x-content-sha256']);
    expect(bytes.toString()).not.toMatch(/recording_reference|pabx_password|pabx_username|\/var\/spool\//);
    // Reuse the project's actual Ruby CSV library rather than splitting cells.
    const raw = execFileSync('bundle', ['exec', 'ruby', '-rcsv', '-rjson', '-e',
      "r = CSV.read(ARGV.fetch(0), headers: true); puts JSON.generate(count: r.length, ids: r.map { |v| v['Gravação ID'] }, units: r.map { |v| v['Unidade ID'] }.uniq)",
      file], { cwd: process.env.GITHUB_WORKSPACE, timeout: 15000, maxBuffer: 128 * 1024, encoding: 'utf8' });
    const parsed = JSON.parse(raw);
    expect(parsed.count).toBe(expectedIds.length);
    expect([...parsed.ids].sort()).toEqual([...expectedIds].sort());
    expect(parsed.units).toEqual([String(target.unit_id)]);
    return { sha256: digest, bytes: bytes.length, record_ids: parsed.ids, count: parsed.count,
      native_query: Object.fromEntries(new URL(response.url()).searchParams), temporary_file_not_uploaded: true };
  };
  let original;
  let restoreAttempted = false;
  let restore;
  try {
    expect((await context()).capabilities.reports).toBe(false);
    const profileResponse = await page.request.get('http://127.0.0.1:5387/api/v1/profile', { headers: target.operator });
    expect(profileResponse.status()).toBe(200);
    const profile = await profileResponse.json();
    expect(profile.accounts.find(row => String(row.id) === account).role).toBe('agent');
    const grant = authority('grant');
    expect(grant.actor_id).toBe(String(profile.id));
    original = grant.original_permissions;
    expect((await context()).capabilities.reports).toBe(true);
    expect((await page.request.get(endpoint, { headers: foreignHeaders })).status()).toBe(401);
    expect((await page.request.get(endpoint, { headers: target.operator, params: { unit_id: target.denied_unit_id } })).status()).toBe(404);
    const first = await page.request.get(`${base}/recordings`, { headers: target.operator, params: { page: '1', per_page: '20' } });
    const second = await page.request.get(`${base}/recordings`, { headers: target.operator, params: { page: '2', per_page: '20' } });
    expect(first.status()).toBe(200);
    expect(second.status()).toBe(200);
    const initial = await first.json();
    const final = await second.json();
    expect(initial.meta.total).toBe(21);
    const ids = [...initial.items, ...final.items].map(row => String(row.id));
    expect(new Set(ids).size).toBe(21);
    await page.goto(`/app/accounts/${account}/contact-center/gravacoes?native_navigation=1`);
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    page.on('request', trackMedia);
    const full = await readCSV(ids);
    const contrast = await measureLocatorTextContrast(page.locator('[data-export-recording-report]'));
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await capture('full');
    const allowed = target.recordings.allowed;
    await page.goto(`/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(allowed.call_id)}`);
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recordings-search]').fill('SYNTHETIC unsubmitted search');
    const filtered = await readCSV([String(allowed.id)]);
    expect(filtered.native_query.q).toBe(allowed.call_id);
    expect(filtered.native_query.page).toBeUndefined();
    expect(filtered.native_query.per_page).toBeUndefined();
    await expect(page.locator('[data-recordings-search]')).toHaveValue('SYNTHETIC unsubmitted search');
    await capture('filtered');
    restoreAttempted = true;
    restore = authority('restore', original);
    expect(restore.restored_original_permissions).toBe(true);
    expect(restore.original_permissions_sha256).toBe(grant.original_permissions_sha256);
    expect((await context()).capabilities.reports).toBe(false);
    const denied = page.waitForResponse(value => value.url().split('?')[0].replace(':5386/', ':5387/') === endpoint);
    await page.locator('[data-export-recording-report]').click();
    expect((await denied).status()).toBe(401);
    await expect(page.locator('[data-export-recording-report]')).toHaveCount(0);
    await page.evaluate(() => Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')());
    expect(downloads.length).toBe(2);
    expect(mediaRequests).toEqual([]);
    await capture('denied');
    return { sha: process.env.GITHUB_SHA, account_id: account, member_id: member, actor_id: String(profile.id),
      actual_dark_theme: dark, full, filtered, native_reports_permission_restored: true,
      original_permissions_sha256: restore.original_permissions_sha256,
      foreign_account_status: 401, inaccessible_unit_status: 404, revoked_report_status: 401,
      all_21_rows_not_only_first_20: true, unsaved_search_not_exported: true,
      real_browser_downloads: downloads.length, recording_media_requests: mediaRequests, binary_audio_or_provider_operations: false,
      browser_scale_limit_proof: false, contrast, screenshots };
  } finally {
    page.off('download', onDownload);
    page.off('request', trackMedia);
    if (original && !restoreAttempted) {
      restoreAttempted = true;
      authority('restore', original);
    }
  }
}
