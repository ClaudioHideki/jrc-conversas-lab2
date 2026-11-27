import { verifyNativeRecordingTicket } from './call-center-recording-ticket-native.mjs';
import { verifyNativeManualRecordingTask } from './call-center-recording-manual-task-native.mjs';
import { expect } from '@playwright/test';
import { verifyNativeRecordingActions } from './call-center-recording-actions-native.mjs';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { measureLocatorTextContrast as measureTextContrast } from './call-center-text-contrast.mjs';
import { verifyNativeTranscript } from './call-center-transcript-native.mjs';
import { verifyNativeRecordingContext } from './call-center-recording-context-native.mjs';
import { verifyNativeQualityHistory } from './call-center-quality-history-native.mjs';

// Production Vue + real authenticated native APIs, immutable SQL revisions and audits.
// The alternate owned server substitutes only the declared remote analysis read, never an API or authorization response.
export async function verifyNativeQualityReview(parent, info, target) {
  const account = String(target.account_id);
  const record = target.recordings.allowed;
  const path = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${record.id}/quality_review`;
  const endpoint = `http://127.0.0.1:5387${path}`;
  const dark = info.project.name.endsWith('dark');
  const screenshots = [];
  const errors = [];
  const prohibited = [];
  const posts = [];
  const pages = [];
  let nativeTabReceipt = null;
  const capture = async (page, name) => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    const filename = `.codex/call-center-native-e2e/${info.project.name}-quality-${name}.png`;
    await page.screenshot({ path: filename, fullPage: true });
    screenshots.push(filename);
  };
  const open = async auth => {
    const page = await parent.context().newPage();
    pages.push(page);
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => {
      const request = route.request();
      const url = new URL(request.url());
      const owned = ['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(
        url.origin
      );
      const external = ['http:', 'https:'].includes(url.protocol) && !owned;
      const correction =
        owned && request.method() === 'POST' && url.pathname === path;
      if (correction) {
        const payload = request.postDataJSON();
        expect(Object.keys(payload)).toEqual(['quality_review']);
        expect(Object.keys(payload.quality_review).sort()).toEqual(
          [
            'adjusted_summary',
            'adjusted_themes',
            'classification',
            'expected_revision',
            'expected_source_sha256',
            'justification',
            'recommendation_ids',
            'request_id',
          ].sort()
        );
        posts.push(payload.quality_review);
      }
      if (
        external ||
        (!['GET', 'HEAD'].includes(request.method()) && !correction)
      ) {
        prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
        return route.abort('blockedbyclient');
      }
      return route.continue();
    });
    await page.addInitScript(
      ({ headers, isDark }) => {
        Reflect.set(window, '__SYNTHETIC_AUTH__', headers);
        document.addEventListener('DOMContentLoaded', () =>
          document.documentElement.classList.toggle('dark', isDark)
        );
      },
      { headers: auth, isDark: dark }
    );
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.call_id)}`
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    const sourceResponse = page.waitForResponse(
      response =>
        response.request().method() === 'GET' &&
        new URL(response.url()).pathname === path
    );
    await page.locator('[data-recording-analysis-open]').click();
    const nativeSourceResponse = await sourceResponse;
    expect(nativeSourceResponse.status()).toBe(200);
    const nativeSource = await nativeSourceResponse.json();
    expect(nativeSource).toMatchObject({
      account_id: account,
      recording_id: record.id,
      original: {
        sentimento_cliente: 'positivo',
        nota_final: 0,
        alerta_supervisao: true,
        motivo_alerta:
          'SYNTHETIC explicit source signal independent of sentiment',
      },
    });
    await expect(page.locator('[data-analysis-supervision-state]')).toHaveText(
      'Alerta informado pelo Nico'
    );
    await expect(page.locator('[data-analysis-supervision-reason]')).toHaveText(
      nativeSource.original.motivo_alerta
    );
    const signal = page.locator('[data-analysis-supervision-signal]');
    await expect(signal.locator('button, input, form, a')).toHaveCount(0);
    const signalContrast = await measureTextContrast(
      page.locator('[data-analysis-supervision-state]')
    );
    expect(signalContrast.ratio).toBeGreaterThanOrEqual(4.5);
    const tabs = page.locator('[data-recording-tabs] [role="tab"]');
    await expect(tabs).toHaveCount(5);
    await expect(
      page.locator('[data-analysis-original-summary]')
    ).toContainText('SYNTHETIC original immutable summary');
    if (pages.length === 1) {
      const labels = await tabs.allTextContents();
      expect(labels.map(label => label.trim())).toEqual([
        'Análise do Nico',
        'Transcrição',
        'Gravação',
        'Contexto',
        'Ações e Histórico',
      ]);
      const contrasts = await Promise.all(
        Array.from({ length: 5 }, (_, index) =>
          measureTextContrast(tabs.nth(index))
        )
      );
      contrasts.forEach(contrast =>
        expect(contrast.ratio).toBeGreaterThanOrEqual(4.5)
      );
      expect(
        await page
          .locator('[data-recording-selected]')
          .evaluate(element => element.scrollWidth <= element.clientWidth)
      ).toBe(true);
      nativeTabReceipt = {
        labels: labels.map(label => label.trim()),
        contrasts,
        real_original_summary_loaded: true,
        original_supervision_signal: {
          actual_native_GET: true,
          flag: nativeSource.original.alerta_supervisao,
          reason: nativeSource.original.motivo_alerta,
          original_sentiment: nativeSource.original.sentimento_cliente,
          original_quality: nativeSource.original.nota_final,
          independent_of_sentiment_and_no_write_controls: true,
          contrast: signalContrast,
        },
      };
      await signal.scrollIntoViewIfNeeded();
      await capture(page, 'five-native-tabs-analysis');
    }
    await page.locator('[data-recording-quality-open]').click();
    await expect(page.locator('[data-quality-original-summary]')).toContainText(
      'SYNTHETIC original immutable summary'
    );
    return page;
  };
  const persistenceControl = action => {
    const raw = execFileSync(
      'bundle',
      [
        'exec',
        'rails',
        'runner',
        'script/jrc_call_center_quality_persistence_failure.rb',
        action,
        account,
        String(record.id),
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
    expect(receipt.account_id).toBe(account);
    expect(receipt.recording_id).toBe(String(record.id));
    return receipt;
  };
  const submit = async (page, status) => {
    const response = page.waitForResponse(
      item =>
        new URL(item.url()).pathname === path &&
        item.request().method() === 'POST'
    );
    await page.locator('[data-quality-save]').click();
    const actual = await response;
    expect(actual.status()).toBe(status);
    return actual.json();
  };
  try {
    const profile = await parent.request.get(
      'http://127.0.0.1:5387/api/v1/profile',
      { headers: target.operator }
    );
    expect(profile.status()).toBe(200);
    const actor = await profile.json();
    expect(actor.accounts.find(row => String(row.id) === account).role).toBe(
      'agent'
    );
    const page = await open(target.operator);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(dark);
    await expect(page.locator('[data-quality-save]')).toBeDisabled();
    await expect(page.locator('[data-quality-original-score]')).toHaveText('0');
    await expect(page.locator('[data-quality-original-sentiment]')).toHaveText(
      'positivo'
    );
    await expect(page.locator('[data-quality-original-model]')).toHaveText(
      'Não informado pela fonte'
    );
    await expect(
      page.locator('[data-quality-sentiment-confidence]')
    ).toHaveText('Não informado pela fonte');
    const contrast = await measureTextContrast(
      page.locator('[data-quality-review] h4').first()
    );
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await capture(page, 'original');
    await page
      .locator('input[name="quality-classification"][value="negative"]')
      .check();
    await expect(page.locator('[data-quality-required]')).toContainText(
      'justificativa'
    );
    await expect(page.locator('[data-quality-save]')).toBeDisabled();
    expect(posts).toHaveLength(0);
    await page
      .locator('[data-quality-summary]')
      .fill('SYNTHETIC first human summary');
    await page
      .locator('[data-quality-themes]')
      .fill('SYNTHETIC reviewed theme');
    await page
      .locator('[data-quality-review] input[type="checkbox"]')
      .uncheck();
    await page
      .locator('[data-quality-justification]')
      .fill('SYNTHETIC first explicit reason');
    let persistenceFailure;
    let failedPayload;
    let rejectionActive = false;
    try {
      const enabled = persistenceControl('enable');
      rejectionActive = true;
      expect(enabled).toMatchObject({
        constraint_active: true,
        revisions: 0,
        audits: 0,
      });
      const rejected = await submit(page, 503);
      expect(rejected).toEqual({ error: 'quality_review_persistence_failed' });
      failedPayload = posts.at(-1);
      await expect(
        page.locator('[data-quality-review] [role="alert"]')
      ).toContainText('Não foi possível salvar a revisão');
      await expect(page.locator('[data-quality-summary]')).toHaveValue(
        'SYNTHETIC first human summary'
      );
      await expect(page.locator('[data-quality-justification]')).toHaveValue(
        'SYNTHETIC first explicit reason'
      );
      await expect(page.locator('[data-quality-save]')).toBeEnabled();
      expect(posts).toHaveLength(1);
      persistenceFailure = persistenceControl('inspect');
      expect(persistenceFailure).toMatchObject({
        constraint_active: true,
        revisions: 0,
        audits: 0,
      });
      await capture(page, 'native-persistence-failure-retained-draft');
    } finally {
      if (rejectionActive) {
        const restored = persistenceControl('disable');
        expect(restored).toMatchObject({
          constraint_active: false,
          revisions: 0,
          audits: 0,
        });
      }
    }
    const first = await submit(page, 200);
    expect(posts.at(-1)).toEqual(failedPayload);
    expect(first.item.request_id).toBe(failedPayload.request_id);
    expect(first.item).toMatchObject({
      revision: 1,
      origin: 'human',
      actor_id: String(actor.id),
    });
    expect(first.item.values.adjusted_themes).toEqual([
      'SYNTHETIC reviewed theme',
    ]);
    expect(first.item.values.recommendation_ids).toEqual([]);
    await expect(page.locator('[data-quality-review]')).toHaveCount(0);
    await page.locator('[data-recording-quality-open]').click();
    await expect(page.locator('[data-quality-human-origin]')).toContainText(
      '1'
    );
    await page
      .locator('[data-quality-justification]')
      .fill('SYNTHETIC reviewed stale draft');
    const competing = {
      ...posts[0],
      expected_revision: 1,
      request_id: randomUUID(),
      classification: 'neutral',
      adjusted_summary: 'SYNTHETIC competing native revision',
      justification: 'SYNTHETIC explicit competing reason',
    };
    const saved = await parent.request.post(endpoint, {
      headers: target.operator,
      data: { quality_review: competing },
    });
    expect(saved.status()).toBe(200);
    expect((await saved.json()).item.revision).toBe(2);
    await submit(page, 409);
    await expect(page.locator('[data-quality-summary]')).toHaveValue(
      'SYNTHETIC first human summary'
    );
    await expect(page.locator('[data-quality-save]')).toBeDisabled();
    await capture(page, 'conflict');
    await page.locator('[data-quality-conflict-review] button').first().click();
    await expect(
      page.locator('[data-quality-conflict-review] button')
    ).toHaveCount(2);
    await expect(page.locator('[data-quality-summary]')).toHaveValue(
      'SYNTHETIC first human summary'
    );
    await page.locator('[data-quality-conflict-review] button').last().click();
    const third = await submit(page, 200);
    expect(third.item.revision).toBe(3);
    await page.reload();
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-quality-open]').click();
    await expect(
      page.locator('[data-quality-current-human-review]')
    ).toContainText('SYNTHETIC reviewed stale draft');
    await expect(page.locator('[data-quality-original-summary]')).toContainText(
      'SYNTHETIC original immutable summary'
    );
    await expect(page.locator('[data-quality-original-sentiment]')).toHaveText(
      'positivo'
    );
    await capture(page, 'persisted');
    const postsBeforeCancel = posts.length;
    await page
      .locator('[data-quality-summary]')
      .fill('SYNTHETIC canceled unsaved summary');
    await page
      .locator('[data-quality-review]')
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    await expect(page.locator('[data-quality-discard]')).toBeVisible();
    await expect(page.locator('[data-quality-summary]')).toHaveValue(
      'SYNTHETIC canceled unsaved summary'
    );
    await page.locator('[data-quality-discard] button').first().click();
    await expect(page.locator('[data-quality-discard]')).toHaveCount(0);
    await expect(page.locator('[data-quality-summary]')).toHaveValue(
      'SYNTHETIC canceled unsaved summary'
    );
    await page
      .locator('[data-quality-review]')
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    await page.locator('[data-quality-discard] button').last().click();
    await expect(page.locator('[data-quality-review]')).toHaveCount(0);
    expect(posts).toHaveLength(postsBeforeCancel);
    const canceledResponse = await parent.request.get(endpoint, {
      headers: target.operator,
    });
    expect(canceledResponse.status()).toBe(200);
    const cancelState = await canceledResponse.json();
    expect(cancelState.revision).toBe(3);
    expect(cancelState.latest_review.values.adjusted_summary).toBe(
      'SYNTHETIC first human summary'
    );
    await page.locator('[data-recording-quality-open]').click();
    await expect(page.locator('[data-quality-summary]')).toHaveValue(
      cancelState.latest_review.values.adjusted_summary
    );
    await expect(page.locator('[data-quality-justification]')).toHaveValue('');
    await capture(page, 'restored-after-explicit-cancel');
    const denied = await parent.request.post(endpoint, {
      headers: target.scoped,
      data: {
        quality_review: {
          ...competing,
          expected_revision: 3,
          request_id: randomUUID(),
        },
      },
    });
    expect(denied.status()).toBe(401);
    const viewer = await open(target.scoped);
    await expect(viewer.locator('[data-quality-save]')).toHaveCount(0);
    await expect(
      viewer.locator('[data-quality-current-human-review]')
    ).toContainText('SYNTHETIC first human summary');
    await capture(viewer, 'readonly-listener');
    await verifyNativeTranscript(parent, viewer, info, target, capture);
    await verifyNativeRecordingContext(page, viewer, info, target, capture);
    await verifyNativeQualityHistory(parent, page, info, target, capture);
    await verifyNativeRecordingActions(parent, page, info, target, capture);
    await verifyNativeManualRecordingTask(parent, info, target);
    await verifyNativeRecordingTicket(parent, info, target);
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
        timeout: 45000,
        maxBuffer: 256 * 1024,
        encoding: 'utf8',
      }
    );
    const native = JSON.parse(raw.trim().split('\n').at(-1));
    expect(native.source_sha).toBe(process.env.GITHUB_SHA);
    expect(native.actual_native_revisions.map(row => row.revision)).toEqual([
      1, 2, 3,
    ]);
    expect(
      native.actual_native_revisions.map(row => row.values.classification)
    ).toEqual(['negative', 'neutral', 'negative']);
    expect(
      native.actual_native_revisions.every(
        row =>
          row.original.sentimento_cliente === 'positivo' &&
          row.original.nota_final === 0
      )
    ).toBe(true);
    expect(native.native_audits).toHaveLength(3);
    expect(
      native.native_audits.every(
        row => row.user_id === actor.id && row.action === 'create'
      )
    ).toBe(true);
    expect(native.ending_destination_actions).toBe(0);
    expect(native.PABX_commands).toBe(0);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-quality-review-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          recording_id: record.id,
          synthetic: true,
          source_boundary: native.source_boundary,
          actual_dark_theme: dark,
          contrast,
          real_native_persistence_and_reload: true,
          original_operator_nonadministrator: true,
          explicit_conflict_review_preserved_draft: true,
          native_persistence_failure_recovery: {
            rejected: persistenceFailure,
            actual_POST_status: 503,
            error: 'quality_review_persistence_failed',
            native_draft_retained_and_no_automatic_retry: true,
            explicit_retry_same_request_id:
              first.item.request_id === failedPayload.request_id,
            recovered_revision: first.item.revision,
            recovered_request_id: first.item.request_id,
          },
          explicit_cancel_and_keep_editing_preserved_native_revision: true,
          nativeTabReceipt,
          cancelState: {
            revision: cancelState.revision,
            adjusted_summary: cancelState.latest_review.values.adjusted_summary,
            no_additional_POST: posts.length === postsBeforeCancel,
          },
          listener_without_own_review_permission_denied: true,
          no_recommendation_or_PABX_operation: true,
          screenshots,
          errors,
          prohibited,
          native,
          whole_figure23_accepted: false,
          external_Nico_homologated: false,
        },
        null,
        2
      )
    );
  } finally {
    await Promise.all(pages.map(page => page.close()));
  }
}
