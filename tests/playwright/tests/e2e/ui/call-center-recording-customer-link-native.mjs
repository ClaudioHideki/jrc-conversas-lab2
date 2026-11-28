import { expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Actual native master picker, POST, account/call locks, audit and persisted read.
// No fulfilled API response, made-up contact, provider call or grant mutation.
export async function verifyNativeRecordingCustomerLink(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const api = `/api/v1/accounts/${account}`;
  const origin = 'http://127.0.0.1:5387';
  const headers = target.operator;
  const dark = info.project.name.endsWith('dark');
  const selection = await parent.request.get(
    origin + api + '/jrc_contact_center/recordings?q=extra-02',
    { headers }
  );
  expect(selection.status()).toBe(200);
  const rows = await selection.json();
  expect(rows.meta.total).toBe(1);
  expect(rows.items).toHaveLength(1);
  const record = rows.items[0];
  expect(typeof record.unique_id).toBe('string');
  expect(record.unique_id.length).toBeGreaterThan(0);
  const path =
    api + `/jrc_contact_center/recordings/${record.id}/customer_link`;
  const contactResponse = await parent.request.get(
    origin +
      api +
      `/customers/contacts/${target.customer_records_context.contact_id}`,
    { headers }
  );
  expect(contactResponse.status()).toBe(200);
  const nativeContact = await contactResponse.json();
  const person = nativeContact.payload || nativeContact;
  expect(String(person.id)).toBe(target.customer_records_context.contact_id);
  const errors = [];
  const prohibited = [];
  const posts = [];
  const screenshots = [];
  const witness = () => {
    const raw = execFileSync(
      'bundle',
      [
        'exec',
        'rails',
        'runner',
        'script/jrc_call_center_recording_customer_link_evidence.rb',
        account,
        String(record.id),
      ],
      {
        cwd: process.env.GITHUB_WORKSPACE,
        env: process.env,
        timeout: 45000,
        maxBuffer: 128 * 1024,
        encoding: 'utf8',
      }
    );
    const value = JSON.parse(raw.trim().split('\n').at(-1));
    expect(value.source_sha).toBe(process.env.GITHUB_SHA);
    expect(value.account_id).toBe(account);
    expect(value.recording_id).toBe(String(record.id));
    expect(value.read_only_witness).toBe(true);
    return value;
  };
  const capture = async stage => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(dark);
    const filename = `.codex/call-center-native-e2e/${info.project.name}-recording-customer-link-${stage}.png`;
    await page.screenshot({ path: filename, fullPage: true });
    screenshots.push(filename);
  };
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const local = [origin, 'http://127.0.0.1:5386'].includes(url.origin);
    const link = local && request.method() === 'POST' && url.pathname === path;
    if (link) posts.push(request.postDataJSON());
    if (
      (['http:', 'https:'].includes(url.protocol) && !local) ||
      (!['GET', 'HEAD'].includes(request.method()) && !link)
    ) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
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
    { auth: headers, isDark: dark }
  );
  try {
    const before = witness();
    expect(before.call_id).toBe(record.unique_id);
    expect(before.contact_id).toBeNull();
    expect(before.audit_count).toBe(0);
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.unique_id)}`
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-context-open]').click();
    const context = page.locator('[data-recording-call-context]');
    await expect(context.locator('[data-open-linked-master]')).toHaveCount(0);
    const open = context.locator('[data-open-recording-customer-link]');
    const contrast = await measureLocatorTextContrast(open);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    const previewEvent = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === path &&
        response.request().method() === 'GET'
    );
    await open.click();
    const previewResponse = await previewEvent;
    expect(previewResponse.status()).toBe(200);
    const preview = await previewResponse.json();
    expect(preview).toMatchObject({
      account_id: account,
      recording_id: String(record.id),
      call_session_id: before.call_session_id,
      call_id: before.call_id,
      lock_version: before.lock_version,
      can_link: true,
      already_linked: false,
    });
    const search = context.getByRole('searchbox');
    await search.fill(person.name);
    await search.press('Enter');
    const option = context.getByRole('button').filter({ hasText: person.name });
    await expect(option).toHaveCount(1);
    await option.click();
    await expect(
      context.locator('[data-save-recording-customer-link]')
    ).toBeDisabled();
    expect(posts).toEqual([]);
    await context
      .locator('[data-confirm-recording-customer-link]')
      .scrollIntoViewIfNeeded();
    await capture('selected-before-explicit-confirmation');
    await context.locator('[data-confirm-recording-customer-link]').check();
    const saved = page.waitForResponse(
      response =>
        new URL(response.url()).pathname === path &&
        response.request().method() === 'POST'
    );
    await context.locator('[data-save-recording-customer-link]').click();
    const savedResponse = await saved;
    expect(savedResponse.status()).toBe(200);
    const receipt = await savedResponse.json();
    expect(receipt).toMatchObject({
      account_id: account,
      user_id: preview.user_id,
      recording_id: String(record.id),
      call_session_id: before.call_session_id,
      contact_id: String(person.id),
      lock_version: before.lock_version + 1,
    });
    await expect(
      context.locator('[data-recording-context-contact]')
    ).toHaveText(person.name);
    await expect(context.locator('[data-open-linked-master]')).toBeVisible();
    await expect(
      context.locator('[data-open-recording-customer-link]')
    ).toHaveCount(0);
    await context.locator('[data-open-linked-master]').scrollIntoViewIfNeeded();
    await capture('native-linked-context-and-existing-master');
    const after = witness();
    expect(after.contact_id).toBe(String(person.id));
    expect(after.audit_count).toBe(1);
    expect(after.audits[0].user_id).toBe(preview.user_id);
    expect(after.audits[0].changes.before.contact_id).toBeNull();
    expect(String(after.audits[0].changes.after.contact_id)).toBe(
      String(person.id)
    );
    expect(after.unmodified_call_fields_sha256).toBe(
      before.unmodified_call_fields_sha256
    );
    expect(after.original_recording_sha256).toBe(
      before.original_recording_sha256
    );
    expect(after.native_history).toEqual(before.native_history);
    expect(posts).toEqual([
      {
        customer_link: {
          contact_id: String(person.id),
          call_session_id: before.call_session_id,
          call_id: before.call_id,
          lock_version: before.lock_version,
          confirm: true,
        },
      },
    ]);
    const replay = await parent.request.post(origin + path, {
      headers,
      data: posts[0],
    });
    expect(replay.status()).toBe(409);
    const denied = await parent.request.get(origin + path, {
      headers: target.scoped,
    });
    expect([401, 403, 404]).toContain(denied.status());
    await page.reload();
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-context-open]').click();
    await expect(page.locator('[data-recording-context-contact]')).toHaveText(
      person.name
    );
    await expect(page.locator('[data-open-linked-master]')).toBeVisible();
    await expect(
      page.locator('[data-open-recording-customer-link]')
    ).toHaveCount(0);
    await page.locator('[data-open-linked-master]').scrollIntoViewIfNeeded();
    await capture('persisted-after-native-reload');
    const final = witness();
    expect(final).toEqual(after);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recording-customer-link.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          synthetic: true,
          actual_dark_theme: dark,
          recording_id: String(record.id),
          native_list_unique_id: record.unique_id,
          exact_native_preview: preview,
          exact_native_receipt: receipt,
          native_before: before,
          native_after: final,
          sole_browser_POST: posts[0],
          replay_status: replay.status(),
          denied_status: denied.status(),
          explicit_selection_and_confirmation: true,
          persisted_after_native_reload: true,
          existing_master_picker_reused: true,
          history_not_rewritten: true,
          contrast,
          screenshots,
          errors,
          prohibited,
          no_provider_operation: true,
          whole_figure_or_Part1_accepted: false,
        },
        null,
        2
      ) + '\n'
    );
  } catch (error) {
    await page
      .screenshot({
        path: `.codex/call-center-native-e2e/${info.project.name}-recording-customer-link-owned-failure.png`,
        fullPage: true,
        timeout: 5000,
      })
      .catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
