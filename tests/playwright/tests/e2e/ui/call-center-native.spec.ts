import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);
const base = `/app/accounts/${session.account_id}/contact-center/control-desk`;
const api = `http://127.0.0.1:5387/api/v1/accounts/${session.account_id}/jrc_contact_center`;
const expectContainedDialog = async (page: Page) => {
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect
    .poll(async () => {
      const box = await dialog.boundingBox();
      const viewport = page.viewportSize();
      return Boolean(
        box &&
          viewport &&
          box.x >= 0 &&
          box.y >= 0 &&
          box.x + box.width <= viewport.width &&
          box.y + box.height <= viewport.height
      );
    })
    .toBe(true);
};
test.beforeEach(async ({ page }, info) => {
  const auth = info.title.startsWith('configuration audit boundary')
    ? session.auditor
    : info.title.startsWith('native role denied')
      ? session.delegated
      : info.title.startsWith('corporate boundary')
        ? session.restricted
        : info.title.startsWith('profile change')
          ? session.viewer
          : session.administrator;
  await page.addInitScript(
    ({ auth, dark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', dark)
      );
    },
    { auth, dark: info.project.name.endsWith('dark') }
  );
});

test('native queue eligibility is rechecked before saving and preserves the reviewed selection', async ({
  page,
}, info) => {
  const targets = session.access_targets[info.project.name];
  const created = await page.request.post(api + '/queues', {
    headers: session.administrator,
    data: {
      queue: {
        unit_id: session.unit_id,
        name: 'SYNTHETIC enrollment ' + info.project.name,
        code: 'ELIGIBLE-' + info.project.name,
      },
    },
  });
  expect(created.status()).toBe(201);
  const queue = (await created.json()).item;
  await page.goto(base + '/queues?queues_tab=memberships');
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await expect(
    dialog.locator('option[value="' + targets.enrollment.id + '"]')
  ).toBeDisabled();
  await dialog
    .getByLabel('Fila', { exact: true })
    .selectOption(String(queue.id));
  await dialog
    .getByLabel('Usuário', { exact: true })
    .selectOption(String(targets.enrollment_eligible.id));
  let current = await page.request.get(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    { headers: session.administrator }
  );
  let revoke = await page.request.patch(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    {
      headers: session.administrator,
      data: {
        authorization: { eligible: false },
        expected_revision: (await current.json()).item.revision,
      },
    }
  );
  expect(revoke.status()).toBe(200);
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await rejected).status()).toBe(422);
  await expect(dialog.getByRole('alert')).toContainText(
    'pendente de autorização'
  );
  await expect(dialog.getByLabel('Usuário', { exact: true })).toHaveValue(
    String(targets.enrollment_eligible.id)
  );
  await expect(dialog.getByLabel('Fila', { exact: true })).toHaveValue(
    String(queue.id)
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-queue-eligibility.png',
    fullPage: true,
  });
  current = await page.request.get(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    { headers: session.administrator }
  );
  revoke = await page.request.patch(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    {
      headers: session.administrator,
      data: {
        authorization: { eligible: true },
        expected_revision: (await current.json()).item.revision,
      },
    }
  );
  expect(revoke.status()).toBe(200);
  const saved = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(201);
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(
    page.locator('[data-resource-row]').filter({ hasText: queue.name })
  ).toContainText(targets.enrollment_eligible.name);
  const bypass = await page.request.post(api + '/queue_memberships', {
    headers: session.administrator,
    data: {
      queue_membership: {
        queue_id: queue.id,
        account_user_id: targets.enrollment.id,
      },
    },
  });
  expect(bypass.status()).toBe(422);
  const rows = await page.request.get(
    api + '/queue_memberships?queue_id=' + queue.id,
    { headers: session.administrator }
  );
  expect((await rows.json()).items).toHaveLength(1);
  current = await page.request.get(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    { headers: session.administrator }
  );
  const suspended = await page.request.patch(
    api + '/access_authorizations/users/' + targets.enrollment_eligible.id,
    {
      headers: session.administrator,
      data: {
        authorization: { eligible: false },
        expected_revision: (await current.json()).item.revision,
      },
    }
  );
  expect(suspended.status()).toBe(200);
  await page.reload();
  await page
    .locator('[data-resource-row]')
    .filter({ hasText: queue.name })
    .locator('[data-edit]')
    .click();
  await dialog.getByLabel('Ativo', { exact: true }).uncheck();
  const deactivated = page.waitForResponse(
    response =>
      response.url().includes('/queue_memberships/') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await deactivated).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
});

test('native access user eligibility, real pagination, denial and persistence', async ({
  page,
}, info) => {
  const target = session.access_targets[info.project.name].pending;
  await page.goto(
    base +
      '/permissions?permission_scope=users&access_users_q=SYNTHETIC%20pagination'
  );
  const section = page.locator('[data-authority-assignments]');
  await expect(section.locator('[data-edit-authority]')).toHaveCount(20);
  await section.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(section.locator('[data-edit-authority]')).toHaveCount(1);
  await section
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  await section.getByRole('textbox').fill(target.name);
  await section.getByRole('combobox').selectOption('pending');
  await section
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(section.locator('[data-edit-authority]')).toHaveCount(1);
  await section.locator('[data-edit-authority="' + target.id + '"]').click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await expect(dialog.locator('[data-user-eligible]')).not.toBeChecked();
  await dialog.locator('[data-user-eligible]').check();
  await dialog
    .locator('[data-allow="jrc_contact_center_recordings_view"]')
    .check();
  await dialog
    .locator('[data-allow="jrc_contact_center_recordings_listen"]')
    .check();
  await dialog
    .locator('[data-deny="jrc_contact_center_recordings_download"]')
    .check();
  await expect(
    dialog.getByRole('button', { name: 'Salvar permissões', exact: true })
  ).toBeDisabled();
  await dialog.locator('[data-review-authority]').check();
  const persisted = page.waitForResponse(
    response =>
      response.url().endsWith('/access_authorizations/users/' + target.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Salvar permissões', exact: true })
    .click();
  expect((await persisted).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  await section.getByRole('combobox').selectOption('eligible');
  await section
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await page.reload();
  await expect(
    section.locator('[data-edit-authority="' + target.id + '"]')
  ).toBeVisible();
  await section.locator('[data-edit-authority="' + target.id + '"]').click();
  await expect(dialog.locator('[data-user-eligible]')).toBeChecked();
  await expect(
    dialog.locator('[data-deny="jrc_contact_center_recordings_download"]')
  ).toBeChecked();
  const saved = await page.request.get(
    api + '/access_authorizations/users/' + target.id,
    { headers: session.administrator }
  );
  expect(saved.status()).toBe(200);
  const state = (await saved.json()).item;
  expect(state.effective).toContain('jrc_contact_center_recordings_listen');
  expect(state.effective).not.toContain(
    'jrc_contact_center_recordings_download'
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  const foreground = await page
    .locator('[data-administration-section] h2')
    .evaluate(element => getComputedStyle(element).color);
  await expect(dialog.locator('[data-authority-editor]')).toHaveCSS(
    'color',
    foreground
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' + info.project.name + '-access-user.png',
    fullPage: true,
  });
});

test('native access team grants remain separate from eligibility and queue participation', async ({
  page,
}, info) => {
  const targets = session.access_targets[info.project.name];
  await page.goto(
    base +
      '/permissions?permission_scope=teams&access_teams_q=' +
      encodeURIComponent(targets.team.name)
  );
  const section = page.locator('[data-authority-assignments]');
  await section
    .locator('[data-edit-authority="' + targets.team.id + '"]')
    .click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await expect(dialog.locator('[data-user-eligible]')).toHaveCount(0);
  await expect(dialog.locator('[data-deny]')).toHaveCount(0);
  await dialog.locator('[data-allow="jrc_contact_center_monitor"]').check();
  await dialog.locator('[data-review-authority]').check();
  const persisted = page.waitForResponse(
    response =>
      response
        .url()
        .endsWith('/access_authorizations/teams/' + targets.team.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Salvar permissões', exact: true })
    .click();
  expect((await persisted).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await section
    .locator('[data-edit-authority="' + targets.team.id + '"]')
    .click();
  await expect(
    dialog.locator('[data-allow="jrc_contact_center_monitor"]')
  ).toBeChecked();
  const peer = await page.request.get(
    api + '/access_authorizations/users/' + targets.peer.id,
    { headers: session.administrator }
  );
  expect(peer.status()).toBe(200);
  const state = (await peer.json()).item;
  expect(state.inherited).toContain('jrc_contact_center_monitor');
  expect(state.effective).toContain('jrc_contact_center_monitor');
  const pending = await page.request.get(
    api + '/access_authorizations/users/' + targets.conflict.id,
    { headers: session.administrator }
  );
  expect((await pending.json()).item.eligible).toBe(false);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' + info.project.name + '-access-team.png',
    fullPage: true,
  });
});

test('native access conflict preserves draft and requires explicit comparison before overwrite', async ({
  page,
}, info) => {
  const target = session.access_targets[info.project.name].conflict;
  await page.goto(
    base +
      '/permissions?permission_scope=users&access_users_q=' +
      encodeURIComponent(target.name)
  );
  await page.locator('[data-edit-authority="' + target.id + '"]').click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await dialog.locator('[data-user-eligible]').check();
  await dialog.locator('[data-allow="jrc_contact_center_monitor"]').check();
  const snapshot = await page.request.get(
    api + '/access_authorizations/users/' + target.id,
    { headers: session.administrator }
  );
  const old = (await snapshot.json()).item;
  const other = await page.request.patch(
    api + '/access_authorizations/users/' + target.id,
    {
      headers: session.administrator,
      data: {
        expected_revision: old.revision,
        authorization: {
          eligible: true,
          allowed: ['jrc_contact_center_publish'],
        },
      },
    }
  );
  expect(other.status()).toBe(200);
  const current = (await other.json()).item;
  await dialog.locator('[data-review-authority]').check();
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/access_authorizations/users/' + target.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Salvar permissões', exact: true })
    .click();
  expect((await rejected).status()).toBe(409);
  await expect(
    dialog.locator('[data-allow="jrc_contact_center_monitor"]')
  ).toBeChecked();
  await expect(
    dialog.getByRole('button', { name: 'Salvar permissões', exact: true })
  ).toBeDisabled();
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-access-conflict.png',
    fullPage: true,
  });
  await dialog
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(dialog.locator('[data-configuration-latest]')).toContainText(
    'publicar'
  );
  await dialog.locator('[data-configuration-review]').check();
  await dialog.locator('[data-review-authority]').check();
  const persisted = page.waitForResponse(
    response =>
      response.url().endsWith('/access_authorizations/users/' + target.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Salvar permissões', exact: true })
    .click();
  const saved = await persisted;
  expect(saved.status()).toBe(200);
  expect(saved.request().postDataJSON().expected_revision).toBe(
    current.revision
  );
  await expect(dialog).not.toBeVisible();
  const final = await page.request.get(
    api + '/access_authorizations/users/' + target.id,
    { headers: session.administrator }
  );
  expect((await final.json()).item.allowed).toEqual([
    'jrc_contact_center_monitor',
  ]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-access-revised.png',
    fullPage: true,
  });
});

test('fifteen permission-bound cards, actual CSS, honest pending states and no overflow', async ({
  page,
}, info) => {
  await page.goto(base);
  await expect(page.locator('[data-card]')).toHaveCount(15);
  await expect(
    page.getByRole('heading', {
      name: 'Configurações do Call Center',
      exact: true,
    })
  ).toBeVisible();
  await expect(page.locator('[data-card]').first().locator('..')).toHaveCSS(
    'display',
    'grid'
  );
  await expect(page.locator('[data-control-desk] header')).not.toHaveCSS(
    'background-color',
    'rgba(0, 0, 0, 0)'
  );
  const light = await page
    .locator('[data-control-desk] header')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  await page.evaluate(() => document.documentElement.classList.toggle('dark'));
  const opposite = await page
    .locator('[data-control-desk] header')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  expect(opposite).not.toBe(light);
  await page.evaluate(() => document.documentElement.classList.toggle('dark'));
  const cards = {
    numbers: 'Números',
    extensions: 'Ramais',
    queues: 'Filas',
    ivr: 'URA',
    hours: 'Horários',
    audio: 'Áudios',
    pauses: 'Pausas',
    closures: 'Encerramentos',
    distribution: 'Distribuição',
    permissions: 'Permissões',
    recordings: 'Gravações',
    pabx: 'PABX',
    approvals: 'Aprovações',
    general: 'Parâmetros Gerais',
    integrations: 'Integrações',
  };
  const pending = [
    'numbers',
    'ivr',
    'hours',
    'audio',
    'pauses',
    'distribution',
    'recordings',
  ];
  for (const [key, name] of Object.entries(cards)) {
    const card = page.locator(`[data-card="${key}"]`);
    await expect(
      card.getByRole('heading', { name, exact: true })
    ).toBeVisible();
    const icon = card.locator('span[class*="i-lucide-"]').first();
    expect(
      await icon.evaluate(element => {
        const css = getComputedStyle(element);
        return (
          (css.maskImage !== 'none' || css.backgroundImage !== 'none') &&
          element.getBoundingClientRect().width > 0 &&
          element.getBoundingClientRect().height > 0
        );
      })
    ).toBe(true);
    await page.locator(`[data-card="${key}"]`).click();
    await expect(page.locator('[data-administration-section] h2')).toHaveText(
      name
    );
    if (pending.includes(key)) {
      await expect(
        page.locator('[data-administration-section] [role="status"]')
      ).toContainText('Funcionalidade pendente');
      await expect(page.locator('[data-create]')).toHaveCount(0);
    }
    await page
      .getByText('Voltar às configurações do Call Center', { exact: true })
      .click();
  }
  await expect(page.locator('[data-provider-state]')).toHaveText(
    'Conexão PABX não configurada nesta conta.'
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  const out = path.resolve('.codex/call-center-native-e2e');
  fs.mkdirSync(out, { recursive: true });
  await page.screenshot({
    path: `${out}/${info.project.name}-central.png`,
    fullPage: true,
  });
});

test('native unit popup: validation failure preserves values, creation editing reload and API persistence', async ({
  page,
}, info) => {
  const suffix = info.project.name.replaceAll('-', '_');
  const name = `SYNTHETIC popup ${suffix}`;
  await page.goto(`${base}/general`);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog.getByLabel('Código', { exact: true }).fill('PRIMARY');
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog.getByRole('alert')).toBeVisible();
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(name);
  await dialog.getByLabel('Código', { exact: true }).fill(`POPUP_${suffix}`);
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.getByLabel('Pesquisar', { exact: true }).fill(name);
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(1);
  await page.locator('[data-edit]').click();
  await dialog.getByLabel('Nome', { exact: true }).fill(`${name} revised`);
  await expect
    .poll(() => dialog.getByLabel('Nome', { exact: true }).inputValue())
    .toBe(`${name} revised`);
  expect(
    await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-popup.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('[data-resource-row]')).toContainText(
    `${name} revised`
  );
  const result = await page.request.get(
    `${api}/units?page=1&q=${encodeURIComponent(name)}`,
    { headers: session.administrator }
  );
  expect(result.status()).toBe(200);
  expect((await result.json()).items[0].name).toBe(`${name} revised`);
});

test('queue pagination, persisted filtering, navigation and clearing filters', async ({
  page,
}) => {
  await page.goto(`${base}/queues`);
  await page.getByLabel('Pesquisar', { exact: true }).fill('SYNTHETIC queue ');
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(20);
  const first = await page.locator('[data-resource-row]').first().innerText();
  await page.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(3);
  expect(
    await page.locator('[data-resource-row]').first().innerText()
  ).not.toBe(first);
  await page.getByLabel('Pesquisar', { exact: true }).fill('queue 22');
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(1);
  await page.reload();
  await expect(page.getByLabel('Pesquisar', { exact: true })).toHaveValue(
    'queue 22'
  );
  await expect(page.locator('[data-resource-row]')).toContainText('queue 22');
  await page
    .getByText('Voltar às configurações do Call Center', { exact: true })
    .click();
  await page.locator('[data-card="queues"]').click();
  await expect(page.getByLabel('Pesquisar', { exact: true })).toHaveValue(
    'queue 22'
  );
  await page
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(20);
});

test('profile change revalidates native grants and denies writes after revocation', async ({
  page,
}, info) => {
  await page.goto(base);
  await expect(
    page.getByText(
      'Nenhuma configuração administrativa autorizada para seu perfil.',
      { exact: true }
    )
  ).toBeVisible();
  await expect(page.locator('[data-card]')).toHaveCount(0);
  const write = await page.request.post(`${api}/units`, {
    headers: session.viewer,
    data: { unit: { name: 'Denied', code: 'DENIED', kind: 'sac' } },
  });
  expect(write.status()).toBe(401);
  const foreign = await page.request.get(
    `http://127.0.0.1:5387/api/v1/accounts/${session.other_account_id}/jrc_contact_center/administration`,
    { headers: session.administrator }
  );
  expect(foreign.status()).toBe(401);
  await page.goto(`${base}/general`);
  await expect(page.getByRole('alert')).toContainText('Seção indisponível');
  await expect(page.locator('[data-create]')).toHaveCount(0);
  const roleUrl = `http://127.0.0.1:5387/api/v1/accounts/${session.account_id}/custom_roles/${session.viewer_role_id}`;
  const grant = await page.request.patch(roleUrl, {
    headers: session.administrator,
    data: {
      custom_role: {
        permissions: [
          'jrc_contact_center_view',
          'jrc_contact_center_configure',
        ],
      },
    },
  });
  expect(grant.status()).toBe(200);
  await page.goto(base);
  await expect(page.locator('[data-card="general"]')).toBeVisible();
  await expect(page.locator('[data-card="permissions"]')).toHaveCount(0);
  const created = await page.request.post(`${api}/units`, {
    headers: session.viewer,
    data: {
      unit: {
        name: `synthetic-role-${info.project.name}`,
        code: `ROLE-${info.project.name}`,
        kind: 'sac',
      },
    },
  });
  expect(created.status()).toBe(201);
  const target = (await created.json()).item;
  const revoke = await page.request.patch(roleUrl, {
    headers: session.administrator,
    data: { custom_role: { permissions: ['jrc_contact_center_view'] } },
  });
  expect(revoke.status()).toBe(200);
  await page.reload();
  await expect(page.locator('[data-card]')).toHaveCount(0);
  const denied = await page.request.patch(`${api}/units/${target.id}`, {
    headers: session.viewer,
    data: { unit: { name: 'Forbidden after revocation' } },
  });
  expect(denied.status()).toBe(401);
  const persisted = await page.request.get(
    `${api}/units?q=${encodeURIComponent(target.code)}&page=1`,
    { headers: session.administrator }
  );
  expect((await persisted.json()).items[0].name).toBe(target.name);
});

test('queue popup creates edits and reloads local data without claiming PABX application', async ({
  page,
}, info) => {
  const name = `synthetic-qa-queue-${info.project.name}`;
  await page.goto(`${base}/queues?queues_q=${name}`);
  await expect(page.locator('[data-resource-row]')).toHaveCount(0);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog
    .getByLabel('Código', { exact: true })
    .fill(`QA-${info.project.name}`);
  await dialog
    .getByRole('combobox', { name: 'Unidade operacional', exact: true })
    .selectOption(String(session.unit_id));
  await expect(
    dialog.getByRole('combobox', { name: 'Unidade operacional', exact: true })
  ).toHaveValue(String(session.unit_id));
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.locator('[data-edit]').click();
  await dialog.getByLabel('Nome', { exact: true }).fill(`${name}-revised`);
  await dialog
    .getByRole('combobox', { name: 'Status', exact: true })
    .selectOption('inactive');
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-queue.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('[data-resource-row]')).toContainText(
    `${name}-revised`
  );
  const read = await page.request.get(`${api}/queues?q=${name}&page=1`, {
    headers: session.administrator,
  });
  expect((await read.json()).items[0]).toMatchObject({
    name: `${name}-revised`,
    status: 'inactive',
    service_kind: 'voice',
  });
});

test('editing an existing non-voice queue preserves the native channel contract', async ({
  page,
}, info) => {
  const name = `synthetic-qa-chat-${info.project.name}`;
  const created = await page.request.post(`${api}/queues`, {
    headers: session.administrator,
    data: {
      queue: {
        name,
        code: `CHAT-${info.project.name}`,
        unit_id: session.unit_id,
        service_kind: 'whatsapp',
      },
    },
  });
  expect(created.status()).toBe(201);
  await page.goto(`${base}/queues?queues_q=${name}`);
  await page.locator('[data-edit]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(`${name}-reviewed`);
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('[data-resource-row]')).toContainText('WhatsApp');
  const read = await page.request.get(`${api}/queues?q=${name}&page=1`, {
    headers: session.administrator,
  });
  expect((await read.json()).items[0].service_kind).toBe('whatsapp');
});

test('native team popup and member editor persist without granting queue participation', async ({
  page,
}, info) => {
  const name = `synthetic-qa-team-${info.project.name}`;
  await page.goto(`${base}/queues?queues_tab=teams&teams_q=${name}`);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('Synthetic native team');
  await dialog
    .getByRole('button', { name: 'Salvar dados da equipe', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await page.locator('[data-edit]').click();
  const before = await page.request.get(
    `${api}/queue_memberships?page=1&per_page=100`,
    { headers: session.administrator }
  );
  const count = (await before.json()).meta.total;
  await dialog
    .locator(`[data-team-member="${session.viewer_user_id}"]`)
    .check();
  await dialog
    .getByRole('button', { name: 'Salvar participantes', exact: true })
    .click();
  await expect(dialog.getByRole('status')).toHaveText(
    'Participantes da equipe salvos.'
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-team.png`,
    fullPage: true,
  });
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('Synthetic revised description');
  await dialog
    .getByRole('button', { name: 'Salvar dados da equipe', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('[data-resource-row]')).toContainText(
    'Synthetic revised description'
  );
  await page.locator('[data-edit]').click();
  await expect(
    dialog.locator(`[data-team-member="${session.viewer_user_id}"]`)
  ).toBeChecked();
  await dialog.getByLabel('Nome', { exact: true }).fill('Discard this edit');
  await page.keyboard.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(page.locator('[data-resource-row]')).toContainText(name);
  const after = await page.request.get(
    `${api}/queue_memberships?page=1&per_page=100`,
    { headers: session.administrator }
  );
  expect((await after.json()).meta.total).toBe(count);
});

test('queue membership popup distinguishes supervision from participation and persists deactivation', async ({
  page,
}, info) => {
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
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
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
});

test('local ACW popup validates HH:MM preserves failed values and reloads the native policy', async ({
  page,
}, info) => {
  const before = await page.request.get(`${api}/acw_policy`, {
    headers: session.administrator,
  });
  const policy = (await before.json()).item;
  const minutes = (Math.floor(policy.limits.voice / 60) % 50) + 1;
  const value = `00:${String(minutes).padStart(2, '0')}`;
  await page.goto(`${base}/closures`);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Voz', { exact: true }).fill('00:00');
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog.getByRole('alert')).toHaveText(
    'Informe HH:MM entre 00:01 e 01:00.'
  );
  await expect(dialog.getByLabel('Voz', { exact: true })).toHaveValue('00:00');
  const rejected = await page.request.get(`${api}/acw_policy`, {
    headers: session.administrator,
  });
  expect((await rejected.json()).item).toEqual(policy);
  await dialog.getByLabel('Voz', { exact: true }).fill(value);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await page.locator('[data-create]').click();
  await expect(dialog.getByLabel('Voz', { exact: true })).toHaveValue(value);
  const read = await page.request.get(`${api}/acw_policy`, {
    headers: session.administrator,
  });
  expect((await read.json()).item.limits.voice).toBe(minutes * 60);
});

test('corporate boundary denies foreign units and queues for scoped configuration and writes', async ({
  page,
}) => {
  await page.goto(`${base}/general`);
  await expect(page.locator('[data-resource-row]')).toHaveCount(1);
  await expect(page.locator('[data-resource-row]')).toContainText(
    'SYNTHETIC unit A'
  );
  const deniedUpdate = await page.request.patch(
    `${api}/units/${session.denied_unit_id}`,
    {
      headers: session.restricted,
      data: { unit: { name: 'Forbidden' } },
    }
  );
  expect(deniedUpdate.status()).toBe(404);
  const deniedQueue = await page.request.post(`${api}/queues`, {
    headers: session.restricted,
    data: {
      queue: {
        name: 'Forbidden',
        code: 'FORBIDDEN',
        unit_id: session.denied_unit_id,
      },
    },
  });
  expect(deniedQueue.status()).toBe(404);
  const deniedMember = await page.request.post(`${api}/queue_memberships`, {
    headers: session.restricted,
    data: {
      queue_membership: {
        queue_id: session.denied_queue_id,
        account_user_id: session.viewer_account_user_id,
      },
    },
  });
  expect(deniedMember.status()).toBe(404);
  const deniedScope = await page.request.post(`${api}/units`, {
    headers: session.restricted,
    data: {
      unit: {
        name: 'Forbidden',
        code: 'FORBIDDEN',
        kind: 'sac',
        settings: {
          issuer_company_id: session.issuer_company_id,
          business_unit_id: session.denied_business_unit_id,
        },
      },
    },
  });
  expect(deniedScope.status()).toBe(401);
  const roleUrl =
    'http://127.0.0.1:5387/api/v1/accounts/' +
    session.account_id +
    '/custom_roles/' +
    session.viewer_role_id;
  const originalRole = await page.request.get(roleUrl, {
    headers: session.administrator,
  });
  expect(originalRole.status()).toBe(200);
  const beforeRole = await originalRole.json();
  const deniedRole = await page.request.patch(roleUrl, {
    headers: session.restricted,
    data: { custom_role: { name: 'Forbidden unit takeover' } },
  });
  expect(deniedRole.status()).toBe(401);
  const deniedDeletion = await page.request.delete(roleUrl, {
    headers: session.restricted,
  });
  expect(deniedDeletion.status()).toBe(401);
  const preservedRole = await page.request.get(roleUrl, {
    headers: session.administrator,
  });
  expect(await preservedRole.json()).toEqual(beforeRole);
  await page.goto(base + '/queues?queues_tab=teams');
  await expect(page.locator('[data-create]')).toHaveCount(0);
  await page.goto(base + '/closures');
  await expect(page.locator('[data-create]')).toHaveCount(0);
  await expect(page.locator('[data-administration-section]')).toContainText(
    'toda a conta'
  );
  const deniedGlobal = await page.request.patch(api + '/acw_policy', {
    headers: session.restricted,
    data: { limits: { voice: 60, whatsapp: 120 }, voice_required: false },
  });
  expect(deniedGlobal.status()).toBe(401);
});

test('native permission popup reuses the role editor and persists only explicitly selected capabilities', async ({
  page,
}, info) => {
  const roleUrl = `http://127.0.0.1:5387/api/v1/accounts/${session.account_id}/custom_roles/${session.viewer_role_id}`;
  const before = await page.request.get(roleUrl, {
    headers: session.administrator,
  });
  expect(before.status()).toBe(200);
  const original = await before.json();
  await page.goto(`${base}/permissions`);
  await page
    .getByRole('combobox', { name: 'Perfil nativo', exact: true })
    .selectOption(String(session.viewer_role_id));
  await page.locator('[data-edit-native-role]').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.locator('input[id^="jrc_contact_center_"]')).toHaveCount(
    13
  );
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC explicitly reviewed permissions');
  await dialog.locator('#jrc_contact_center_configure').check();
  await expect(dialog.locator('#jrc_contact_center_publish')).not.toBeChecked();
  expect(
    await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-permissions.png`,
    fullPage: true,
  });
  await dialog
    .getByRole('button', { name: 'Revisar alterações', exact: true })
    .click();
  await expect(dialog.locator('[data-role-review]')).toContainText(
    'Capacidades a conceder'
  );
  await dialog
    .getByRole('button', { name: 'Confirmar alterações', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  const after = await page.request.get(roleUrl, {
    headers: session.administrator,
  });
  expect((await after.json()).permissions.sort()).toEqual([
    'jrc_contact_center_configure',
    'jrc_contact_center_view',
  ]);
  const restored = await page.request.patch(roleUrl, {
    headers: session.administrator,
    data: { custom_role: { permissions: original.permissions } },
  });
  expect(restored.status()).toBe(200);
});

test('native role creation validates the form and persists exactly the selected capabilities', async ({
  page,
}, info) => {
  const name = 'SYNTHETIC created role ' + info.project.name;
  await page.goto(base + '/permissions');
  await page.locator('[data-new-native-role]').click();
  const dialog = page.getByRole('dialog');
  const submit = dialog.getByRole('button', {
    name: 'Revisar alterações',
    exact: true,
  });
  await expect(submit).toBeDisabled();
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC explicit role creation');
  await expect(submit).toBeDisabled();
  await dialog.locator('#jrc_contact_center_view').check();
  await expect(submit).toBeEnabled();
  await expect(dialog.locator('#jrc_contact_center_publish')).not.toBeChecked();
  await expect(
    dialog.getByText('Participar de uma equipe ou fila', { exact: false })
  ).toBeVisible();
  expect(
    await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' + info.project.name + '-role-create.png',
    fullPage: true,
  });
  await submit.click();
  await expect(dialog.locator('[data-role-review]')).toBeVisible();
  const unsaved = await page.request.get(
    'http://127.0.0.1:5387/api/v1/accounts/' +
      session.account_id +
      '/custom_roles',
    { headers: session.administrator }
  );
  expect((await unsaved.json()).some(row => row.name === name)).toBe(false);
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC revised before confirmation');
  await expect(dialog.locator('[data-role-review]')).toHaveCount(0);
  await submit.click();
  await expect(dialog.locator('[data-role-review]')).toBeVisible();
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' + info.project.name + '-role-review.png',
    fullPage: true,
  });
  await dialog
    .getByRole('button', { name: 'Confirmar alterações', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  const list = await page.request.get(
    'http://127.0.0.1:5387/api/v1/accounts/' +
      session.account_id +
      '/custom_roles',
    {
      headers: session.administrator,
    }
  );
  expect(list.status()).toBe(200);
  const role = (await list.json()).find(row => row.name === name);
  expect(role.permissions).toEqual(['jrc_contact_center_view']);
  await expect(
    page
      .getByRole('combobox', { name: 'Perfil nativo', exact: true })
      .getByRole('option', { name, exact: true })
  ).toHaveCount(1);
});

test('native role denied creation keeps the draft and never persists an unauthorized power', async ({
  page,
}, info) => {
  const name = 'SYNTHETIC denied role ' + info.project.name;
  await page.goto(base + '/permissions');
  await page.locator('[data-new-native-role]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(name);
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC denied grant retained for review');
  await dialog.locator('#jrc_contact_center_view').check();
  await dialog.locator('#jrc_contact_center_publish').check();
  await dialog
    .getByRole('button', { name: 'Revisar alterações', exact: true })
    .click();
  await expect(dialog.locator('[data-role-review]')).toBeVisible();
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/custom_roles') &&
      response.request().method() === 'POST'
  );
  await dialog
    .getByRole('button', { name: 'Confirmar alterações', exact: true })
    .click();
  expect((await rejected).status()).toBe(401);
  await expect(dialog).toBeVisible();
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(name);
  await expect(dialog.locator('#jrc_contact_center_publish')).toBeChecked();
  await expect(page.locator('[popover="manual"]')).toContainText(
    'Não foi possível salvar. Seus dados foram preservados.'
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' + info.project.name + '-role-denied.png',
    fullPage: true,
  });
  const list = await page.request.get(
    'http://127.0.0.1:5387/api/v1/accounts/' +
      session.account_id +
      '/custom_roles',
    {
      headers: session.delegated,
    }
  );
  expect(list.status()).toBe(200);
  expect((await list.json()).some(row => row.name === name)).toBe(false);
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
});

test('native role stale form preserves the draft and requires a fresh explicit review', async ({
  page,
}, info) => {
  const rolesApi =
    'http://127.0.0.1:5387/api/v1/accounts/' +
    session.account_id +
    '/custom_roles';
  const name = 'SYNTHETIC stale role ' + info.project.name;
  const created = await page.request.post(rolesApi, {
    headers: session.administrator,
    data: {
      custom_role: {
        name,
        description: 'Original server version',
        permissions: ['jrc_contact_center_view'],
      },
    },
  });
  expect(created.status()).toBe(200);
  const original = await created.json();
  expect(original.revision).toMatch(/^[0-9a-f]{64}$/);
  await page.goto(base + '/permissions');
  await page
    .getByRole('combobox', { name: 'Perfil nativo', exact: true })
    .selectOption(String(original.id));
  await page.locator('[data-edit-native-role]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(name + ' local');
  await dialog
    .getByLabel('Descrição', { exact: true })
    .fill('SYNTHETIC retained local draft');
  const newer = await page.request.patch(rolesApi + '/' + original.id, {
    headers: session.administrator,
    data: {
      custom_role: { description: 'SYNTHETIC concurrent server version' },
    },
  });
  expect(newer.status()).toBe(200);
  const current = await newer.json();
  expect(current.revision).not.toBe(original.revision);
  await dialog
    .getByRole('button', { name: 'Revisar alterações', exact: true })
    .click();
  const staleSave = page.waitForResponse(
    response =>
      response.url().endsWith('/custom_roles/' + original.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Confirmar alterações', exact: true })
    .click();
  const conflict = await staleSave;
  expect(conflict.request().postDataJSON().expected_revision).toBe(
    original.revision
  );
  expect(conflict.status()).toBe(409);
  await expect(dialog.locator('[data-role-conflict]')).toContainText(
    'outra sessão'
  );
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    name + ' local'
  );
  await expect(dialog.getByLabel('Descrição', { exact: true })).toHaveValue(
    'SYNTHETIC retained local draft'
  );
  await expect(dialog.locator('[data-role-review]')).toHaveCount(0);
  await expect(
    dialog.getByRole('button', { name: 'Revisar alterações', exact: true })
  ).toBeDisabled();
  const preserved = await page.request.get(rolesApi + '/' + original.id, {
    headers: session.administrator,
  });
  expect((await preserved.json()).description).toBe(
    'SYNTHETIC concurrent server version'
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-role-conflict.png',
    fullPage: true,
  });
  await dialog
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(dialog.locator('[data-role-latest]')).toContainText(
    'SYNTHETIC concurrent server version'
  );
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    name + ' local'
  );
  await expect(
    dialog.getByRole('button', { name: 'Revisar alterações', exact: true })
  ).toBeEnabled();
  await dialog
    .getByRole('button', { name: 'Revisar alterações', exact: true })
    .click();
  await expect(dialog.locator('[data-role-review]')).toContainText(
    'SYNTHETIC retained local draft'
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-role-reloaded.png',
    fullPage: true,
  });
  const reviewedSave = page.waitForResponse(
    response =>
      response.url().endsWith('/custom_roles/' + original.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Confirmar alterações', exact: true })
    .click();
  const saved = await reviewedSave;
  expect(saved.request().postDataJSON().expected_revision).toBe(
    current.revision
  );
  expect(saved.status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  await page.reload();
  const final = await page.request.get(rolesApi + '/' + original.id, {
    headers: session.administrator,
  });
  expect(await final.json()).toMatchObject({
    name: name + ' local',
    description: 'SYNTHETIC retained local draft',
    permissions: ['jrc_contact_center_view'],
  });
});

test('configuration audit filters pagination details history and verified export use real records', async ({
  page,
}, info) => {
  const suffix = info.project.name;
  const created = await page.request.post(api + '/queues', {
    headers: session.administrator,
    data: {
      queue: {
        unit_id: session.unit_id,
        code: 'AUDIT-' + suffix,
        name: 'SYNTHETIC audit ' + suffix,
      },
    },
  });
  expect(created.status()).toBe(201);
  const queue = (await created.json()).item;
  for (let index = 0; index < 22; index += 1) {
    const changed = await page.request.patch(api + '/queues/' + queue.id, {
      headers: session.administrator,
      data: {
        queue: { name: 'SYNTHETIC audit ' + suffix + ' version ' + index },
      },
    });
    expect(changed.status()).toBe(200);
  }
  const query =
    '?audit_config_resource_type=queue&audit_config_resource_id=' +
    queue.id +
    '&unrelated_filter=keep';
  await page.goto(base + '/audit' + query);
  const panel = page.locator('[data-configuration-audit]');
  await expect(panel).toBeVisible();
  await expect(panel.locator('[data-audit-row]')).toHaveCount(20);
  await expect(panel).toContainText('Total 23');
  await panel.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(panel.locator('[data-audit-row]')).toHaveCount(3);
  await expect(page).toHaveURL(/audit_config_page=2/);
  await page.reload();
  await expect(panel.locator('[data-audit-row]')).toHaveCount(3);
  await panel.getByRole('button', { name: 'Anterior', exact: true }).click();
  await expect(panel.locator('[data-audit-row]')).toHaveCount(20);
  await page.screenshot({
    path: '.codex/call-center-native-e2e/' + suffix + '-audit-list.png',
    fullPage: true,
  });
  await panel.locator('[data-audit-detail]').first().click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText(
    'SYNTHETIC audit ' + suffix + ' version 20'
  );
  await expect(dialog).toContainText(
    'SYNTHETIC audit ' + suffix + ' version 21'
  );
  await expect(dialog.locator('[data-audit-scopes]')).toContainText(
    '#' + session.unit_id
  );
  await expect(dialog).toContainText('Não comprova publicação');
  const detailColor = await dialog
    .locator('[data-audit-details] dd')
    .first()
    .evaluate(element => getComputedStyle(element).color);
  const expectedColor = await panel
    .locator('header h2')
    .evaluate(element => getComputedStyle(element).color);
  expect(detailColor).toBe(expectedColor);

  await page.screenshot({
    path: '.codex/call-center-native-e2e/' + suffix + '-audit-details.png',
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await panel
    .getByRole('button', { name: 'Ver histórico', exact: true })
    .click();
  await expect(page).toHaveURL(/audit_config_history=true/);
  await expect(panel).toContainText('Histórico completo do recurso');
  await expect(panel.locator('[data-audit-row]')).toHaveCount(20);
  const downloadEvent = page.waitForEvent('download');
  const exportResponse = page.waitForResponse(response =>
    response.url().includes('/configuration_audits/export')
  );
  await panel
    .getByRole('button', { name: 'Exportar relatório', exact: true })
    .click();
  const exported = await exportResponse;
  expect(exported.status()).toBe(200);
  const download = await downloadEvent;
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  const csv = Buffer.concat(chunks);
  const { createHash } = await import('node:crypto');
  expect(createHash('sha256').update(csv).digest('hex')).toBe(
    exported.headers()['x-content-sha256']
  );
  expect(csv.toString('utf8')).toContain('SYNTHETIC audit ' + suffix);
  expect(csv.toString('utf8')).toContain('Escopo posterior');
  expect(csv.toString('utf8')).not.toMatch(/access-token|password|api_key/);
  await panel.getByLabel('Data inicial', { exact: true }).fill('2026-11-18');
  await panel.getByLabel('Data final', { exact: true }).fill('2026-11-17');
  await panel
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(panel.locator('[data-audit-list-error]')).toHaveText(
    'Confira as datas inicial e final.'
  );
  await expect(panel.locator('[data-audit-row]')).toHaveCount(0);
  await panel
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  await expect(panel.locator('[data-audit-row]').first()).toBeVisible();
  await expect(page).toHaveURL(/unrelated_filter=keep/);
  expect(new URL(page.url()).searchParams.has('audit_config_resource_id')).toBe(
    false
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
});

test('configuration audit boundary respects unit account export rights and live revocation', async ({
  page,
}, info) => {
  const changed = await page.request.patch(
    api + '/queues/' + session.allowed_queue_id,
    {
      headers: session.administrator,
      data: { queue: { name: 'SYNTHETIC allowed audit ' + info.project.name } },
    }
  );
  expect(changed.status()).toBe(200);
  const hidden = await page.request.patch(
    api + '/queues/' + session.denied_queue_id,
    {
      headers: session.administrator,
      data: { queue: { name: 'PRIVATE OTHER UNIT ' + info.project.name } },
    }
  );
  expect(hidden.status()).toBe(200);
  const historyQuery = queueId =>
    '?history=true&resource_type=queue&resource_id=' + queueId;
  const privateEvents = await page.request.get(
    api + '/configuration_audits' + historyQuery(session.denied_queue_id),
    {
      headers: session.administrator,
    }
  );
  expect(privateEvents.status()).toBe(200);
  const privateId = (await privateEvents.json()).items[0].id;
  const deniedDetail = await page.request.get(
    api + '/configuration_audits/' + privateId,
    { headers: session.auditor }
  );
  expect(deniedDetail.status()).toBe(404);
  const deniedList = await page.request.get(
    api + '/configuration_audits' + historyQuery(session.denied_queue_id),
    {
      headers: session.auditor,
    }
  );
  expect(deniedList.status()).toBe(200);
  expect((await deniedList.json()).items).toEqual([]);
  const deniedExport = await page.request.get(
    api + '/configuration_audits/export',
    { headers: session.audit_reader }
  );
  expect(deniedExport.status()).toBe(401);
  const forbiddenWrite = await page.request.patch(
    api + '/queues/' + session.allowed_queue_id,
    {
      headers: session.auditor,
      data: { queue: { name: 'Forbidden audit write' } },
    }
  );
  expect(forbiddenWrite.status()).toBe(401);
  const foreign = await page.request.get(
    'http://127.0.0.1:5387/api/v1/accounts/' +
      session.other_account_id +
      '/jrc_contact_center/configuration_audits',
    { headers: session.auditor }
  );
  expect(foreign.status()).toBe(401);
  await page.goto(
    base +
      '/audit?audit_config_resource_type=queue&audit_config_resource_id=' +
      session.allowed_queue_id
  );
  const panel = page.locator('[data-configuration-audit]');
  await expect(panel.locator('[data-audit-row]').first()).toBeVisible();
  await expect(panel).not.toContainText('PRIVATE OTHER UNIT');
  await expect(
    panel
      .getByRole('combobox', { name: 'Unidade operacional', exact: true })
      .locator('option')
  ).not.toContainText(['SYNTHETIC unit B']);
  await panel.locator('[data-audit-detail]').first().click();
  await expect(page.getByRole('dialog')).toContainText(
    'SYNTHETIC allowed audit ' + info.project.name
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-audit-scoped.png',
    fullPage: true,
  });
  await page
    .getByRole('dialog')
    .getByRole('button', { name: 'Fechar', exact: true })
    .click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
  const roleUrl =
    'http://127.0.0.1:5387/api/v1/accounts/' +
    session.account_id +
    '/custom_roles/' +
    session.auditor_role_id;
  try {
    const revoke = await page.request.patch(roleUrl, {
      headers: session.administrator,
      data: {
        custom_role: {
          permissions: [
            'jrc_contact_center_view',
            'jrc_contact_center_supervise',
          ],
        },
      },
    });
    expect(revoke.status()).toBe(200);
    await page.reload();
    await expect(page.locator('[data-configuration-audit]')).toHaveCount(0);
    await expect(page.getByRole('alert')).toContainText('Seção indisponível');
    const denied = await page.request.get(api + '/configuration_audits', {
      headers: session.auditor,
    });
    expect(denied.status()).toBe(401);
  } finally {
    const restore = await page.request.patch(roleUrl, {
      headers: session.administrator,
      data: {
        custom_role: {
          permissions: [
            'jrc_contact_center_view',
            'jrc_contact_center_supervise',
            'jrc_contact_center_audit',
            'jrc_contact_center_reports',
          ],
        },
      },
    });
    expect(restore.status()).toBe(200);
  }
});

test('native queue stale revision preserves the draft and requires explicit fresh confirmation', async ({
  page,
}, info) => {
  const name = 'SYNTHETIC revision queue ' + info.project.name;
  const created = await page.request.post(api + '/queues', {
    headers: session.administrator,
    data: {
      queue: {
        unit_id: session.unit_id,
        name,
        code: 'REVISION-' + info.project.name,
        service_kind: 'voice',
      },
    },
  });
  expect(created.status()).toBe(201);
  const target = (await created.json()).item;
  expect(target.revision).toMatch(/^[a-f0-9]{64}$/);
  await page.goto(base + '/queues?queues_q=' + encodeURIComponent(name));
  await expect(page.locator('[data-resource-row]')).toHaveCount(1);
  await page.locator('[data-edit]').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Nome', { exact: true }).fill(name + ' local draft');
  const concurrent = await page.request.patch(api + '/queues/' + target.id, {
    headers: session.administrator,
    data: { queue: { name: name + ' concurrent server state' } },
  });
  expect(concurrent.status()).toBe(200);
  const current = (await concurrent.json()).item;
  expect(current.revision).not.toBe(target.revision);
  const staleResponse = page.waitForResponse(
    response =>
      response.url().endsWith('/queues/' + target.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const rejected = await staleResponse;
  expect(rejected.request().postDataJSON().expected_revision).toBe(
    target.revision
  );
  expect(rejected.status()).toBe(409);
  await expect(dialog.locator('[data-configuration-conflict]')).toContainText(
    'outra sessão'
  );
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    name + ' local draft'
  );
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-queue-conflict.png',
    fullPage: true,
  });
  await dialog
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(dialog.locator('[data-configuration-latest]')).toContainText(
    name + ' concurrent server state'
  );
  await expect(dialog.getByLabel('Nome', { exact: true })).toHaveValue(
    name + ' local draft'
  );
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog.locator('[data-configuration-review]').check();
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill(name + ' reviewed draft');
  await expect(dialog.locator('[data-configuration-review]')).not.toBeChecked();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog.locator('[data-configuration-review]').check();
  const saveResponse = page.waitForResponse(
    response =>
      response.url().endsWith('/queues/' + target.id) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const saved = await saveResponse;
  expect(saved.request().postDataJSON().expected_revision).toBe(
    current.revision
  );
  expect(saved.status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  const final = await page.request.get(api + '/queues/' + target.id, {
    headers: session.administrator,
  });
  expect(final.status()).toBe(200);
  expect((await final.json()).item.name).toBe(name + ' reviewed draft');
  await page
    .getByLabel('Pesquisar', { exact: true })
    .fill(name + ' reviewed draft');
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await page.reload();
  await expect(page.locator('[data-resource-row]')).toHaveCount(1);
  await expect(page.locator('[data-resource-row]')).toContainText(
    name + ' reviewed draft'
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-queue-revised.png',
    fullPage: true,
  });
});
