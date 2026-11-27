import { verifyNativeCustomerRecords } from './call-center-customer-records-native.mjs';
import { expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Actual route, native dialog/form, authenticated APIs and committed PostgreSQL.
// No fulfilled API responses, manufactured grants or provider operations.
export async function verifyNativeRecordingTicket(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const record = target.recordings.allowed;
  const origin = 'http://127.0.0.1:5387';
  const path = `/api/v1/accounts/${account}/jrc_service_desk/tickets`;
  const intakePath = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${record.id}/ticket_intake`;
  const dark = info.project.name.endsWith('dark');
  const errors = [],
    prohibited = [],
    posts = [],
    screenshots = [];
  const witness = () => {
    const raw = execFileSync(
      'bundle',
      [
        'exec',
        'rails',
        'runner',
        'script/jrc_call_center_recording_ticket_evidence.rb',
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
    const result = JSON.parse(raw.trim().split('\n').at(-1));
    expect(result.source_sha).toBe(process.env.GITHUB_SHA);
    expect(result.account_id).toBe(account);
    expect(result.recording_id).toBe(record.id);
    expect(result.read_only_witness).toBe(true);
    return result;
  };
  const capture = async stage => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(dark);
    const name = `.codex/call-center-native-e2e/${info.project.name}-recording-native-ticket-${stage}.png`;
    await page.screenshot({ path: name, fullPage: true });
    screenshots.push(name);
  };
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const request = route.request(),
      url = new URL(request.url());
    const local = ['http://127.0.0.1:5386', origin].includes(url.origin);
    const create =
      local && request.method() === 'POST' && url.pathname === path;
    const external = ['http:', 'https:'].includes(url.protocol) && !local;
    if (create) {
      const payload = request.postDataJSON();
      expect(payload.recording_id).toBe(String(record.id));
      expect(payload.unit_id).toBe(target.manual_ticket_destination.unit_id);
      expect(payload).not.toHaveProperty('user_id');
      expect(payload).not.toHaveProperty('account_id');
      expect(payload).not.toHaveProperty('recording_origin');
      posts.push({ payload, key: request.headers()['idempotency-key'] });
    }
    if (external || (!['GET', 'HEAD'].includes(request.method()) && !create)) {
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
    { headers: target.operator, isDark: dark }
  );
  try {
    const before = witness();
    expect(before.ticket_count).toBe(0);
    expect(before.actor_role).toBe('agent');
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.call_id)}`
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    const previewResponse = page.waitForResponse(
      response =>
        response.request().method() === 'GET' &&
        new URL(response.url()).pathname === intakePath
    );
    await page.locator('[data-recording-actions-open]').click();
    const preview = await previewResponse;
    expect(preview.status()).toBe(200);
    const source = await preview.json();
    expect(source.account_id).toBe(account);
    expect(source.recording_id).toBe(record.id);
    expect(source.call_id).toBe(record.call_id);
    expect(source.user_id).toBe(before.actor_id);
    const open = page.locator('[data-open-native-recording-ticket]');
    await expect(open).toBeVisible();
    const actionContrast = await measureLocatorTextContrast(open);
    expect(actionContrast.ratio).toBeGreaterThanOrEqual(4.5);
    const fresh = page.waitForResponse(
      response =>
        response.request().method() === 'GET' &&
        new URL(response.url()).pathname === intakePath
    );
    await open.click();
    expect((await fresh).status()).toBe(200);
    const form = page
      .getByRole('dialog')
      .filter({ has: page.locator('[data-recording-ticket-origin]') });
    await expect(form).toBeVisible();
    await expect(form.locator('[data-recording-ticket-origin]')).toContainText(
      String(record.id)
    );
    await expect(form.getByLabel('Unidade', { exact: true })).toBeDisabled();
    expect(posts).toHaveLength(0);
    await capture('existing-native-form');
    const next = () =>
      form.getByRole('button', { name: 'Próxima etapa', exact: true }).click();
    await next();
    await expect(
      form.getByLabel('Solicitante', { exact: true })
    ).toBeDisabled();
    const title = `SYNTHETIC recording native Ticket ${info.project.name}`;
    await form.getByLabel('Título', { exact: true }).fill(title);
    await form
      .getByLabel('Descrição', { exact: true })
      .fill(
        'SYNTHETIC explicit review in the existing native Service Desk form.'
      );
    await next();
    await form
      .getByLabel('Prioridade', { exact: true })
      .selectOption(target.manual_ticket_destination.priority_id);
    await next();
    await next();
    const confirmed = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname === path
    );
    await form
      .getByRole('button', { name: 'Criar chamado', exact: true })
      .click();
    const created = await confirmed;
    expect(created.status()).toBe(201);
    const receipt = await created.json();
    expect(receipt.account_id).toBe(account);
    expect(receipt.applied).toBe(true);
    expect(posts).toHaveLength(1);
    await expect(page.getByTestId('ticket-created-receipt')).toContainText(
      title
    );
    await capture('confirmed-native-receipt');
    const after = witness();
    expect(after.ticket_count).toBe(1);
    const native = after.tickets[0];
    expect(native.id).toBe(receipt.ticket_id);
    expect(native.requester_id).toBe(source.contact_id);
    expect(native.creator_user_id).toBe(source.user_id);
    expect(native.origin.recording_id).toBe(Number(record.id));
    expect(native.idempotency_key).toBe(posts[0].key);
    expect(native.creation_events).toBe(1);
    expect(native.context_events).toBe(1);
    for (const key of [
      'qualifications_semantic_sha256',
      'ending_attempt_count',
      'native_project_tasks',
      'PABX_commands',
    ])
      expect(after[key]).toEqual(before[key]);
    const replay = await parent.request.post(origin + path, {
      headers: { ...target.operator, 'Idempotency-Key': posts[0].key },
      data: posts[0].payload,
    });
    expect(replay.status()).toBe(201);
    expect((await replay.json()).ticket_id).toBe(native.id);
    const altered = {
      ...posts[0].payload,
      ticket: {
        ...posts[0].payload.ticket,
        title: 'SYNTHETIC rejected conflicting duplicate',
      },
    };
    const conflict = await parent.request.post(origin + path, {
      headers: { ...target.operator, 'Idempotency-Key': posts[0].key },
      data: altered,
    });
    expect(conflict.status()).toBe(409);
    const denied = await parent.request.post(origin + path, {
      headers: { ...target.scoped, 'Idempotency-Key': posts[0].key },
      data: posts[0].payload,
    });
    expect(denied.status()).toBe(403);
    await page.getByTestId('open-created-ticket').click();
    await page.reload();
    await expect(page.getByText(title, { exact: true }).first()).toBeVisible();
    const readback = await parent.request.get(origin + path + '/' + native.id, {
      headers: target.operator,
    });
    expect(readback.status()).toBe(200);
    expect((await readback.json()).ticket.id).toBe(native.id);
    await capture('persisted-native-ticket-after-reload');
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(record.call_id)}`
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    const listPath = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${record.id}/tickets`;
    const linkedResponse = page.waitForResponse(
      response =>
        response.request().method() === 'GET' &&
        new URL(response.url()).pathname === listPath
    );
    await page.locator('[data-recording-actions-open]').click();
    const listResponse = await linkedResponse;
    expect(listResponse.status()).toBe(200);
    const linked = await listResponse.json();
    expect(linked.account_id).toBe(account);
    expect(linked.user_id).toBe(before.actor_id);
    expect(linked.recording_id).toBe(record.id);
    expect(linked.items).toHaveLength(1);
    expect(linked.items[0]).toMatchObject({
      id: native.id,
      number: native.id,
      title,
    });
    expect(linked.meta).toEqual({ page: 1, per_page: 20, total: 1, pages: 1 });
    const list = page.locator('[data-recording-linked-tickets]');
    const linkedTicket = list.getByRole('link').filter({ hasText: title });
    await expect(linkedTicket).toBeVisible();
    await capture('linked-native-ticket-in-recording-actions');
    await verifyNativeCustomerRecords(page, info, target, {
      id: native.id,
      title,
    });
    await linkedTicket.click();
    await expect(page.getByText(title, { exact: true }).first()).toBeVisible();
    const deniedList = await parent.request.get(origin + listPath, {
      headers: target.scoped,
    });
    expect(deniedList.status()).toBe(401);
    const final = witness();
    expect(final.ticket_count).toBe(1);
    expect(final.tickets).toEqual(after.tickets);
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recording-native-ticket.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          recording_id: record.id,
          synthetic: true,
          actual_dark_theme: dark,
          actual_native_preview: source,
          native_form_and_post: true,
          linked_native_ticket_page: linked,
          actual_link_navigation_after_create_and_reload: true,
          denied_linked_list_status: deniedList.status(),
          explicit_native_form_confirmation_before_create: true,
          original_agent_nonadministrator: true,
          replay_status: replay.status(),
          conflict_status: conflict.status(),
          denied_status: denied.status(),
          sole_browser_POST: posts[0],
          native_before: before,
          native_after: final,
          ACW_ending_actions_and_existing_Project_tasks_unchanged: true,
          contrast: actionContrast,
          screenshots,
          errors,
          prohibited,
          whole_figure21_or_Part1_accepted: false,
          external_provider_homologation: false,
        },
        null,
        2
      ) + '\n'
    );
  } catch (error) {
    await page
      .screenshot({
        path: `.codex/call-center-native-e2e/${info.project.name}-recording-native-ticket-failure.png`,
        fullPage: true,
        timeout: 5000,
      })
      .catch(() => null);
    throw error;
  } finally {
    await page.close();
  }
}
