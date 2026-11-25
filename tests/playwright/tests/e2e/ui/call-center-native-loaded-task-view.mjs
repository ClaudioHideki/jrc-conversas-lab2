import { expect } from '@playwright/test';

// Real native GET and loaded detail marker only. No response interception,
// fabricated state, retries, permission grant or task modification.
export async function openLoadedNativeTask(
  page,
  { link, accountId, projectId, taskId, title }
) {
  const identifiers = [accountId, projectId, taskId].map(String);
  expect(identifiers.every(value => /^[1-9][0-9]*$/.test(value))).toBe(true);
  const [account, project, task] = identifiers;
  const path = `/api/v1/accounts/${account}/projects/projects/${project}/tasks/${task}`;
  const [response] = await Promise.all([
    page.waitForResponse(
      entry =>
        entry.request().method() === 'GET' &&
        new URL(entry.url()).pathname === path
    ),
    link.click(),
  ]);
  expect(response.status()).toBe(200);
  const native = (await response.json()).data;
  expect(String(native.id)).toBe(task);
  expect(String(native.project_id)).toBe(project);
  expect(native.title).toBe(title);
  const dialog = page.getByRole('dialog', { name: title, exact: true });
  await expect(dialog).toBeVisible();
  await expect(
    dialog.getByText('Carregando tarefa...', { exact: true })
  ).toHaveCount(0);
  await expect(dialog.getByRole('alert')).toHaveCount(0);
  await expect(dialog.getByText(new RegExp(' / #' + task + '$'))).toBeVisible();
  return {
    status: response.status(),
    task_id: task,
    project_id: project,
    native_detail_loaded_before_capture: true,
    task_edit_or_save_claimed: false,
  };
}
