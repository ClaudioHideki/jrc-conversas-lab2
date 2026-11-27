import { openLoadedNativeTask } from './call-center-native-loaded-task-view.mjs';
import { expect } from '@playwright/test';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';
import { verifyNativeTaskCurrentState } from './call-center-native-task-state.mjs';

// Actual native editor/APIs/database. No fake responses or provider operations.
export async function verifyNativeManualRecordingTask(parent, info, target) {
  const page = await parent.context().newPage();
  const account = String(target.account_id);
  const source = target.ending_context;
  const destination = target.manual_task_destination;
  const base = `/api/v1/accounts/${account}/jrc_contact_center/recordings/${source.recording_id}`;
  const taskPath = base + '/tasks';
  const reviewPath = base + '/quality_review';
  const origin = 'http://127.0.0.1:5387';
  const screenshots = [];
  const errors = [];
  const prohibited = [];
  const taskPosts = [];
  const reviewPosts = [];
  const headers = target.operator;
  const dark = info.project.name.endsWith('dark');
  page.on('pageerror', error => errors.push(error.message));
  const capture = async name => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth
      )
    ).toBe(true);
    const filename = `.codex/call-center-native-e2e/${info.project.name}-recording-manual-task-${name}.png`;
    await page.screenshot({ path: filename, fullPage: true });
    screenshots.push(filename);
  };
  await page.route('**/*', route => {
    const request = route.request();
    const url = new URL(request.url());
    const owned = ['http://127.0.0.1:5386', origin].includes(url.origin);
    const external = ['http:', 'https:'].includes(url.protocol) && !owned;
    const create =
      owned && request.method() === 'POST' && url.pathname === taskPath;
    const review =
      owned && request.method() === 'POST' && url.pathname === reviewPath;
    if (create) {
      const payload = request.postDataJSON();
      expect(Object.keys(payload)).toEqual(['recording_task']);
      expect(Object.keys(payload.recording_task).sort()).toEqual([
        'project_id',
        'request_id',
        'task',
      ]);
      taskPosts.push(payload);
    }
    if (review) reviewPosts.push(request.postDataJSON());
    if (
      external ||
      (!['GET', 'HEAD'].includes(request.method()) && !create && !review)
    ) {
      prohibited.push(`${request.method()} ${url.origin}${url.pathname}`);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  const read = async path => {
    const response = await parent.request.get(origin + path, { headers });
    expect(response.status()).toBe(200);
    return response.json();
  };
  const openActions = async () => {
    await page.goto(
      `/app/accounts/${account}/contact-center/gravacoes?native_navigation=1&recordings_q=${encodeURIComponent(source.call_id)}`
    );
    await expect(page.locator('[data-recording-row]')).toHaveCount(1);
    await page.locator('[data-recording-details]').click();
    await page.locator('[data-recording-actions-open]').click();
    await expect(page.locator('[data-recording-manual-tasks]')).toBeVisible();
  };
  await page.addInitScript(
    ({ auth, isDark }) => {
      Reflect.set(window, '__SYNTHETIC_AUTH__', auth);
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', isDark)
      );
    },
    { auth: headers, isDark: dark }
  );
  try {
    expect((await read(taskPath)).items).toEqual([]);
    const beforeReview = await read(reviewPath);
    await openActions();
    const tasks = page.locator('[data-recording-manual-tasks]');
    await tasks.locator('[data-recording-new-task]').click();
    const picker = page.locator('[data-recording-task-project-picker]');
    await expect(picker).toBeVisible();
    await expect(picker).toContainText(destination.project_name);
    await expect(picker).not.toContainText(destination.hidden_project_name);
    await capture('authorized-project-picker');
    await page
      .getByRole('button', { name: 'Fechar janela', exact: true })
      .click();
    await expect(tasks).toBeVisible();
    expect(taskPosts).toEqual([]);
    await tasks.locator('[data-recording-new-task]').click();
    await picker
      .locator(`[data-create-task-project="${destination.project_id}"]`)
      .click();
    const editor = page
      .getByRole('dialog')
      .filter({ has: page.locator('form') })
      .last();
    await expect(editor).toBeVisible();
    const title = `SYNTHETIC authored recording task ${info.project.name}`;
    await editor.getByLabel(/^Título/).fill(title);
    await editor
      .getByLabel('Responsável', { exact: true })
      .selectOption(destination.assignee_id);
    await editor.getByLabel('Prazo', { exact: true }).fill('2026-12-02');
    await capture('existing-native-task-editor');
    const createdResponse = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname === taskPath
    );
    await editor
      .getByRole('button', { name: 'Criar tarefa', exact: true })
      .click();
    const created = await createdResponse;
    expect(created.status()).toBe(200);
    const receipt = await created.json();
    expect(receipt).toMatchObject({
      account_id: account,
      recording_id: source.recording_id,
    });
    expect(receipt.link_id).toMatch(/^[1-9][0-9]*$/);
    expect(taskPosts).toHaveLength(1);
    await expect(tasks.locator('[data-recording-manual-task-row]')).toHaveCount(
      1
    );
    const persisted = await read(taskPath);
    expect(persisted.items).toHaveLength(1);
    expect(persisted.items[0].id).toBe(receipt.link_id);
    expect(persisted.items[0].request_id).toBe(
      taskPosts[0].recording_task.request_id
    );
    const targetTask = persisted.items[0].target;
    expect(targetTask).toMatchObject({
      kind: 'project_task',
      project_id: destination.project_id,
    });
    const nativePath = `/api/v1/accounts/${account}/projects/projects/${destination.project_id}/tasks/${targetTask.id}`;
    const native = (await read(nativePath)).data;
    expect(native.title).toBe(title);
    expect(String(native.assignee_id)).toBe(destination.assignee_id);
    expect(native.due_on).toBe('2026-12-02');
    expect(native.status).toBe('backlog');
    const taskIdentity = {
      accountId: account,
      projectId: destination.project_id,
      taskId: targetTask.id,
    };
    const currentState = await verifyNativeTaskCurrentState(
      page,
      tasks,
      taskIdentity
    );
    const contrast = await measureLocatorTextContrast(tasks.locator('h3'));
    expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
    await capture('persisted-native-task-and-current-state');
    const repeated = await parent.request.post(origin + taskPath, {
      headers,
      data: taskPosts[0],
    });
    expect(repeated.status()).toBe(200);
    expect(await repeated.json()).toEqual(receipt);
    expect((await read(taskPath)).items).toEqual(persisted.items);
    expect(
      (
        await read(
          `/api/v1/accounts/${account}/projects/projects/${destination.project_id}`
        )
      ).data.tasks_total
    ).toBe(1);
    const listener = await parent.request.get(origin + taskPath, {
      headers: target.scoped,
    });
    expect(listener.status()).toBe(200);
    const restricted = await listener.json();
    expect(restricted.project_module_available).toBe(false);
    expect(restricted.items[0].target).toBeNull();
    expect(JSON.stringify(restricted)).not.toContain(destination.project_name);
    const denied = await parent.request.post(origin + taskPath, {
      headers: target.scoped,
      data: {
        recording_task: {
          ...taskPosts[0].recording_task,
          request_id: randomUUID(),
        },
      },
    });
    expect([401, 404]).toContain(denied.status());
    expect((await read(reviewPath)).revision).toBe(beforeReview.revision);
    await page.locator('[data-recording-quality-open]').click();
    await expect(page.locator('[data-quality-review]')).toBeVisible();
    await page
      .locator('input[name="quality-classification"][value="negative"]')
      .check();
    await page
      .locator('[data-quality-justification]')
      .fill('SYNTHETIC conclude review while native task remains pending');
    const savedResponse = page.waitForResponse(
      response =>
        response.request().method() === 'POST' &&
        new URL(response.url()).pathname === reviewPath
    );
    await page
      .getByRole('button', { name: 'Salvar e concluir', exact: true })
      .click();
    expect((await savedResponse).status()).toBe(200);
    await expect(page.locator('[data-quality-review]')).toHaveCount(0);
    expect(reviewPosts).toHaveLength(1);
    expect((await read(reviewPath)).revision).toBe(beforeReview.revision + 1);
    const after = (await read(nativePath)).data;
    [
      'id',
      'project_id',
      'status',
      'assignee_id',
      'due_on',
      'updated_at',
      'lock_version',
    ].forEach(field => {
      expect(after[field]).toEqual(native[field]);
    });
    const projectDetails = (
      await read(
        '/api/v1/accounts/' +
          account +
          '/projects/projects/' +
          destination.project_id
      )
    ).data;
    const activeColumn = projectDetails.columns.find(
      column => column.status_key === 'in_progress'
    );
    expect(activeColumn).toBeDefined();
    // Existing native Projects endpoint, its explicit synthetic owner and native lock revision.
    const movedResponse = await parent.request.post(
      origin + nativePath + '/move',
      {
        headers: target.administrator,
        data: { column_id: activeColumn.id, lock_version: after.lock_version },
      }
    );
    expect(movedResponse.status()).toBe(200);
    expect((await movedResponse.json()).data.status).toBe('in_progress');
    await openActions();
    await expect(page.locator('[data-recording-manual-task-row]')).toHaveCount(
      1
    );
    expect((await read(taskPath)).items).toEqual(persisted.items);
    const afterState = await verifyNativeTaskCurrentState(
      page,
      page.locator('[data-recording-manual-tasks]'),
      taskIdentity
    );
    expect(afterState.status).toBe('in_progress');
    expect(afterState.assignee_id).toBe(currentState.assignee_id);
    expect(afterState.due_on).toBe(currentState.due_on);
    expect(afterState.task_id).toBe(currentState.task_id);
    expect((await read(taskPath)).items).toEqual(persisted.items);
    await capture('review-concluded-pending-task-preserved-after-reload');
    const link = page.locator('[data-open-recording-manual-task]');
    const nativeTaskView = await openLoadedNativeTask(page, {
      link,
      accountId: account,
      projectId: destination.project_id,
      taskId: targetTask.id,
      title,
    });
    await capture('existing-native-task-opened-from-recording');
    expect(errors).toEqual([]);
    expect(prohibited).toEqual([]);
    expect(
      await page.evaluate(() =>
        document.documentElement.classList.contains('dark')
      )
    ).toBe(dark);
    fs.writeFileSync(
      `.codex/call-center-native-e2e/${info.project.name}-recording-manual-task-native.json`,
      JSON.stringify(
        {
          sha: process.env.GITHUB_SHA,
          project: info.project.name,
          account_id: account,
          recording_id: source.recording_id,
          call_session_id: source.call_session_id,
          synthetic: true,
          actual_dark_theme: dark,
          actual_native_Task_editor: true,
          hidden_private_Project_excluded: true,
          picker_cancel_preserved_recording_without_write: true,
          actual_UI_task_POSTs: taskPosts.length,
          explicit_same_key_retry_reused_receipt_and_only_one_native_Task: true,
          restricted_listener_gained_no_destination_rights: true,
          review_did_not_complete_or_hide_native_Task: true,
          receipt,
          persisted_link: persisted.items[0],
          native_task: {
            id: String(native.id),
            project_id: String(native.project_id),
            status: native.status,
            assignee_id: String(native.assignee_id),
            due_on: native.due_on,
          },
          currentState,
          sourceUpdatedState: afterState,
          nativeTaskView,
          review_revision_before: beforeReview.revision,
          review_revision_after: beforeReview.revision + 1,
          contrast,
          errors,
          prohibited,
          screenshots,
          no_external_homologation: true,
          whole_Part1_accepted: false,
        },
        null,
        2
      ) + '\n'
    );
  } finally {
    await page.close();
  }
}
