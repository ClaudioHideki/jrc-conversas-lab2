import { verifyNativeRecordingReportExport } from './call-center-recording-report-export-native.mjs';
import { expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Real Rails, both recording scopes, PostgreSQL, CSS and existing detail dialog.
// Only Nico source I/O uses the explicitly owned original-analysis boundary.
export async function verifyNativeRecordingQualityReport(
  parent,
  info,
  target,
  foreignHeaders
) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const api = `http://127.0.0.1:5387/api/v1/accounts/${account}/jrc_contact_center/recordings`;
  const screenshots = [];
  const errors = [];
  const prohibited = [];
  const dark = info.project.name.endsWith('dark');
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
    const path = `.codex/call-center-native-e2e/${info.project.name}-recording-quality-report-${stage}.png`;
    await page.screenshot({ path, fullPage: true });
    screenshots.push(path);
  };
  const read = (headers, params = {}) =>
    parent.request.get(`${api}/quality_report`, { headers, params });
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    if (
      (['http:', 'https:'].includes(url.protocol) &&
        !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(
          url.origin
        )) ||
      !['GET', 'HEAD'].includes(request.method())
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
    { auth: target.operator, isDark: dark }
  );
  try {
    const initial = await read(target.operator);
    expect(initial.status()).toBe(200);
    expect(initial.headers()['cache-control']).toContain('no-store');
    const full = await initial.json();
    expect(full.account_id).toBe(account);
    expect(full.meta.total).toBe(21);
    expect(full.items).toHaveLength(20);
    expect(full.quality_summary).toMatchObject({
      universe: 21,
      analyzed: 21,
      without_analysis: 0,
      unclassified: 0,
      counts: { positivo: 21, neutro: 0, negativo: 0 },
      percentages: { positivo: 100, neutro: 0, negativo: 0 },
      quality_measured: 21,
      quality_average: 0,
      denominator: 'latest_original_analyses',
    });
    expect((await read(foreignHeaders)).status()).toBe(401);
    expect(
      (await read(target.operator, { unit_id: target.denied_unit_id })).status()
    ).toBe(404);
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_mode=quality`
    );
    const summary = page.locator('[data-recording-quality-summary]');
    await expect(summary).toBeVisible();
    await expect(summary.locator('[data-quality-denominator]')).toContainText(
      '21 análises'
    );
    await expect(summary.locator('[data-quality-score]')).toContainText(
      'qualidade: 0'
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    const contrast = await Promise.all(
      [
        'all',
        'positivo',
        'neutro',
        'negativo',
        'unclassified',
        'without_analysis',
      ].map(async key => {
        const measured = await measureLocatorTextContrast(
          summary.locator(`[data-quality-filter="${key}"] > span`).first()
        );
        expect(measured.ratio).toBeGreaterThanOrEqual(4.5);
        return { key, ...measured };
      })
    );
    await capture('period');
    await page.locator('[data-scoped-recordings] > nav button').last().click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    expect(new URL(page.url()).searchParams.get('recordings_page')).toBe('2');
    await page.reload();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await expect(summary.locator('[data-quality-denominator]')).toContainText(
      '21 análises'
    );
    await capture('page2');
    await summary.locator('[data-quality-filter="negativo"]').click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(0);
    await expect(
      summary.locator('[data-quality-filter="negativo"]')
    ).toHaveAttribute('aria-pressed', 'true');
    expect(new URL(page.url()).searchParams.get('recordings_page')).toBeNull();
    await expect(summary.locator('[data-quality-denominator]')).toContainText(
      '21 análises'
    );
    await capture('negative');
    await summary.locator('[data-quality-filter="all"]').click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    await page
      .locator('[data-recordings-search]')
      .fill(target.recordings.allowed.call_id);
    await page
      .getByRole('button', { name: 'Aplicar filtros', exact: true })
      .click();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await expect(summary.locator('[data-quality-denominator]')).toContainText(
      '1 análises'
    );
    await page.locator('[data-recording-details]').click();
    const details = page.locator('[data-recording-selected]');
    await expect(details).toBeVisible();
    await expect(
      details.locator('[data-recording-tabs] [role="tab"]')
    ).toHaveCount(5);
    await capture('details');
    await details.locator('[data-recording-close]').click();
    await expect(details).toHaveCount(0);
    await page.evaluate(async auth => {
      Object.assign(window.axios.defaults.headers.common, auth);
      await Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')();
    }, target.scoped);
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    await expect(details.locator('[data-recording-download]')).toHaveCount(0);
    await expect(details.locator('[data-recording-quality-open]')).toHaveCount(
      0
    );
    await capture('readonly');
    await details.locator('[data-recording-close]').click();
    await page.locator('[data-recordings-mode="recordings"]').click();
    await expect(page.locator('[data-recording-quality-summary]')).toHaveCount(
      0
    );
    expect(new URL(page.url()).searchParams.get('recordings_mode')).toBeNull();
    const navigation = page.locator('[data-contact-center-navigation]');
    const openMenu = async () => {
      if (!(await navigation.isVisible()))
        await page.locator('header button[aria-expanded]').click();
    };
    await openMenu();
    const qualityLink = navigation.locator(
      '[data-contact-center-destination="quality"]'
    );
    const recordingsLink = navigation.locator(
      '[data-contact-center-destination="jrc_contact_center_recordings"]'
    );
    await expect(recordingsLink).toHaveAttribute('aria-current', 'page');
    await expect(qualityLink).toHaveAttribute('aria-current', 'false');
    await qualityLink.click();
    await expect(summary).toBeVisible();
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    expect(new URL(page.url()).searchParams.get('recordings_mode')).toBe(
      'quality'
    );
    if (info.project.name.startsWith('mobile'))
      await expect(
        page.locator('header button[aria-expanded]')
      ).toHaveAttribute('aria-expanded', 'false');
    await openMenu();
    await expect(qualityLink).toHaveAttribute('aria-current', 'page');
    await expect(recordingsLink).toHaveAttribute('aria-current', 'false');
    await recordingsLink.click();
    await expect(summary).toHaveCount(0);
    await expect(page.locator('[data-recording-row]')).toHaveCount(20);
    expect(new URL(page.url()).searchParams.get('recordings_mode')).toBeNull();
    const recordingCSV = await verifyNativeRecordingReportExport(page, info, target, foreignHeaders);
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
        maxBuffer: 512 * 1024,
        encoding: 'utf8',
      }
    );
    const witness = JSON.parse(raw.trim().split('\n').at(-1));
    expect(witness.source_sha).toBe(process.env.GITHUB_SHA);
    expect(String(witness.account_id)).toBe(account);
    const nativeReads = witness.operations.filter(
      row => row.changes.operation === 'quality_summary'
    );
    expect(nativeReads.length).toBeGreaterThan(0);
    expect(
      nativeReads.every(
        row =>
          row.auditable_type === 'Account' &&
          !JSON.stringify(row.changes).includes('sentimento_cliente')
      )
    ).toBe(true);
    const exportAudits = witness.operations.filter(row => row.changes.operation === 'export');
    expect(exportAudits).toHaveLength(2);
    for (const result of [recordingCSV.full, recordingCSV.filtered]) {
      const audit = exportAudits.find(row => row.changes.sha256 === result.sha256);
      expect(audit).toBeTruthy();
      expect(audit.auditable_type).toBe('Account');
      expect(String(audit.user_id)).toBe(recordingCSV.actor_id);
      expect(audit.changes.format).toBe('csv');
      expect(audit.changes.record_count).toBe(result.count);
      expect([...audit.changes.record_ids].sort()).toEqual([...result.record_ids].sort());
    }
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recording-quality-report.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          synthetic: true,
          actual_dark_theme: dark,
          source_boundary:
            'synthetic_original_analysis_not_external_Nico_homologation',
          full_period: full.quality_summary,
          actual_native_total: full.meta.total,
          first_page_count: full.items.length,
          page2_and_reload_verified: true,
          negative_segment_without_denominator_change: true,
          original_details_and_profile_withdrawal_reused: true,
          native_sidebar_shortcut_and_return_verified: true,
          native_sidebar_reuses_same_route: true,
          native_read_audit_ids: nativeReads.map(row => row.id),
          recording_metadata_csv: { ...recordingCSV, native_export_audit_ids: exportAudits.map(row => row.id) },
          foreign_account_status: 401,
          inaccessible_unit_status: 404,
          whole_figure_or_Part1_accepted: false,
          no_provider_operation: true,
          errors,
          prohibited,
          contrast,
          screenshots,
        },
        null,
        2
      ) + '\n'
    );
  } catch (error) {
    await page
      .screenshot({
        path: `.codex/call-center-native-e2e/${info.project.name}-recording-quality-report-owned-failure.png`,
        fullPage: true,
        timeout: 5000,
      })
      .catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
