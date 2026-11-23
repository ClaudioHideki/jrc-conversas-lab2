import { expect } from '@playwright/test';
import fs from 'node:fs';
import { bindBrowserApiResponse } from './call-center-browser-api.mjs';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Real production form/hook, scoped HTTP, PostgreSQL, actual CSS. No intercepted success or provider command.
export async function verifyEndingConfirmation(
  parent,
  info,
  target,
  foreignHeaders
) {
  const page = await parent.context().newPage();
  const errors = [];
  const forbidden = [];
  const confirmations = [];
  const screenshots = [];
  const contrast = [];
  const administrativeStatuses = [];
  const dark = info.project.name.endsWith('dark');
  const base = `/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const api = `http://127.0.0.1:5387${base}`;
  const qualification = `${api}/qualifications/${target.qualification_id}`;
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    const url = new URL(request.url());
    if (
      ['http:', 'https:'].includes(url.protocol) &&
      url.hostname !== '127.0.0.1'
    )
      forbidden.push(url.origin + url.pathname);
    if (
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        url.pathname
      )
    )
      forbidden.push(url.pathname);
    if (
      url.pathname ===
        `${base}/qualifications/${target.qualification_id}/confirm_reason` &&
      request.method() === 'POST'
    )
      confirmations.push(request.postDataJSON());
  });
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const outside =
      ['http:', 'https:'].includes(url.protocol) &&
      !['http://127.0.0.1:5386', 'http://127.0.0.1:5387'].includes(url.origin);
    const provider =
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        url.pathname
      );
    if (outside || provider) {
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
    { auth: target.operator, isDark: dark }
  );
  const matches = bindBrowserApiResponse(page, 'http://127.0.0.1:5387');
  const location = `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}?with_pause=1`;
  const capture = async suffix => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    expect(
      await page
        .locator('html')
        .evaluate(node => node.classList.contains('dark'))
    ).toBe(dark);
    const path = `.codex/call-center-native-e2e/${info.project.name}-ending-confirmation-${suffix}.png`;
    await page.screenshot({ path, fullPage: false });
    screenshots.push(path);
  };
  const read = async () => {
    const result = await page.request.get(
      api + `/qualifications?call_session_id=${target.call_session_id}`,
      { headers: target.operator }
    );
    expect(result.status()).toBe(200);
    return (await result.json()).items.find(
      row => String(row.id) === String(target.qualification_id)
    );
  };
  try {
    await page.goto(location);
    const beforeAdmin = await page.request.get(api + '/acw_forms', {
      headers: target.operator,
    });
    expect([401, 403, 404]).toContain(beforeAdmin.status());
    administrativeStatuses.push(beforeAdmin.status());
    const form = page.locator('[data-pending-qualification-form]');
    await expect(form.locator('[data-ending-reason-required]')).toBeVisible();
    const reason = form.locator('[data-qualification-field="reason"]');
    await reason.selectOption(target.ending_reason_code);
    const feedback = form.locator('[data-acw-answer="feedback"]');
    const verified = form.locator('[data-acw-answer="verified"]');
    const quantity = form.locator('[data-acw-answer="quantity"]');
    await expect(feedback).toBeVisible();
    await feedback.fill('SYNTHETIC partial feedback');
    await verified.selectOption('false');
    await form
      .locator('[data-qualification-field="note"]')
      .fill('SYNTHETIC private confirmation note');
    await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
    expect(confirmations).toEqual([]);
    await form.locator('[data-confirm-ending-reason]').click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('SYNTHETIC original ending');
    const confirmButton = dialog.getByRole('button', {
      name: 'Confirmar motivo',
      exact: true,
    });
    await expect(confirmButton).toBeVisible();
    expect(
      await confirmButton
        .locator('span')
        .last()
        .evaluate(node => node.scrollWidth <= node.clientWidth)
    ).toBe(true);
    const box = await dialog.boundingBox();
    const viewport = page.viewportSize();
    expect(
      Boolean(
        box &&
          viewport &&
          box.x >= 0 &&
          box.y >= 0 &&
          box.x + box.width <= viewport.width &&
          box.y + box.height <= viewport.height
      )
    ).toBe(true);
    const colors = await dialog
      .locator('[data-ending-confirmation-review]')
      .evaluate(measureTextContrast, ['p.font-semibold', 'p:nth-child(2)']);
    for (const row of colors) expect(row.ratio).toBeGreaterThanOrEqual(4.5);
    contrast.push(...colors);
    expect(confirmations).toEqual([]);
    await capture('review');
    const confirmed = page.waitForResponse(response =>
      matches(
        response,
        `${base}/qualifications/${target.qualification_id}/confirm_reason`,
        'POST'
      )
    );
    await confirmButton.click();
    const response = await confirmed;
    expect(response.status()).toBe(200);
    const receipt = (await response.json()).item;
    expect(receipt.ending_reason_confirmation).toMatchObject({
      state: 'confirmed',
      reason_code: target.ending_reason_code,
      completes_acw: false,
      executes_integrations: false,
    });
    expect(receipt.completed_at).toBeNull();
    expect(receipt.acw_form_context.answers[target.form_rule_id]).toEqual({
      feedback: 'SYNTHETIC partial feedback',
      verified: false,
    });
    await expect(form.locator('[data-ending-reason-confirmed]')).toBeVisible();
    await expect(form.locator('[data-ending-reason-required]')).toHaveCount(0);
    await expect(reason).toBeDisabled();
    await expect(
      form.locator('[data-qualification-field="note"]')
    ).toBeEnabled();
    await expect(page.locator('[data-native-deferred-pause]')).toHaveAttribute(
      'data-agent-state',
      'acw'
    );
    await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
    await capture('confirmed-open-acw');
    const denial = await page.request.patch(qualification + '/draft', {
      headers: target.operator,
      data: {
        expected_draft_revision: receipt.draft_revision,
        qualification: { reason_code: 'other' },
      },
    });
    expect(denial.status()).toBe(409);
    expect((await denial.json()).error).toBe('ending_reason_already_confirmed');
    const foreign = await page.request.post(qualification + '/confirm_reason', {
      headers: foreignHeaders,
      data: confirmations[0],
    });
    expect([401, 403, 404]).toContain(foreign.status());
    const admin = await page.request.post(qualification + '/confirm_reason', {
      headers: target.administrator,
      data: confirmations[0],
    });
    expect(admin.status()).toBe(404);
    const replay = await page.request.post(qualification + '/confirm_reason', {
      headers: target.operator,
      data: confirmations[0],
    });
    expect(replay.status()).toBe(200);
    expect((await replay.json()).item.ending_reason_confirmation.id).toBe(
      receipt.ending_reason_confirmation.id
    );
    await page.reload();
    await expect(form.locator('[data-ending-reason-confirmed]')).toBeVisible();
    await expect(reason).toBeDisabled();
    await expect(feedback).toHaveValue('SYNTHETIC partial feedback');
    await expect(verified).toHaveValue('false');
    expect((await read()).completed_at).toBeNull();
    await capture('reloaded-open-acw');
    await quantity.fill('0');
    await form
      .locator('[data-qualification-field="result"]')
      .selectOption('completed');
    const completion = page.waitForResponse(result =>
      matches(
        result,
        `${base}/qualifications/${target.qualification_id}`,
        'PATCH'
      )
    );
    await form.locator('[data-complete-qualification]').click();
    expect((await completion).status()).toBe(200);
    await expect(page.locator('[data-qualification-completed]')).toBeVisible();
    const final = await read();
    expect(final.completed_at).toBeTruthy();
    expect(final.ending_reason_confirmation.id).toBe(
      receipt.ending_reason_confirmation.id
    );
    expect(final.acw_form_context.answers[target.form_rule_id]).toEqual({
      feedback: 'SYNTHETIC partial feedback',
      verified: false,
      quantity: 0,
    });
    const finalStateResponse = await page.request.get(api + '/agent_state', {
      headers: target.operator,
    });
    expect(finalStateResponse.status()).toBe(200);
    const finalStatePayload = await finalStateResponse.json();
    expect(String(finalStatePayload.account_id)).toBe(
      String(target.account_id)
    );
    const finalState = finalStatePayload.item;
    expect(finalState).toMatchObject({
      account_user_id: String(target.operator_id),
      state: 'available',
      pending_qualifications: [],
      eligible: false,
      provider_confirmed: false,
    });
    // Observe the production component's read-only poll; never inject UI state.
    await expect(page.locator('[data-native-deferred-pause]')).toHaveAttribute(
      'data-agent-state',
      finalState.state,
      {
        timeout: 15000,
      }
    );
    await capture('completed');
    const afterAdmin = await page.request.get(api + '/acw_forms', {
      headers: target.operator,
    });
    expect([401, 403, 404]).toContain(afterAdmin.status());
    administrativeStatuses.push(afterAdmin.status());
    expect(confirmations).toHaveLength(1);
    expect(errors).toEqual([]);
    expect(forbidden).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-ending-confirmation-native.json`,
      JSON.stringify(
        {
          synthetic: true,
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          dark,
          qualification_id: target.qualification_id,
          account_id: target.account_id,
          confirmation_id: receipt.ending_reason_confirmation.id,
          explicit_confirmation_requests: 1,
          confirmed_with_incomplete_form: true,
          acw_remained_open: true,
          reason_change_status: denial.status(),
          other_actor_status: admin.status(),
          foreign_status: foreign.status(),
          idempotent_replay_status: replay.status(),
          pending_reload_preserved: true,
          final_completion_status: 200,
          final_agent_state: finalState.state,
          native_agent_poll_observed: true,
          provider_confirmed: finalState.provider_confirmed,
          false_and_zero_preserved: true,
          administrative_statuses: administrativeStatuses,
          contrast,
          screenshots,
          errors,
          provider_writes: forbidden,
        },
        null,
        2
      ) + '\n'
    );
  } finally {
    if (!page.isClosed()) await page.close();
  }
}
