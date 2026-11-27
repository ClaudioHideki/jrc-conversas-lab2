import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast as measureTextContrast } from './call-center-text-contrast.mjs';

// Extend the existing four native quality cases; real APIs, policies, SQL and source-boundary fixture remain unchanged.
export async function verifyNativeTranscript(
  parent,
  page,
  info,
  target,
  capture
) {
  const account = String(target.account_id);
  const recording = target.recordings.allowed;
  const suffix = '/quality_review/transcript';
  const path = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${recording.id}${suffix}`;
  const profileResponse = await parent.request.get(
    'http://127.0.0.1:5387/api/v1/profile',
    { headers: target.scoped }
  );
  expect(profileResponse.status()).toBe(200);
  const currentActor = await profileResponse.json();
  expect(
    currentActor.accounts.find(row => String(row.id) === account).role
  ).toBe('agent');
  const observed = [];
  page.on('response', response => {
    if (new URL(response.url()).pathname === path)
      observed.push(response.status());
  });
  await page
    .locator('[data-quality-review]')
    .getByRole('button', { name: 'Cancelar', exact: true })
    .click();
  await expect(page.locator('[data-quality-review]')).toHaveCount(0);
  const response = page.waitForResponse(
    row => new URL(row.url()).pathname === path
  );
  await page.locator('[data-recording-transcript-open]').click();
  const firstResponse = await response;
  expect(firstResponse.status()).toBe(200);
  const first = await firstResponse.json();
  expect(first.account_id).toBe(account);
  expect(first.recording_id).toBe(recording.id);
  expect(first.call_id).toBe(recording.call_id);
  expect(first.text).toBe('SYNTHETIC original transcript never changed');
  expect(first.segments).toEqual([]);
  expect(first.temporal_alignment).toBe('not_supplied_by_native_source');
  await expect(page.locator('[data-transcript-text]')).toHaveText(first.text);
  await expect(page.locator('[data-transcript-timing-limit]')).toContainText(
    'não fornece marcações de tempo'
  );
  await expect(page.locator('[data-recording-transcript] audio')).toHaveCount(
    0
  );
  const contrast = await measureTextContrast(
    page.locator('[data-transcript-text] p').first()
  );
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  await capture(page, 'transcript-original');
  await page.locator('[data-transcript-search]').fill('NEVER CHANGED');
  await expect(page.locator('[data-transcript-block]')).toHaveCount(1);
  await expect(page.locator('[data-transcript-block]')).toHaveText(first.text);
  await page
    .locator('[data-transcript-search]')
    .fill('SYNTHETIC absent search');
  await expect(page.locator('[data-transcript-no-matches]')).toBeVisible();
  await capture(page, 'transcript-search');
  expect(observed).toEqual([200]);
  await page.reload();
  await expect(page.locator('[data-recording-row]')).toHaveCount(1);
  await page.locator('[data-recording-details]').click();
  await page.locator('[data-recording-transcript-open]').click();
  await expect(page.locator('[data-transcript-text]')).toHaveText(first.text);
  await expect(page.locator('[data-transcript-search]')).toHaveValue('');
  await expect(page.locator('[data-transcript-source]')).toContainText(
    first.source_sha256
  );
  await capture(page, 'transcript-reloaded');
  expect(observed).toEqual([200, 200]);
  await page.locator('[data-recording-listen]').click();
  await expect(page.locator('[data-recording-selected] audio')).toHaveCount(1);
  const volume = page.locator('[data-native-recording-volume]');
  await volume.press('Home');
  await volume.press('ArrowRight');
  expect(
    await page
      .locator('[data-recording-selected] audio')
      .evaluate(audio => audio.volume)
  ).toBeCloseTo(0.05);
  expect(
    await page
      .locator('[data-recording-selected] audio')
      .evaluate(audio => audio.paused)
  ).toBe(true);
  expect(
    await page
      .locator('[data-recording-selected]')
      .evaluate(element => element.scrollWidth <= element.clientWidth)
  ).toBe(true);
  await volume.scrollIntoViewIfNeeded();
  await capture(page, 'transcript-audio-volume');
  const denied = await Promise.all(
    ['denied_unit', 'denied_tenant', 'unmapped_provider'].map(async kind => {
      const url = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center/recordings/${target.recordings[kind].id}${suffix}`;
      const result = await parent.request.get(url, { headers: target.scoped });
      expect(result.status()).toBe(404);
      expect(await result.text()).not.toContain('original transcript');
      return { kind, status: result.status() };
    })
  );
  const raw = execFileSync(
    'bundle',
    [
      'exec',
      'rails',
      'runner',
      'script/jrc_call_center_recordings_evidence.rb',
      account,
    ],
    {
      cwd: process.env.GITHUB_WORKSPACE,
      env: process.env,
      timeout: 45000,
      maxBuffer: 256 * 1024,
      encoding: 'utf8',
    }
  );
  const native = JSON.parse(raw.trim().split('\n').at(-1));
  expect(native.source_sha).toBe(process.env.GITHUB_SHA);
  const receipts = native.operations.filter(
    row => row.changes.operation === 'transcript'
  );
  expect(receipts).toHaveLength(2);
  expect(
    receipts.every(
      row => String(row.record_id) === recording.id && row.action === 'read'
    )
  ).toBe(true);
  expect(receipts.every(row => row.user_id === currentActor.id)).toBe(true);
  expect(
    receipts.every(
      row =>
        row.changes.cc_scope.before.unit_id &&
        row.changes.cc_scope.before.queue_id
    )
  ).toBe(true);
  expect(JSON.stringify(receipts)).not.toContain(first.text);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-transcript-native.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: account,
        recording_id: recording.id,
        synthetic: true,
        first,
        contrast,
        native,
        transcript_read_receipts: receipts,
        denied,
        current_actor_id: currentActor.id,
        actual_dark_theme: await page.evaluate(() =>
          document.documentElement.classList.contains('dark')
        ),
        native_volume_value: 0.05,
        volume_change_did_not_start_audio: true,
        screenshots: [
          'transcript-original',
          'transcript-search',
          'transcript-reloaded',
          'transcript-audio-volume',
        ].map(
          name =>
            `.codex/call-center-native-e2e/${info.project.name}-quality-${name}.png`
        ),
        original_preserved_after_human_review: true,
        local_text_search_without_extra_fetch_or_media_seek: true,
        explicit_missing_timing_without_manufactured_segments: true,
        existing_four_mode_quality_case_extended: true,
        external_Nico_homologation: false,
        synchronized_segment_acceptance: false,
      },
      null,
      2
    )
  );
}
