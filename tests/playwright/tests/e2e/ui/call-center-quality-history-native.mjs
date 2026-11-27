import { expect } from '@playwright/test';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast as measureTextContrast } from './call-center-text-contrast.mjs';

// Real native fixture preparation uses a second existing recording, leaving the original three UI-created revisions untouched.
export async function verifyNativeQualityHistory(
  parent,
  page,
  info,
  target,
  capture
) {
  const account = String(target.account_id);
  const record = target.quality_history_record;
  const path = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${record.id}/quality_review`;
  const endpoint = `http://127.0.0.1:5387${path}`;
  const headResponse = await parent.request.get(endpoint, {
    headers: target.operator,
  });
  expect(headResponse.status()).toBe(200);
  const head = await headResponse.json();
  expect(head.revision).toBe(0);
  await Array.from({ length: 21 }).reduce(async (previous, _, index) => {
    await previous;
    const response = await parent.request.post(endpoint, {
      headers: target.operator,
      data: {
        quality_review: {
          request_id: randomUUID(),
          expected_revision: index,
          expected_source_sha256: head.source_sha256,
          classification: ['positive', 'neutral', 'negative'][index % 3],
          adjusted_summary: `SYNTHETIC authorized history revision ${index + 1}`,
          adjusted_themes: [],
          recommendation_ids: [],
          justification: `SYNTHETIC authorized history reason ${index + 1}`,
        },
      },
    });
    expect(response.status()).toBe(200);
    expect((await response.json()).item.revision).toBe(index + 1);
  }, Promise.resolve());
  await page.goto(
    `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.call_id)}`
  );
  await expect(page.locator('[data-recording-row]')).toHaveCount(1);
  await page.locator('[data-recording-details]').click();
  const historyResponse = page.waitForResponse(
    response => new URL(response.url()).pathname === path + '/history'
  );
  await page.locator('[data-recording-quality-history-open]').click();
  const initial = await historyResponse;
  expect(initial.status()).toBe(200);
  const first = await initial.json();
  expect(first.account_id).toBe(account);
  expect(first.recording_id).toBe(record.id);
  expect(first.meta).toMatchObject({
    page: 1,
    per_page: 20,
    total: 21,
    pages: 2,
  });
  expect(first.items.map(row => row.revision)).toEqual(
    Array.from({ length: 20 }, (_, index) => 21 - index)
  );
  const history = page.locator('[data-quality-review-history]');
  await expect(history.locator('[data-quality-history-revision]')).toHaveCount(
    20
  );
  await expect(
    history.locator('[data-quality-history-original]').first()
  ).toHaveText('SYNTHETIC original immutable summary');
  await expect(
    history.locator('[data-quality-history-adjusted]').first()
  ).toHaveText('SYNTHETIC authorized history revision 21');
  await expect(
    history.locator('[data-quality-history-reason]').first()
  ).toContainText('SYNTHETIC authorized history reason 21');
  await expect(history.locator('[data-quality-history-source]')).toContainText(
    first.timezone
  );
  await expect(
    history.locator('[data-quality-history-source-version]').first()
  ).toContainText(head.source_sha256);
  const contrast = await measureTextContrast(
    history.locator('[data-quality-history-original]').first()
  );
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await history.scrollIntoViewIfNeeded();
  await capture(page, 'immutable-revision-history-first-page');
  const nextResponse = page.waitForResponse(response => {
    const url = new URL(response.url());
    return (
      url.pathname === path + '/history' && url.searchParams.get('page') === '2'
    );
  });
  await history.locator('[data-quality-history-next]').click();
  const next = await nextResponse;
  expect(next.status()).toBe(200);
  const second = await next.json();
  expect(second.meta).toMatchObject({ page: 2, per_page: 20, total: 21 });
  expect(second.items.map(row => row.revision)).toEqual([1]);
  await expect(history.locator('[data-quality-history-revision]')).toHaveCount(
    1
  );
  await expect(history.locator('[data-quality-history-adjusted]')).toHaveText(
    'SYNTHETIC authorized history revision 1'
  );
  await expect(history.locator('[data-quality-history-next]')).toBeDisabled();
  await capture(page, 'immutable-revision-history-second-page');
  const previousResponse = page.waitForResponse(response => {
    const url = new URL(response.url());
    return (
      url.pathname === path + '/history' && url.searchParams.get('page') === '1'
    );
  });
  await history.locator('[data-quality-history-previous]').click();
  expect((await previousResponse).status()).toBe(200);
  await expect(history.locator('[data-quality-history-revision]')).toHaveCount(
    20
  );
  await expect(page.locator('[data-quality-save]')).toHaveCount(0);
  await capture(page, 'immutable-revision-history-restored');
  const listener = await parent.request.get(endpoint + '/history', {
    headers: target.scoped,
    params: { page: 1 },
  });
  expect(listener.status()).toBe(200);
  const denied = await parent.request.post(endpoint, {
    headers: target.scoped,
    data: {
      quality_review: { expected_revision: 21, request_id: randomUUID() },
    },
  });
  expect(denied.status()).toBe(401);
  const raw = execFileSync(
    'bundle',
    [
      'exec',
      'rails',
      'runner',
      'script/jrc_call_center_quality_review_evidence.rb',
      account,
      record.id,
    ],
    {
      cwd: process.env.GITHUB_WORKSPACE,
      env: process.env,
      encoding: 'utf8',
      timeout: 45000,
      maxBuffer: 512 * 1024,
    }
  );
  const native = JSON.parse(raw.trim().split('\n').at(-1));
  expect(native.source_sha).toBe(process.env.GITHUB_SHA);
  expect(native.actual_native_revisions.map(row => row.revision)).toEqual(
    Array.from({ length: 21 }, (_, index) => index + 1)
  );
  expect(native.native_audits).toHaveLength(21);
  const expectedIds = native.actual_native_revisions.map(row => row.id).sort();
  expect([...first.items, ...second.items].map(row => row.id).sort()).toEqual(
    expectedIds
  );
  expect(
    native.native_audits.map(row => String(row.auditable_id)).sort()
  ).toEqual(expectedIds);
  expect(
    new Set(native.actual_native_revisions.map(row => row.actor_id)).size
  ).toBe(1);
  expect(new Set(native.native_audits.map(row => String(row.user_id)))).toEqual(
    new Set(native.actual_native_revisions.map(row => row.actor_id))
  );
  expect(native.PABX_commands).toBe(0);
  expect(native.ending_destination_actions).toBe(0);
  expect(native.existing_records_modified_by_evidence).toBe(false);
  expect(
    new Set(native.actual_native_revisions.map(row => row.source_sha256))
  ).toEqual(new Set([head.source_sha256]));
  expect(
    native.actual_native_revisions.every(
      row =>
        row.original.sentimento_cliente === 'positivo' &&
        row.original.nota_final === 0
    )
  ).toBe(true);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-quality-history-native.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: account,
        recording_id: record.id,
        synthetic: true,
        fixture_setup:
          '21 real authenticated native writes on a second existing owned recording, not UI creation evidence',
        original_three_UI_corrections_not_modified: true,
        first,
        second,
        native,
        contrast,
        real_scoped_API_pagination_and_return: true,
        immutable_original_compared_with_human_revisions: true,
        listening_did_not_grant_review_writes: true,
        no_provider_homologation: true,
        actual_dark_theme: await page.evaluate(() =>
          document.documentElement.classList.contains('dark')
        ),
        screenshots: [
          'immutable-revision-history-first-page',
          'immutable-revision-history-second-page',
          'immutable-revision-history-restored',
        ].map(
          name =>
            `.codex/call-center-native-e2e/${info.project.name}-quality-${name}.png`
        ),
        whole_figure23_accepted: false,
      },
      null,
      2
    )
  );
}
