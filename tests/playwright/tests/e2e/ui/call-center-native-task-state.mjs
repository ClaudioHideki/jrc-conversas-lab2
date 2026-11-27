import { expect } from '@playwright/test';
import { measureTextContrast } from './call-center-text-contrast.mjs';

// Real Projects API only. Neither the task nor its immutable automation receipt
// is modified to manufacture a status, owner, date or successful read.
export async function verifyNativeTaskCurrentState(
  page,
  panel,
  { accountId, projectId, taskId, loadedOnOpen = false }
) {
  const identifiers = [accountId, projectId, taskId].map(String);
  expect(identifiers.every(value => /^[1-9][0-9]*$/.test(value))).toBe(true);
  const [account, project, task] = identifiers;
  const path = `/api/v1/accounts/${account}/projects/projects/${project}/tasks/${task}`;
  const state = panel.locator('[data-ending-task-current-state]');
  await expect(state).toHaveCount(1);
  if (loadedOnOpen)
    await expect(state.locator('[data-native-task-status]')).toBeVisible();
  else await expect(state.locator('[data-native-task-status]')).toHaveCount(0);
  const read = async () => {
    const [response] = await Promise.all([
      page.waitForResponse(
        entry =>
          entry.request().method() === 'GET' &&
          new URL(entry.url()).pathname === path
      ),
      state.locator('[data-load-native-task-state]').click(),
    ]);
    expect(response.status()).toBe(200);
    const native = (await response.json()).data;
    expect(String(native.id)).toBe(task);
    expect(String(native.project_id)).toBe(project);
    const statuses = {
      backlog: 'A fazer',
      in_progress: 'Em andamento',
      review: 'Em validação',
      completed: 'Concluído',
      blocked: 'Bloqueado',
      canceled: 'Cancelado',
    };
    expect(Object.hasOwn(statuses, native.status)).toBe(true);
    await expect(state.locator('[data-native-task-status]')).toHaveText(
      statuses[native.status]
    );
    await expect(state.locator('[data-native-task-assignee]')).toHaveText(
      native.assignee?.name || 'Sem responsável definido'
    );
    await expect(state.locator('[data-native-task-due]')).toHaveText(
      native.due_on
        ? native.due_on.split('-').reverse().join('/')
        : 'Sem prazo definido'
    );
    await expect(state.locator('[role="alert"]')).toHaveCount(0);
    await expect(state.locator('input, textarea, form')).toHaveCount(0);
    expect(await state.textContent()).not.toContain(native.title);
    const [contrast] = await state
      .locator('[data-native-task-status]')
      .evaluate(measureTextContrast);
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    return {
      task_id: task,
      project_id: project,
      status: native.status,
      assignee_id:
        native.assignee_id === null ? null : String(native.assignee_id),
      due_on: native.due_on,
      actual_native_GET: true,
      native_assignee_association_present: Object.hasOwn(native, 'assignee'),
      state_contrast_ratio: contrast.ratio,
    };
  };
  const first = await read();
  const refreshed = await read();
  expect(refreshed).toEqual(first);
  return {
    ...refreshed,
    ...(loadedOnOpen ? { observed_loaded_on_open: true } : {}),
    explicit_read_and_refresh: true,
    no_task_write_or_receipt_rewrite: true,
  };
}
