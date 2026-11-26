import { expect } from '@playwright/test';

// Existing native configuration APIs, real browser review and PostgreSQL.
// Inactivation affects only this owned synthetic queue; no provider command or artificial approval is used.
export async function verifyInactiveServiceDeskSource({
  page,
  target,
  prefix,
  endpoint,
  openEditor,
  persist,
  proof,
  capture,
  writes,
  previous,
}) {
  const queueUrl = `http://127.0.0.1:5387${prefix}/queues/${target.queue_id}`;
  const queue = await page.request.get(queueUrl, {
    headers: target.administrator,
  });
  expect(queue.status()).toBe(200);
  const existing = (await queue.json()).item;
  const closed = await page.request.patch(queueUrl, {
    headers: target.administrator,
    data: {
      queue: { status: 'inactive' },
      expected_revision: existing.revision,
    },
  });
  expect(closed.status()).toBe(200);
  const context = await page.request.get(`${endpoint}/source_context`, {
    headers: target.administrator,
    params: { queue_id: String(target.queue_id) },
  });
  expect(context.status()).toBe(200);
  const source = (await context.json()).item;
  expect(source.configuration_available).toBe(false);
  expect(source.service_desk.configuration_available).toBe(true);
  await page.reload();
  let editor = await openEditor();
  await editor.locator('[data-ending-rule-edit]').click();
  await expect(editor.locator('[data-ending-rule-active]')).toBeChecked();
  await editor.locator('[data-ending-rule-active]').uncheck();
  const saved = await persist(editor);
  expect(saved).toBe(200);
  const final = proof();
  expect(final.version_ids).toHaveLength(3);
  previous.version_ids.forEach(id =>
    expect(final.private_version_hashes[id]).toBe(
      previous.private_version_hashes[id]
    )
  );
  expect([final.tickets, final.task_effects, final.attempts]).toEqual([
    0, 0, 0,
  ]);
  expect(writes).toHaveLength(3);
  const submitted = writes.at(-1).private_rule;
  expect(submitted.active).toBe(false);
  await capture(
    'deactivated-closed-source',
    editor.locator('[data-ending-rule-saved]')
  );
  await page.reload();
  editor = await openEditor();
  await editor.locator('[data-ending-rule-edit]').click();
  await expect(editor.locator('[data-ending-rule-active]')).not.toBeChecked();
  await editor.locator('[data-ending-rule-active]').check();
  await editor.locator('[data-ending-rule-reviewed]').check();
  await expect(editor.locator('[data-ending-rule-save]')).toBeDisabled();
  const current = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(current.status()).toBe(200);
  const revision = (await current.json()).revision;
  const denied = await page.request.post(endpoint, {
    headers: target.administrator,
    data: {
      private_rule: { ...submitted, active: true },
      expected_revision: revision,
    },
  });
  expect(denied.status()).toBe(422);
  expect(proof()).toEqual(final);
  return {
    queue_update_status: closed.status(),
    source_configuration_available: source.configuration_available,
    native_destination_configuration_available:
      source.service_desk.configuration_available,
    deactivation_status: saved,
    UI_reactivation_save_disabled: true,
    API_reactivation_status: denied.status(),
    previous_private_versions_preserved: true,
    no_native_effects: true,
    final,
  };
}
