import { expect } from '@playwright/test';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

// Real native approval UI, CSS, PostgreSQL and ACW. No mocked API or external PABX.
export async function verifyAllScopePauseApproval(parent, info, target) {
  const pages = [];
  const errors = [];
  const providerWrites = [];
  const screenshots = [];
  const dark = info.project.name.endsWith('dark');
  const base = `/api/v1/accounts/${target.account_id}`;
  const api = `http://127.0.0.1:5387${base}/jrc_contact_center`;
  const browserResponse = (response, path, method) =>
    isBrowserApiResponse(
      response,
      parent.url(),
      `http://127.0.0.1:5387${path}`,
      method
    );
  const newPage = async auth => {
    const page = await parent.context().newPage();
    pages.push(page);
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {
      if (
        !['GET', 'HEAD'].includes(request.method()) &&
        /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
          request.url()
        )
      )
        providerWrites.push(new URL(request.url()).pathname);
    });
    await page.addInitScript(
      ({ headers, isDark }) => {
        window.__SYNTHETIC_AUTH__ = headers;
        document.addEventListener('DOMContentLoaded', () =>
          document.documentElement.classList.toggle('dark', isDark)
        );
      },
      { headers: auth, isDark: dark }
    );
    return page;
  };
  const capture = async (page, suffix, dialog = false) => {
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
    if (dialog) {
      const box = await page.getByRole('dialog').boundingBox();
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
    }
    const path = `.codex/call-center-native-e2e/${info.project.name}-pause-approval-${suffix}.png`;
    await page.screenshot({ path, fullPage: false });
    screenshots.push(path);
  };
  const page = await newPage(target.operator);
  const state = async () => {
    const response = await page.request.get(api + '/agent_state', {
      headers: target.operator,
    });
    expect(response.status()).toBe(200);
    return (await response.json()).item;
  };
  const location = `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}?with_pause=1`;
  try {
    await page.goto(location);
    const widget = page.locator('[data-native-deferred-pause]');
    await expect(widget).toBeVisible();
    await expect(widget).toHaveAttribute('data-agent-state', 'acw');
    const deniedAdmin = await page.request.get(api + '/acw_forms', {
      headers: target.operator,
    });
    expect([401, 403, 404]).toContain(deniedAdmin.status());
    await widget
      .locator('select')
      .first()
      .selectOption(String(target.queue_id));
    await widget.locator('select').nth(1).selectOption('approval_break');
    const privateText =
      'SYNTHETIC private reason, never disclosed to the other unit';
    await widget.locator('textarea').fill(privateText);
    await widget
      .getByRole('button', { name: 'Solicitar pausa após ACW', exact: true })
      .click();
    const review = page.locator('[data-pause-approval-review]');
    for (const name of target.affected_unit_names)
      await expect(review).toContainText(name);
    await expect(page.locator('[data-deferred-pause-confirm]')).toBeEnabled();
    await capture(page, 'review', true);
    const created = page.waitForResponse(response =>
      browserResponse(
        response,
        base + '/jrc_contact_center/deferred_pause_request',
        'POST'
      )
    );
    await page.locator('[data-deferred-pause-confirm]').click();
    const result = await created;
    expect(result.status()).toBe(200);
    const first = await result.json();
    expect(first.receipt.state).toBe('pending');
    expect(first.item).toMatchObject({
      state: 'acw',
      provider_confirmed: false,
    });
    expect(first.item.deferred_pause_request.approval.scopes).toHaveLength(2);
    await page.reload();
    await expect(widget.locator('[data-pause-approval-status]')).toBeVisible();
    await expect(widget.locator('[data-pause-approval-apply]')).toHaveCount(0);
    const pending = await state();
    const scopes = pending.deferred_pause_request.approval.scopes;
    const requestFor = reviewer => {
      const scope = scopes.find(
        row =>
          String(row.business_unit_id) === String(reviewer.business_unit_id)
      );
      expect(scope.requests).toHaveLength(1);
      return scope.requests[0].id;
    };
    const ownLink = widget.locator('[data-pause-approval-status] a').first();
    const ownPage = await newPage(target.operator);
    await ownPage.goto(await ownLink.getAttribute('href'));
    await expect(
      ownPage.locator('[data-native-pause-approval-origin]')
    ).toBeVisible();
    await expect(ownPage.getByRole('button', { name: /^Aprovar/ })).toHaveCount(
      0
    );
    await capture(ownPage, 'own-request');
    await ownPage.close();

    for (const [index, reviewer] of target.approval_reviewers.entries()) {
      const requestId = requestFor(reviewer);
      const reviewerPage = await newPage(reviewer.auth);
      await reviewerPage.goto(
        `/app/accounts/${target.account_id}/approvals/inbox/${requestId}`
      );
      const origin = reviewerPage.locator(
        '[data-native-pause-approval-origin]'
      );
      await expect(origin).toContainText(target.affected_unit_names[index]);
      await expect(origin).not.toContainText(
        target.affected_unit_names[1 - index]
      );
      await expect(reviewerPage.locator('body')).not.toContainText(privateText);
      const otherId = requestFor(target.approval_reviewers[1 - index]);
      const denied = await reviewerPage.request.get(
        `http://127.0.0.1:5387${base}/approvals/requests/${otherId}`,
        {
          headers: reviewer.auth,
        }
      );
      expect([401, 403, 404]).toContain(denied.status());
      await reviewerPage
        .locator('textarea')
        .fill(`SYNTHETIC manager ${index + 1} explicitly reviews own unit`);
      await reviewerPage.getByRole('button', { name: /^Aprovar/ }).click();
      const decisionDialog = reviewerPage.getByRole('dialog');
      await expect(
        decisionDialog.locator('[data-native-pause-approval-origin]')
      ).toContainText(target.affected_unit_names[index]);
      await capture(reviewerPage, `reviewer-${index + 1}`, true);
      const decided = reviewerPage.waitForResponse(response =>
        browserResponse(
          response,
          `${base}/approvals/requests/${requestId}/decide`,
          'POST'
        )
      );
      await decisionDialog
        .getByRole('button', { name: 'Aprovar', exact: true })
        .click();
      expect((await decided).ok()).toBe(true);
      await expect
        .poll(
          async () =>
            (await state()).deferred_pause_request.approval.scopes.find(
              scope =>
                String(scope.business_unit_id) ===
                String(reviewer.business_unit_id)
            ).requests[0].state
        )
        .toBe('approved');
      await reviewerPage.close();
      await page.reload();
      await expect(
        widget.locator('[data-pause-approval-status]')
      ).toBeVisible();
      if (index === 0) {
        expect((await state()).deferred_pause_request.approval.status).toBe(
          'approval_required'
        );
        await expect(widget.locator('[data-pause-approval-apply]')).toHaveCount(
          0
        );
        await expect(widget).toHaveAttribute('data-agent-state', 'acw');
        await capture(page, 'first-scope');
      }
    }
    expect((await state()).deferred_pause_request.approval.status).toBe(
      'ready'
    );
    await expect(widget.locator('[data-pause-approval-apply]')).toBeVisible();
    await capture(page, 'ready');
    await widget.locator('[data-pause-approval-apply]').click();
    await expect(page.locator('[data-deferred-pause-confirm]')).toBeEnabled();
    const applied = page.waitForResponse(response =>
      browserResponse(
        response,
        base + '/jrc_contact_center/deferred_pause_request/apply',
        'POST'
      )
    );
    await page.locator('[data-deferred-pause-confirm]').click();
    const applyResponse = await applied;
    expect(applyResponse.status()).toBe(200);
    expect((await applyResponse.json()).receipt.state).toBe('pending');
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(widget).toHaveAttribute('data-agent-state', 'acw');
    await expect(widget.locator('[role="timer"]')).toHaveCount(0);
    await capture(page, 'waiting-acw');
    const form = page.locator('[data-pending-qualification-form]');
    await form
      .locator('[data-qualification-field="reason"]')
      .selectOption('order');
    await form
      .locator('[data-qualification-field="note"]')
      .fill('SYNTHETIC approved pause ACW completion');
    await form
      .locator('[data-qualification-field="result"]')
      .selectOption('completed');
    const completed = page.waitForResponse(response =>
      browserResponse(
        response,
        `${base}/jrc_contact_center/qualifications/${target.qualification_id}`,
        'PATCH'
      )
    );
    await form.locator('[data-complete-qualification]').click();
    expect((await completed).status()).toBe(200);
    await expect(page.locator('[data-qualification-completed]')).toBeVisible();
    await expect(widget).toHaveAttribute('data-agent-state', 'paused', {
      timeout: 15000,
    });
    await expect(widget.locator('[role="timer"]')).toBeVisible();
    const final = await state();
    expect(final).toMatchObject({
      state: 'paused',
      reason_code: 'approval_break',
      eligible: false,
      provider_confirmed: false,
    });
    await page.reload();
    await expect(widget).toHaveAttribute('data-agent-state', 'paused');
    await capture(page, 'applied');
    const deniedAfter = await page.request.get(api + '/acw_forms', {
      headers: target.operator,
    });
    expect([401, 403, 404]).toContain(deniedAfter.status());
    expect(errors).toEqual([]);
    expect(providerWrites).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-pause-approval-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          synthetic: true,
          external_provider: false,
          account_id: target.account_id,
          account_user_id: target.operator_id,
          affected_unit_ids: target.affected_unit_ids,
          requested_scope_count: scopes.length,
          approved_scope_count: 2,
          first_scope_did_not_apply: true,
          full_approval_waited_for_acw: true,
          reload_persisted: true,
          denied_other_unit: true,
          no_administrative_access: true,
          final_state: final.state,
          provider_confirmed: final.provider_confirmed,
          dark,
          screenshots,
          errors,
          provider_writes: providerWrites,
        },
        null,
        2
      ) + '\n'
    );
  } finally {
    for (const owned of pages) if (!owned.isClosed()) await owned.close();
  }
}
