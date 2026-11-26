import { expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Actual native route, scoped HTTP/PostgreSQL and Chrome audio element.
// Only the explicitly owned PABX byte boundary is substituted, never an authorization or API response.
export async function verifyNativeRecordingHistory(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const root = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center/recordings`;
  const expected = target.recordings.allowed;
  const dark = info.project.name.endsWith('dark');
  const errors = [];
  const prohibited = [];
  const screenshots = [];
  const observations = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    if (outside || !['GET', 'HEAD'].includes(request.method())) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  const install = auth =>
    page.addInitScript(
      ({ headers, isDark }) => {
        const current = sessionStorage.getItem(
          'synthetic-recording-current-profile'
        );
        Reflect.set(
          window,
          '__SYNTHETIC_AUTH__',
          current ? JSON.parse(current) : headers
        );
        document.addEventListener('DOMContentLoaded', () =>
          document.documentElement.classList.toggle('dark', isDark)
        );
      },
      { headers: auth, isDark: dark }
    );
  const capture = async suffix => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    expect(
      await page
        .locator('html')
        .evaluate(node => node.classList.contains('dark'))
    ).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-recordings-${suffix}.png`;
    await page.screenshot({ path });
    screenshots.push(path);
  };
  const read = async (path = root, auth = target.operator, params = {}) => {
    const response = await page.request.get(path, { headers: auth, params });
    observations.push({
      path: new URL(path).pathname,
      status: response.status(),
    });
    return response;
  };
  const open = async () => {
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1`
    );
    await expect(page.locator('[data-scoped-recordings]')).toBeVisible();
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
  };
  try {
    await install(target.operator);
    const profileResponse = await read('http://127.0.0.1:5387/api/v1/profile');
    expect(profileResponse.status()).toBe(200);
    const profile = await profileResponse.json();
    expect(profile.accounts.find(row => String(row.id) === account).role).toBe(
      'agent'
    );
    const rows = await read();
    expect(rows.status()).toBe(200);
    const listed = await rows.json();
    expect(listed.account_id).toBe(account);
    expect(listed.meta).toMatchObject({
      page: 1,
      per_page: 20,
      total: target.authorized_recording_count,
      pages: 2,
    });
    expect(listed.items).toHaveLength(20);
    for (const kind of ['denied_unit', 'denied_tenant', 'unmapped_provider']) {
      expect(
        (await read(`${root}/${target.recordings[kind].id}`)).status()
      ).toBe(404);
      expect(listed.items.map(row => row.id)).not.toContain(
        target.recordings[kind].id
      );
    }
    expect(
      (
        await read(root, target.operator, { unit_id: target.denied_unit_id })
      ).status()
    ).toBe(404);
    await open();
    await page
      .getByRole('button', { name: 'Próxima', exact: true })
      .last()
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await expect(page).toHaveURL(/recordings_page=2/);
    await page.reload();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page
      .getByRole('button', { name: 'Anterior', exact: true })
      .last()
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    await page.locator('[data-recordings-from]').fill(listed.period.from);
    await page.locator('[data-recordings-to]').fill(listed.period.to);
    const targets = page.locator('[data-acw-rule-target] select');
    await targets.nth(0).selectOption(String(target.unit_id));
    await targets.nth(1).selectOption(String(target.queue_id));
    expect(
      await targets
        .nth(0)
        .locator('option')
        .evaluateAll(rows => rows.map(row => row.value))
    ).not.toContain(String(target.denied_unit_id));
    await page.locator('[data-recordings-search]').fill(expected.call_id);
    await page
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await expect(page).toHaveURL(/recordings_q=/);
    await page.reload();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await expect(page.locator('[data-recordings-search]')).toHaveValue(
      expected.call_id
    );
    await expect(page.locator('[data-recordings-from]')).toHaveValue(
      listed.period.from
    );
    await expect(page.locator('[data-recordings-to]')).toHaveValue(
      listed.period.to
    );
    await expect(targets.nth(0)).toHaveValue(String(target.unit_id));
    await expect(targets.nth(1)).toHaveValue(String(target.queue_id));
    await expect(page.locator('[data-recordings-period]')).toContainText(
      listed.period.timezone
    );
    const selected = page.locator('[data-recording-selected]');
    await page.locator(`[data-recording-details="${expected.id}"]`).click();
    await expect(selected).toBeVisible();
    await expect(selected.locator('audio')).toHaveCount(0);
    const [contrast] = await page
      .locator('[data-scoped-recordings] h1')
      .evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await capture('authorized-list');
    const playback = page.waitForResponse(response =>
      new URL(response.url()).pathname.endsWith(`/${expected.id}/playback`)
    );
    await selected.locator('[data-recording-listen]').click();
    const bytes = await playback;
    expect(bytes.status()).toBe(200);
    expect(bytes.headers()['x-jrc-recording-account']).toBe(account);
    expect(bytes.headers()['x-jrc-recording-id']).toBe(expected.id);
    const body = await bytes.body();
    expect(body.byteLength).toBe(48044);
    expect(body.subarray(0, 4).toString()).toBe('RIFF');
    expect(bytes.headers()['cache-control']).toContain('no-store');
    const audio = selected.locator('audio');
    await expect
      .poll(() => audio.evaluate(element => element.duration))
      .toBe(3);
    await selected.locator('[data-native-recording-play]').click();
    await expect
      .poll(() => audio.evaluate(element => element.currentTime))
      .toBeGreaterThan(0);
    await selected.locator('[data-native-recording-play]').click();
    await expect
      .poll(() => audio.evaluate(element => element.paused))
      .toBe(true);
    await selected.locator('input[type="range"]').evaluate(element => {
      element.value = '1';
      element.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await expect
      .poll(() => audio.evaluate(element => element.currentTime))
      .toBe(1);
    await selected.scrollIntoViewIfNeeded();
    await capture('actual-player');
    const download = page.waitForEvent('download');
    const downloadedResponse = page.waitForResponse(response =>
      new URL(response.url()).pathname.endsWith(`/${expected.id}/download`)
    );
    await selected.locator('[data-recording-download]').click();
    expect((await downloadedResponse).status()).toBe(200);
    expect((await download).suggestedFilename()).toBe(
      `call-${expected.id}.wav`
    );
    await page
      .getByRole('button', { name: 'Limpar filtros', exact: true })
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    await expect(selected).toHaveCount(0);
    expect(new URL(page.url()).searchParams.get('recordings_q')).toBeNull();
    expect(new URL(page.url()).searchParams.get('recordings_from')).toBeNull();
    expect(new URL(page.url()).searchParams.get('recordings_to')).toBeNull();
    await expect(page.locator('[data-recordings-from]')).toHaveValue('');
    await expect(page.locator('[data-recordings-to]')).toHaveValue('');
    // Full reload with the existing native viewer token: own history remains, download permission does not.
    await page.evaluate(
      headers =>
        sessionStorage.setItem(
          'synthetic-recording-current-profile',
          JSON.stringify(headers)
        ),
      target.scoped
    );
    await open();
    await page.locator('[data-recordings-search]').fill(expected.call_id);
    await page
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator(`[data-recording-details="${expected.id}"]`).click();
    await expect(selected.locator('[data-recording-download]')).toHaveCount(0);
    await expect(selected.locator('[data-recording-listen]')).toBeVisible();
    const viewerProfileResponse = await read(
      'http://127.0.0.1:5387/api/v1/profile',
      target.scoped
    );
    expect(viewerProfileResponse.status()).toBe(200);
    const viewerProfile = await viewerProfileResponse.json();
    expect(viewerProfile.id).not.toBe(profile.id);
    const viewerMember = viewerProfile.accounts.find(
      row => String(row.id) === account
    );
    expect(viewerMember.role).toBe('agent');
    expect(viewerMember.permissions).not.toContain(
      'jrc_contact_center_recordings_download'
    );
    const viewerPlayback = page.waitForResponse(response =>
      new URL(response.url()).pathname.endsWith(`/${expected.id}/playback`)
    );
    await selected.locator('[data-recording-listen]').click();
    const viewerBytes = await viewerPlayback;
    expect(viewerBytes.status()).toBe(200);
    expect(
      createHash('sha256')
        .update(await viewerBytes.body())
        .digest('hex')
    ).toBe(createHash('sha256').update(body).digest('hex'));
    const viewerAudio = selected.locator('audio');
    await expect
      .poll(() => viewerAudio.evaluate(element => element.duration))
      .toBe(3);
    await selected.locator('[data-native-recording-play]').click();
    await expect
      .poll(() => viewerAudio.evaluate(element => element.currentTime))
      .toBeGreaterThan(0);
    await expect(
      selected.locator('[data-native-recording-download]')
    ).toHaveCount(0);
    expect(
      (await read(`${root}/${expected.id}/download`, target.scoped)).status()
    ).toBe(401);
    await selected.scrollIntoViewIfNeeded();
    await capture('native-viewer');
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
    const receipt = JSON.parse(raw.trim().split('\n').at(-1));
    expect(receipt.source_sha).toBe(process.env.GITHUB_SHA);
    expect(receipt.account_id).toBe(Number(account));
    expect(receipt.owned_record_count).toBe(24);
    expect(receipt.media_bytes).toBe(body.byteLength);
    expect(receipt.media_sha256).toBe(
      createHash('sha256').update(body).digest('hex')
    );
    const operations = receipt.operations.filter(
      row =>
        row.auditable_type === 'TelephonyCallRecord' &&
        String(row.record_id) === expected.id
    );
    expect(
      operations.filter(row => row.changes.operation === 'listen')
    ).toHaveLength(2);
    expect(
      operations.filter(row => row.changes.operation === 'download')
    ).toHaveLength(1);
    expect(
      new Set(
        operations
          .filter(row => row.changes.operation === 'listen')
          .map(row => String(row.user_id))
      )
    ).toEqual(new Set([String(profile.id), String(viewerProfile.id)]));
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recordings-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          synthetic: true,
          account_id: account,
          provider_boundary: target.recording_provider_boundary,
          actual_dark_theme: dark,
          authorized_rows: listed.meta.total,
          denied_unit_tenant_and_unmapped_provider: true,
          real_pagination_filter_URL_and_reload: true,
          original_operator_nonadministrator: true,
          private_audio: {
            bytes: body.byteLength,
            sha256: createHash('sha256').update(body).digest('hex'),
            duration_seconds: 3,
          },
          separate_listen_download_authority: true,
          actual_viewer_without_download_reproduced_audio: true,
          actual_pause_and_position_seek: true,
          native_read_audit: receipt,
          contrast,
          screenshots,
          page_errors: errors,
          prohibited_requests: prohibited,
          whole_figure17_accepted: false,
          external_PABX_homologated: false,
        },
        null,
        2
      )
    );
  } finally {
    await page.close();
  }
}
