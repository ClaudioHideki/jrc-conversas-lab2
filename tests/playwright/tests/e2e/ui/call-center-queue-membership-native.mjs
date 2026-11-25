import { expect } from '@playwright/test';

// Existing native queue scenario; synchronization checks the real persistence ACK.
export async function verifyNativeQueueMembership(
  page,
  info,
  { session, api, base }
) {
  const name = `synthetic-qa-members-${info.project.name}`;
  const created = await page.request.post(`${api}/queues`, {
    headers: session.administrator,
    data: {
      queue: {
        name,
        code: `MEM-${info.project.name}`,
        unit_id: session.unit_id,
      },
    },
  });
  expect(created.status()).toBe(201);
  const queue = (await created.json()).item;
  const inactiveResponse = await page.request.post(api + '/queues', {
    headers: session.administrator,
    data: {
      queue: {
        name: name + '-inactive',
        code: 'INACTIVE-' + info.project.name,
        unit_id: session.unit_id,
        status: 'inactive',
      },
    },
  });
  expect(inactiveResponse.status()).toBe(201);
  const inactiveQueue = (await inactiveResponse.json()).item;
  await page.goto(`${base}/queues?queues_tab=memberships`);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await dialog
    .getByRole('combobox', { name: 'Fila', exact: true })
    .selectOption(String(inactiveQueue.id));
  await dialog
    .getByRole('combobox', { name: 'Usuário', exact: true })
    .selectOption(String(session.viewer_account_user_id));
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await rejected).status()).toBe(422);
  await expect(dialog.getByRole('alert')).toContainText('Inativo');
  await expect(
    dialog.getByRole('combobox', { name: 'Fila', exact: true })
  ).toHaveValue(String(inactiveQueue.id));
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-inactive-queue.png',
    fullPage: true,
  });
  await dialog
    .getByRole('combobox', { name: 'Fila', exact: true })
    .selectOption(String(queue.id));
  await expect(
    dialog.getByRole('combobox', { name: 'Fila', exact: true })
  ).toHaveValue(String(queue.id));
  await dialog
    .getByLabel('Participa da distribuição', { exact: true })
    .uncheck();
  await dialog
    .getByLabel('Supervisiona esta fila (não concede permissão de monitoria)', {
      exact: true,
    })
    .check();
  const createdMembership = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const creationResult = await createdMembership;
  expect(creationResult.status()).toBe(201);
  expect((await creationResult.json()).item).toMatchObject({
    queue_id: queue.id,
    account_user_id: Number(session.viewer_account_user_id),
    role: 'supervisor',
    participates: false,
    supervises: true,
    active: true,
  });
  await expect(dialog).not.toBeVisible();
  const row = page.locator('[data-resource-row]').filter({ hasText: name });
  await expect(row).toContainText('Não participa da distribuição');
  await row.locator('[data-edit]').click();
  await expect(
    dialog.getByLabel('Participa da distribuição', { exact: true })
  ).not.toBeChecked();
  await dialog.getByLabel('Participa da distribuição', { exact: true }).check();
  await dialog.getByLabel('Ativo', { exact: true }).uncheck();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-membership.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  const read = await page.request.get(
    `${api}/queue_memberships?queue_id=${queue.id}&page=1`,
    { headers: session.administrator }
  );
  const savedMembership = (await read.json()).items[0];
  expect(savedMembership).toMatchObject({
    participates: true,
    supervises: true,
    active: false,
  });
  await expect(
    page.getByRole('button', { name: 'Participantes', exact: true })
  ).toHaveAttribute('aria-pressed', 'true');
  const enabled = await page.request.patch(
    api + '/queue_memberships/' + savedMembership.id,
    {
      headers: session.administrator,
      data: { queue_membership: { active: true } },
    }
  );
  expect(enabled.status()).toBe(200);
  const inactivated = await page.request.patch(api + '/queues/' + queue.id, {
    headers: session.administrator,
    data: { queue: { status: 'inactive' } },
  });
  expect(inactivated.status()).toBe(200);
  await page.reload();
  await row.locator('[data-edit]').click();
  await dialog.getByLabel('Ativo', { exact: true }).uncheck();
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await row.locator('[data-edit]').click();
  await dialog.getByLabel('Ativo', { exact: true }).check();
  const deniedActivation = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships/' + savedMembership.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await deniedActivation).status()).toBe(422);
  await expect(dialog.getByRole('alert')).toContainText('Inativo');
  const preserved = await page.request.get(
    api + '/queue_memberships?queue_id=' + queue.id + '&page=1',
    { headers: session.administrator }
  );
  expect((await preserved.json()).items[0].active).toBe(false);
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
}
