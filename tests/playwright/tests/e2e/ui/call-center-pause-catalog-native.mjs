import { expect } from '@playwright/test';
import fs from 'node:fs';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';
import { verifyNativePauseWorkspace } from './call-center-pause-workspace-native.mjs';

// Same existing scenario, extracted to retain the reviewed native suite size bound. No product change.
export async function verifyNativePauseCatalogEditor(
  page,
  info,
  target,
  expectContainedDialog
) {
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/pause_catalog`;
  const initial = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(initial.status()).toBe(200);
  const empty = (await initial.json()).item;
  expect(empty.enforced).toBe(false);
  expect(empty.entries).toEqual([]);
  const entries = Array.from({ length: 20 }, (_, index) => ({
    code: `synthetic_${index}`,
    name: `SYNTHETIC reason ${String(index).padStart(2, '0')}`,
    category: 'SYNTHETIC',
    description: '',
    active: true,
    minimum_minutes: 15,
    default_minutes: 30,
    maximum_minutes: 60,
    unit_ids: [],
    custom_role_ids: [],
  }));
  const prepared = await page.request.patch(endpoint, {
    headers: target.administrator,
    data: {
      pause_catalog: { enforced: false, entries },
      expected_revision: empty.revision,
    },
  });
  expect(prepared.status()).toBe(200);
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/pauses`
  );
  const catalog = page.locator('[data-pause-catalog]');
  await expect(
    catalog.getByText('Modo legado: motivos livres continuam permitidos.', {
      exact: true,
    })
  ).toBeVisible();
  await expect(catalog.locator('article')).toHaveCount(20);
  await verifyNativePauseWorkspace(page, info, target);
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await catalog
    .getByRole('button', { name: 'Novo motivo de pausa', exact: true })
    .click();
  await expectContainedDialog(page);
  let dialog = page.getByRole('dialog');
  await dialog.getByLabel('Código', { exact: true }).fill('INVALID SPACE');
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('SYNTHETIC created by real UI');
  await dialog.getByLabel('Categoria', { exact: true }).fill('SYNTHETIC');
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC persisted pause purpose');
  await dialog.getByLabel('Tempo mínimo', { exact: true }).fill('00:15');
  await dialog.getByLabel('Tempo padrão', { exact: true }).fill('00:30');
  await dialog.getByLabel('Tempo máximo', { exact: true }).fill('00:10');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await expect(
    dialog.getByLabel('Tempo máximo', { exact: true })
  ).toHaveAttribute('aria-invalid', 'true');
  await dialog.getByLabel('Tempo máximo', { exact: true }).fill('01:00');
  await dialog.getByLabel('Ativo para novas pausas', { exact: true }).check();
  await dialog
    .getByRole('checkbox', { name: 'Exigir justificativa para este motivo' })
    .check();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeEnabled();
  const rejectedSave = page.waitForResponse(response =>
    isBrowserApiResponse(response, page.url(), endpoint, 'PATCH')
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await rejectedSave).status()).toBe(422);
  await expect(dialog).toBeVisible();
  await expect(dialog.getByLabel('Código', { exact: true })).toHaveValue(
    'INVALID SPACE'
  );
  await expect(dialog.locator('[data-pause-invalid-field="code"]')).toHaveText(
    'Verifique este campo antes de salvar.'
  );
  await expect(dialog.getByLabel('Código', { exact: true })).toBeFocused();
  await expect(
    dialog.locator('[data-pause-invalid-field="code"]')
  ).toBeInViewport();
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    'SYNTHETIC created by real UI'
  );
  const rejectedState = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(rejectedState.status()).toBe(200);
  expect((await rejectedState.json()).item.revision).toBe(
    (await prepared.json()).item.revision
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-popup.png`,
    fullPage: false,
  });
  await dialog.getByLabel('Código', { exact: true }).fill('synthetic_created');
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).toBeHidden();
  await catalog.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(page).toHaveURL(/pauses_page=2/);
  await expect(catalog.locator('article')).toHaveCount(1);
  await expect(catalog).toContainText('SYNTHETIC created by real UI');
  const afterCreate = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(
    (await afterCreate.json()).item.entries.find(
      row => row.code === 'synthetic_created'
    ).justification_required
  ).toBe(true);
  await catalog
    .getByLabel('Buscar motivo', { exact: true })
    .fill('synthetic_created');
  await expect(catalog.locator('article')).toHaveCount(1);
  await expect(page).not.toHaveURL(/pauses_page=/);
  await catalog
    .getByRole('button', { name: 'Editar motivo de pausa', exact: true })
    .click();
  dialog = page.getByRole('dialog');
  await expect(dialog.getByLabel('Descrição', { exact: true })).toHaveValue(
    'SYNTHETIC persisted pause purpose'
  );
  await expect(dialog.getByLabel('Categoria', { exact: true })).toHaveValue(
    'SYNTHETIC'
  );
  const createdState = (await afterCreate.json()).item;
  const canceledWrites = [];
  const watchCancel = request => {
    if (
      request.method() === 'PATCH' &&
      new URL(request.url()).pathname === new URL(endpoint).pathname
    )
      canceledWrites.push(request.method());
  };
  page.on('request', watchCancel);
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('SYNTHETIC canceled name');
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC canceled purpose');
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await expect(dialog).toBeHidden();
  const cancelResponse = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(cancelResponse.status()).toBe(200);
  const afterCancel = (await cancelResponse.json()).item;
  expect(afterCancel.revision).toBe(createdState.revision);
  const canceledEntry = afterCancel.entries.find(
    row => row.code === 'synthetic_created'
  );
  expect(canceledEntry).toMatchObject({
    name: 'SYNTHETIC created by real UI',
    category: 'SYNTHETIC',
    description: 'SYNTHETIC persisted pause purpose',
  });
  page.off('request', watchCancel);
  expect(canceledWrites).toEqual([]);
  await catalog
    .getByRole('button', { name: 'Editar motivo de pausa', exact: true })
    .click();
  dialog = page.getByRole('dialog');
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    canceledEntry.name
  );
  await expect(dialog.getByLabel('Categoria', { exact: true })).toHaveValue(
    canceledEntry.category
  );
  await expect(dialog.getByLabel('Descrição', { exact: true })).toHaveValue(
    canceledEntry.description
  );
  await dialog
    .getByLabel('Descrição', { exact: true })
    .scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-restored-after-cancel.png`,
    fullPage: false,
  });
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-literal-completion.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: String(target.account_id),
        synthetic: true,
        same_existing_case_and_all_original_assertions_retained: true,
        creation: createdState.entries.find(
          row => row.code === 'synthetic_created'
        ),
        afterCancel: canceledEntry,
        initial_revision: createdState.revision,
        after_cancel_revision: afterCancel.revision,
        canceledWrites,
        real_native_persistence_and_reopen: true,
        actual_dark_theme: await page.evaluate(() =>
          document.documentElement.classList.contains('dark')
        ),
        screenshot: `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-restored-after-cancel.png`,
        external_PABX_or_legal_policy_homologation: false,
      },
      null,
      2
    )
  );
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('SYNTHETIC reviewed draft');
  const current = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  const currentItem = (await current.json()).item;
  const concurrent = await page.request.patch(endpoint, {
    headers: target.administrator,
    data: {
      pause_catalog: {
        enforced: false,
        entries: currentItem.entries.map(row =>
          row.code === 'synthetic_created'
            ? { ...row, name: 'SYNTHETIC concurrent server' }
            : row
        ),
      },
      expected_revision: currentItem.revision,
    },
  });
  expect(concurrent.status()).toBe(200);
  const denied = page.waitForResponse(
    response =>
      new URL(response.url()).origin === 'http://127.0.0.1:5386' &&
      new URL(response.url()).pathname === new URL(endpoint).pathname &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await denied).status()).toBe(409);
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    'SYNTHETIC reviewed draft'
  );
  await dialog
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(dialog.locator('[data-configuration-latest]')).toContainText(
    'SYNTHETIC concurrent server'
  );
  await dialog.locator('[data-configuration-review]').check();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeEnabled();
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('SYNTHETIC final reviewed draft');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog.locator('[data-configuration-review]').check();
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).toBeHidden();
  await page.reload();
  await expect(catalog).toContainText('SYNTHETIC final reviewed draft');
  await catalog.getByLabel('Buscar motivo', { exact: true }).fill('');
  await expect(catalog.locator('article')).toHaveCount(20);
  await catalog
    .getByRole('button', {
      name: 'Exigir catálogo para novas pausas',
      exact: true,
    })
    .click();
  dialog = page.getByRole('dialog');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog
    .getByLabel(
      'Revisei os motivos e confirmo a exigência do catálogo para novas pausas nesta conta.',
      { exact: true }
    )
    .check();
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).toBeHidden();
  await page.reload();
  await expect(catalog).toContainText(
    'Catálogo obrigatório para novas pausas.'
  );
  const persisted = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  const item = (await persisted.json()).item;
  expect(item.enforced).toBe(true);
  expect(item.entries).toHaveLength(21);
  expect(
    item.entries.find(row => row.code === 'synthetic_created')
  ).toMatchObject({
    name: 'SYNTHETIC final reviewed draft',
    minimum_minutes: 15,
    default_minutes: 30,
    maximum_minutes: 60,
  });
  const audit = await page.request.get(
    endpoint.replace(
      '/pause_catalog',
      `/configuration_audits?resource_type=pause_catalog&resource_id=${target.account_id}`
    ),
    { headers: target.administrator }
  );
  expect(audit.status()).toBe(200);
  expect((await audit.json()).items.length).toBeGreaterThan(0);
  await catalog.locator('[data-pause-catalog-history]').click();
  await expect(page).toHaveURL(/audit_config_resource_type=pause_catalog/);
  await expect(
    page.getByRole('heading', { name: 'Auditoria administrativa', exact: true })
  ).toBeVisible();
}
