import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID, createHash } from 'node:crypto';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);
const nativeObservations = new WeakMap<
  Page,
  { origin: string; pathname: string; method: string; status: number }[]
>();
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
  const auth = info.title.startsWith('linked Customer Master')
    ? session.customer_master_targets[info.project.name].operator
    : info.title.startsWith('local IVR supervisor')
      ? session.ivr_targets[info.project.name].observer
      : info.title.startsWith('local IVR')
        ? info.title.startsWith('local IVR scoped')
          ? session.ivr_targets[info.project.name].scoped
          : session.ivr_targets[info.project.name].administrator
        : info.title.startsWith('native authenticated navigation')
          ? session.navigation_targets[info.project.name].auth
          : info.title.startsWith('native infrastructure root')
            ? session.infrastructure
            : info.title.startsWith('configuration audit boundary')
              ? session.auditor
              : info.title.startsWith('native role denied')
                ? session.delegated
                : info.title.startsWith('corporate boundary')
                  ? session.restricted
                  : info.title.startsWith('profile change')
                    ? session.viewer
                    : session.administrator;
  if (
    info.title.startsWith('local IVR') ||
    info.title.startsWith('linked Customer Master')
  ) {
    const observations = [];
    const prefix = info.title.startsWith('linked Customer Master')
      ? `/api/v1/accounts/${session.customer_master_targets[info.project.name].account_id}/`
      : `/api/v1/accounts/${session.ivr_targets[info.project.name].account_id}/jrc_contact_center/`;
    nativeObservations.set(page, observations);
    page.on('response', response => {
      const address = new URL(response.url());
      if (address.pathname.startsWith(prefix))
        observations.push({
          origin: address.origin,
          pathname: address.pathname,
          method: response.request().method(),
          status: response.status(),
        });
    });
  }
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

test.afterEach(async ({ page }, info) => {
  const observations = nativeObservations.get(page);
  if (!observations) return;
  const evidence = '.codex/call-center-native-e2e';
  fs.mkdirSync(evidence, { recursive: true });
  const identity = createHash('sha256')
    .update(info.title)
    .digest('hex')
    .slice(0, 12);
  fs.writeFileSync(
    path.join(evidence, `${info.project.name}-${identity}-api-origins.json`),
    JSON.stringify(
      {
        synthetic: true,
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        test: info.title,
        observations,
      },
      null,
      2
    )
  );
  nativeObservations.delete(page);
});

test('native infrastructure root navigation loads the existing settings without provider actions', async ({
  page,
}, info) => {
  const writes = [];
  page.on('request', request => {
    if (!['GET', 'HEAD'].includes(request.method()))
      writes.push(request.method());
  });
  await page.goto(base + '/pabx');
  const link = page.locator('[data-native-pabx-settings]');
  await expect(link).toBeVisible();
  const loaded = page.waitForResponse(
    response =>
      response.url().endsWith('/telephony_integration') &&
      response.request().method() === 'GET'
  );
  await link.click();
  await expect(page).toHaveURL(
    new RegExp('/app/accounts/' + session.account_id + '/ramal/configuracao$')
  );
  const settings = await loaded;
  expect(settings.status()).toBe(200);
  expect((await settings.json()).configured).toBe(false);
  await expect(
    page.getByRole('heading', { name: 'Ramais SIP dos agentes', exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Configuração da API PABX', exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('tab', { name: 'Geral', exact: true })
  ).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('tab', { name: 'Diagnóstico', exact: true }).click();
  await expect(
    page.getByRole('button', { name: 'Testar conexão', exact: true })
  ).toBeDisabled();
  await page
    .getByRole('tab', { name: 'Sincronização CDR', exact: true })
    .click();
  await expect(
    page.getByRole('button', { name: 'Solicitar sincronização', exact: true })
  ).toBeDisabled();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-native-pabx-sync.png`,
    fullPage: true,
  });
  await page.getByRole('tab', { name: 'Geral', exact: true }).click();
  const apiUrl = page.locator('[data-pabx-panel="general"] input[type="url"]');
  await apiUrl.fill('not-a-valid-url');
  await page.getByRole('tab', { name: 'Diagnóstico', exact: true }).click();
  await page
    .getByRole('button', { name: 'Salvar configuração', exact: true })
    .click();
  await expect(
    page.getByRole('tab', { name: 'Geral', exact: true })
  ).toHaveAttribute('aria-selected', 'true');
  await expect(apiUrl).toHaveValue('not-a-valid-url');
  await expect(apiUrl).toBeFocused();
  await page
    .getByRole('button', {
      name: 'Descartar alterações e recarregar',
      exact: true,
    })
    .click();
  await expect(apiUrl).toHaveValue('');
  await page.getByRole('tab', { name: 'Diagnóstico', exact: true }).click();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-native-pabx-diagnostic.png`,
    fullPage: true,
  });
  await page.getByRole('tab', { name: 'Geral', exact: true }).click();

  await expect(page.locator('input[type="password"]').first()).toHaveValue('');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-native-pabx-settings.png',
    fullPage: true,
  });
  await page.goBack();
  await expect(page.locator('[data-native-pabx-settings]')).toBeVisible();
  expect(writes).toEqual([]);
});

test('native infrastructure nonroot cannot open infrastructure controls through a forced route', async ({
  page,
}, info) => {
  await page.goto(base + '/pabx');
  await expect(page.locator('[data-native-pabx-settings]')).toHaveCount(0);
  await page.goto(
    '/app/accounts/' + session.account_id + '/ramal/configuracao'
  );
  await expect(
    page.getByText('Esta área é exclusiva do Super Admin.', { exact: true })
  ).toBeVisible();
  await expect(
    page.getByRole('heading', { name: 'Configuração da API PABX', exact: true })
  ).toHaveCount(0);
  const denied = await page.request.get(
    'http://127.0.0.1:5387/api/v1/accounts/' +
      session.account_id +
      '/telephony_integration',
    { headers: session.administrator }
  );
  expect(denied.status()).toBe(403);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-native-pabx-denied.png',
    fullPage: true,
  });
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
  await page.locator('[data-create]').click();
  await dialog
    .getByLabel('Fila', { exact: true })
    .selectOption(String(queue.id));
  await dialog
    .getByLabel('Usuário', { exact: true })
    .selectOption(String(targets.enrollment_scoped.id));
  const scopeRejected = page.waitForResponse(
    response =>
      response.url().endsWith('/queue_memberships') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const scopeResponse = await scopeRejected;
  expect(scopeResponse.status()).toBe(422);
  expect((await scopeResponse.json()).error).toBe('member_scope_mismatch');
  await expect(dialog.getByRole('alert')).toContainText('não possui cobertura');
  await expect(dialog.getByLabel('Fila', { exact: true })).toHaveValue(
    String(queue.id)
  );
  await expect(dialog.getByLabel('Usuário', { exact: true })).toHaveValue(
    String(targets.enrollment_scoped.id)
  );
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-queue-recipient-scope.png',
    fullPage: true,
  });
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
  await page.goto(
    base +
      '/permissions?permission_scope=users&access_users_q=' +
      encodeURIComponent(targets.peer.name)
  );
  await page.locator('[data-edit-authority="' + targets.peer.id + '"]').click();
  await expectContainedDialog(page);
  await expect(
    dialog.locator('[data-inherited-origin="jrc_contact_center_monitor"]')
  ).toContainText(targets.team.name);
  await expect(dialog.locator('[data-user-eligible]')).toBeChecked();
  await expect(
    dialog.locator('[data-deny="jrc_contact_center_monitor"]')
  ).not.toBeChecked();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path:
      '.codex/call-center-native-e2e/' +
      info.project.name +
      '-access-inherited-origin.png',
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
  await expect(page.locator('[data-control-desk] > header')).toHaveCount(1);
  await expect(page.locator('[data-control-desk] > header')).not.toHaveCSS(
    'background-color',
    'rgba(0, 0, 0, 0)'
  );
  const light = await page
    .locator('[data-control-desk] > header')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  await page.evaluate(() => document.documentElement.classList.toggle('dark'));
  const opposite = await page
    .locator('[data-control-desk] > header')
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
  const auditQuery =
    '?resource_type=acw_policy&resource_id=' +
    session.account_id +
    '&history=true';
  const history = await page.request.get(
    api + '/configuration_audits' + auditQuery,
    {
      headers: session.administrator,
    }
  );
  expect(history.status()).toBe(200);
  const event = (await history.json()).items[0];
  expect(event.resource_type).toBe('acw_policy');
  expect(event.resource_id).toBe(session.account_id);
  expect(event.after.voice).toBe(minutes * 60);
  expect(event.before.voice).toBe(policy.limits.voice);
  expect(event.before.voice_required).toBe(policy.voice_required);
  expect(event.after.voice_required).toBe(policy.voice_required);
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await page.goto(
    base +
      '/audit?audit_source=configuration&audit_config_resource_type=acw_policy' +
      '&audit_config_resource_id=' +
      session.account_id +
      '&audit_config_history=true'
  );
  const panel = page.locator('[data-configuration-audit]');
  await expect(panel.locator('[data-audit-row]').first()).toContainText(
    'Pós-atendimento / Tabulação'
  );
  await panel.locator('[data-audit-detail]').first().click();
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('[data-audit-details]')).toContainText(
    'Tempo máximo de tabulação — Voz (segundos)'
  );
  await expect(dialog.locator('[data-audit-details]')).toContainText(
    'Exigir finalização na voz'
  );
  await expect(dialog).toContainText('Registro local confirmado no JRC.');
  const bounds = await dialog.boundingBox();
  expect(bounds!.width).toBeLessThanOrEqual(info.project.use.viewport!.width);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-audit-detail.png`,
    fullPage: true,
  });
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
  const recentRecords = await page.request.get(
    api + '/configuration_audits?page=1&per_page=5',
    { headers: session.administrator }
  );
  expect(recentRecords.status()).toBe(200);
  const latest = (await recentRecords.json()).items;
  expect(latest).toHaveLength(5);
  expect(latest[0].resource_id).toBe(queue.id);
  await page.goto(base + '?unrelated_filter=keep&audit_config_actor_id=999');
  const recent = page.locator('[data-recent-configuration]');
  await expect(recent.locator('[data-recent-event]')).toHaveCount(5);
  expect(
    await recent
      .locator('[data-recent-event]')
      .evaluateAll(elements =>
        elements.map(element => element.getAttribute('data-recent-event'))
      )
  ).toEqual(latest.map(row => String(row.id)));
  await recent.scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${suffix}-recent-activity.png`,
    fullPage: true,
  });
  await recent.locator('[data-recent-event]').first().click();
  const recentDialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await expect(recentDialog).toContainText(
    'SYNTHETIC audit ' + suffix + ' version 20'
  );
  await expect(recentDialog).toContainText(
    'SYNTHETIC audit ' + suffix + ' version 21'
  );
  await expect(recentDialog).toContainText('Não comprova publicação');
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${suffix}-recent-activity-detail.png`,
    fullPage: true,
  });
  await recentDialog.locator('[data-recent-history]').click();
  await expect(page.locator('[data-configuration-audit]')).toBeVisible();
  await expect(page).toHaveURL(/audit_config_history=true/);
  await expect(page).toHaveURL(/unrelated_filter=keep/);
  expect(new URL(page.url()).searchParams.has('audit_config_actor_id')).toBe(
    false
  );
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
  await page.goto(base);
  const recent = page.locator('[data-recent-configuration]');
  await expect(recent.locator('[data-recent-event]').first()).toBeVisible();
  await expect(recent).not.toContainText('PRIVATE OTHER UNIT');
  await expect(
    recent.locator(`[data-recent-event="${privateId}"]`)
  ).toHaveCount(0);
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

test('native authenticated navigation honors inherited supervision, denied reports and revocation', async ({
  page,
}, info) => {
  const target = session.navigation_targets[info.project.name];
  const loaded = page.waitForResponse(
    response =>
      response.url().endsWith('/jrc_contact_center/supervisor') &&
      response.request().method() === 'GET'
  );
  await page.goto(
    `/app/accounts/${session.account_id}/contact-center/supervisor?native_navigation=1`
  );
  expect((await loaded).status()).toBe(200);
  const metrics = page.locator(
    '[data-supervisor-observed-metrics] article strong'
  );
  await expect(metrics).toHaveText(['0', '0', '—', '—']);
  await expect(page.getByText('Demonstração', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Carla Mendes', { exact: true })).toHaveCount(0);
  await expect(page.getByText('91,2%', { exact: true })).toHaveCount(0);
  await expect(page.getByText('2,8%', { exact: true })).toHaveCount(0);
  const profile = await page.request.get(
    'http://127.0.0.1:5387/api/v1/profile',
    { headers: target.auth }
  );
  expect(profile.status()).toBe(200);
  const permissions = (await profile.json()).accounts.find(
    account => account.id === session.account_id
  ).permissions;
  expect(permissions).toContain('jrc_contact_center_supervise');
  expect(permissions).not.toContain('jrc_contact_center_reports');
  expect(permissions).not.toContain('jrc_contact_center_configure');
  const deniedReport = await page.request.get(api + '/reports/summary', {
    headers: target.auth,
  });
  expect(deniedReport.status()).toBe(401);
  const navigation = page.locator('aside nav');
  if (info.project.name.startsWith('mobile')) {
    await page.getByRole('button', { expanded: false }).click();
  }
  await expect(navigation.locator('a[href$="/supervisor"]')).toBeVisible();
  await expect(navigation.locator('a[href$="/relatorios"]')).toHaveCount(0);
  await expect(navigation.locator('a[href$="/gravacoes"]')).toHaveCount(0);
  await expect(navigation.locator('a[href$="/configuracoes"]')).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-authenticated-navigation.png`,
    fullPage: true,
  });

  const previous = await page.request.get(
    api + '/access_authorizations/teams/' + target.team_id,
    { headers: session.administrator }
  );
  expect(previous.status()).toBe(200);
  const revoked = await page.request.patch(
    api + '/access_authorizations/teams/' + target.team_id,
    {
      headers: session.administrator,
      data: {
        authorization: { allowed: [] },
        expected_revision: (await previous.json()).item.revision,
      },
    }
  );
  expect(revoked.status()).toBe(200);
  await page.reload();
  await expect(page.getByRole('alert')).toHaveText(
    'Negado pela verificação nativa de rota no ambiente sintético.'
  );
  const forbidden = await page.request.get(api + '/supervisor', {
    headers: target.auth,
  });
  expect(forbidden.status()).toBe(401);
});

const createSyntheticIvr = async (
  page: Page,
  target,
  name: string,
  unitId = target.allowed_unit_id,
  auth = target.administrator
) => {
  const response = await page.request.post(
    `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/ivr_drafts`,
    {
      headers: auth,
      data: {
        ivr_draft: {
          name,
          unit_id: String(unitId),
          status: 'draft',
          expected_revision: 0,
          request_id: randomUUID(),
          definition: {
            schema_version: 1,
            start: 'end',
            nodes: [{ id: 'end', type: 'end' }],
          },
        },
      },
    }
  );
  expect(response.status()).toBe(201);
  const body = await response.json();
  expect(body.item.local_only).toBe(true);
  expect(body.item.provider_applied).toBe(false);
  return body.item;
};

test('local IVR real editor persists, simulates, imports and exports immutable revisions', async ({
  page,
}, info) => {
  const target = session.ivr_targets[info.project.name];
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/ivr_drafts`;
  expect(info.project.use.baseURL).toBe('http://127.0.0.1:5386');
  const observedEndpoint = new URL(
    new URL(endpoint).pathname,
    info.project.use.baseURL
  ).href;
  const location = `/app/accounts/${target.account_id}/contact-center/ura?native_navigation=1`;
  const name = `SYNTHETIC IVR editor ${info.project.name}`;
  const providerWrites = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (
      !['GET', 'HEAD'].includes(request.method()) &&
      /\/(commands|telephony_integration|sync_calls)(?:[/?]|$)/.test(
        request.url()
      )
    )
      providerWrites.push(request.url());
  });
  await page.goto(location);
  await expect(page.locator('[data-ivr-workspace]')).toBeVisible();
  await page.locator('[data-ivr-new]').click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await dialog.getByLabel('Nome do rascunho', { exact: true }).fill(name);
  await dialog
    .getByLabel('Unidade operacional', { exact: true })
    .selectOption(String(target.allowed_unit_id));
  await dialog.locator('[data-ivr-add="menu"]').click();
  await dialog.locator('[data-ivr-add="queue"]').click();
  await dialog.locator('[data-ivr-add="end"]').click();
  await dialog.getByLabel('Nó inicial', { exact: true }).selectOption('node_1');
  await dialog
    .getByLabel('Espera técnica (segundos)', { exact: true })
    .fill('8');
  await dialog
    .getByLabel('Tentativas de dígito inválido', { exact: true })
    .fill('2');
  await dialog
    .getByRole('button', { name: 'Adicionar opção DTMF', exact: true })
    .click();
  await dialog.getByLabel('Tecla DTMF', { exact: true }).selectOption('1');
  await dialog
    .getByLabel('Destino lógico', { exact: true })
    .selectOption('node_2');
  await dialog
    .getByLabel('Destino sem resposta', { exact: true })
    .selectOption('node_3');
  await dialog
    .getByLabel('Destino após tentativas inválidas', { exact: true })
    .selectOption('node_3');
  await dialog
    .getByLabel('Fila', { exact: true })
    .selectOption(String(target.queue_id));
  await expect(dialog.locator('[data-ivr-map-node]')).toHaveCount(3);
  await expect(dialog.locator('[data-ivr-map-node="node_1"]')).toContainText(
    'node_2'
  );
  await expect(dialog.locator('[data-ivr-map-node="node_1"]')).toContainText(
    'node_3'
  );
  const originalColor = await dialog
    .locator('#ivr-name')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  await page.evaluate(() => document.documentElement.classList.toggle('dark'));
  await expect
    .poll(() =>
      dialog
        .locator('#ivr-name')
        .evaluate(
          (element, initial) =>
            !element
              .getAnimations()
              .some(animation => animation.playState === 'running') &&
            getComputedStyle(element).backgroundColor !== initial,
          originalColor
        )
    )
    .toBe(true);
  const oppositeColor = await dialog
    .locator('#ivr-name')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  expect(oppositeColor).not.toBe(originalColor);
  await page.evaluate(() => document.documentElement.classList.toggle('dark'));
  await expect
    .poll(() =>
      dialog
        .locator('#ivr-name')
        .evaluate(element => getComputedStyle(element).backgroundColor)
    )
    .toBe(originalColor);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ivr-theme.json`,
    JSON.stringify({
      synthetic: true,
      project: info.project.name,
      initial_color: originalColor,
      opposite_color: oppositeColor,
      restored_color: originalColor,
      native_transition_completed: true,
    })
  );
  await dialog.locator('[data-ivr-map]').scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ivr-builder.png`,
    fullPage: true,
  });
  await dialog
    .getByRole('tab', { name: 'Simulação local', exact: true })
    .click();
  await dialog
    .getByLabel('Dígitos DTMF para simulação', { exact: true })
    .fill('1');
  const simulated = page.waitForResponse(
    response =>
      response.url() === observedEndpoint + '/preview' &&
      response.request().method() === 'POST'
  );
  await dialog
    .getByRole('button', { name: 'Simular definição atual', exact: true })
    .click();
  const simulatedResponse = await simulated;
  expect(simulatedResponse.status()).toBe(200);
  const simulationPayload = await simulatedResponse.json();
  expect(simulationPayload.account_id).toBe(String(target.account_id));
  expect(simulationPayload.simulation).toMatchObject({
    local_only: true,
    provider_applied: false,
  });
  await expect(dialog.locator('[data-ivr-simulation]')).toContainText(
    'Destino lógico de fila encontrado'
  );
  await expect(dialog.locator('[data-ivr-simulation]')).toContainText(
    '#' + target.queue_id
  );
  await dialog
    .getByLabel('Dígitos DTMF para simulação', { exact: true })
    .fill('2');
  await expect(dialog.locator('[data-ivr-simulation]')).toHaveCount(0);
  await dialog
    .getByLabel('Dígitos DTMF para simulação', { exact: true })
    .fill('1');
  await expect(dialog.locator('[data-ivr-simulation]')).toHaveCount(0);
  const created = page.waitForResponse(
    response =>
      response.url() === observedEndpoint &&
      response.request().method() === 'POST'
  );
  await dialog.locator('[data-ivr-save]').click();
  const accepted = await created;
  expect(accepted.status()).toBe(201);
  const acceptedPayload = await accepted.json();
  expect(acceptedPayload.account_id).toBe(String(target.account_id));
  const first = acceptedPayload.item;
  await expect(dialog.locator('[data-ivr-saved]')).toContainText(
    'Revisão local salva e recarregada'
  );
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await page.locator('#ivr-search').fill(name);
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  const card = page.locator(`[data-ivr-draft="${first.id}"]`);
  await expect(card).toContainText(name);
  await card
    .getByRole('button', { name: 'Abrir rascunho', exact: true })
    .click();
  await expect(dialog.locator('#ivr-name')).toHaveValue(name);
  await expect(dialog.locator('#ivr-unit')).toBeDisabled();
  await dialog.getByRole('tab', { name: 'JSON', exact: true }).click();
  const previous = await dialog.locator('#ivr-json').inputValue();
  await dialog.locator('#ivr-import').setInputFiles({
    name: 'invalid.json',
    mimeType: 'application/json',
    buffer: Buffer.from('{'),
  });
  await expect(dialog.getByRole('alert')).toContainText(
    'O arquivo não contém uma estrutura local de URA compatível'
  );
  await expect(dialog.locator('#ivr-json')).toHaveValue(previous);
  const imported = JSON.parse(previous);
  imported.nodes[0].timeout_seconds = 9;
  await dialog.locator('#ivr-import').setInputFiles({
    name: 'synthetic-local-ivr.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(imported)),
  });
  await expect
    .poll(async () =>
      JSON.parse(await dialog.locator('#ivr-json').inputValue())
    )
    .toEqual(imported);
  await expect(dialog.getByRole('alert')).toHaveCount(0);
  const changed = JSON.parse(await dialog.locator('#ivr-json').inputValue());
  changed.nodes[0].timeout_seconds = 10;
  await dialog.locator('#ivr-json').fill(JSON.stringify(changed, null, 2));
  await expect(dialog.locator('[data-ivr-save]')).toBeDisabled();
  await dialog
    .getByRole('button', { name: 'Aplicar JSON ao rascunho', exact: true })
    .click();
  const updated = page.waitForResponse(
    response =>
      response.url() === observedEndpoint + '/' + first.id &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-ivr-save]').click();
  expect((await updated).status()).toBe(200);
  await expect(dialog.locator('[data-ivr-saved]')).toContainText(
    'Revisão local salva e recarregada'
  );
  await dialog.getByRole('tab', { name: 'Histórico', exact: true }).click();
  const original = dialog.locator('[data-ivr-history-revision="1"]');
  await expect(original).toBeVisible();
  const downloadEvent = page.waitForEvent('download');
  await original
    .getByRole('button', { name: 'Exportar revisão salva', exact: true })
    .click();
  const download = await downloadEvent;
  expect(download.suggestedFilename()).toBe(`ura-local-${first.id}-v1.json`);
  const stream = await download.createReadStream();
  expect(stream).not.toBeNull();
  const parts = [];
  for await (const chunk of stream) parts.push(chunk);
  const raw = Buffer.concat(parts);
  const exported = JSON.parse(raw.toString());
  const persisted = await page.request.get(
    endpoint + '/' + first.id + '/versions/1',
    { headers: target.administrator }
  );
  expect(persisted.status()).toBe(200);
  const stored = (await persisted.json()).item;
  expect(exported).toEqual(stored.definition);
  expect(exported.nodes[0].timeout_seconds).toBe(8);
  expect(stored.integrity_sha256).toMatch(/^[0-9a-f]{64}$/);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-ivr-export-integrity.json`,
    JSON.stringify({
      synthetic: true,
      revision: 1,
      export_sha256: createHash('sha256').update(raw).digest('hex'),
      revision_integrity_sha256: stored.integrity_sha256,
      provider_applied: false,
    })
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ivr-history.png`,
    fullPage: true,
  });
  await dialog
    .getByRole('button', { name: 'Arquivar localmente', exact: true })
    .click();
  await dialog
    .locator('[data-ivr-confirmation]')
    .getByRole('button', { name: 'Arquivar localmente', exact: true })
    .click();
  await expect(dialog.locator('[data-ivr-saved]')).toContainText(
    'Revisão local salva e recarregada'
  );
  await expect(dialog.locator('[data-ivr-save]')).toContainText(
    'Salvar como nova revisão de rascunho'
  );
  const restored = page.waitForResponse(
    response =>
      response.url() === observedEndpoint + '/' + first.id &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-ivr-save]').click();
  const restoration = await restored;
  expect(restoration.status()).toBe(200);
  expect((await restoration.json()).item).toMatchObject({
    status: 'draft',
    revision: 4,
  });
  await expect(dialog.locator('[data-ivr-saved]')).toBeVisible();
  await dialog.getByRole('tab', { name: 'Histórico', exact: true }).click();
  await expect(dialog.locator('[data-ivr-history-revision="4"]')).toBeVisible();
  await expect(dialog.locator('[data-ivr-history-revision="1"]')).toBeVisible();
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  expect(errors).toEqual([]);
  expect(providerWrites).toEqual([]);
});

test('local IVR scoped records and forced URLs obey corporate coverage and fresh eligibility', async ({
  page,
}, info) => {
  const target = session.ivr_targets[info.project.name];
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/ivr_drafts`;
  const own = await createSyntheticIvr(
    page,
    target,
    `SYNTHETIC scoped own ${info.project.name}`,
    target.allowed_unit_id,
    target.scoped
  );
  const denied = await createSyntheticIvr(
    page,
    target,
    `SYNTHETIC forbidden unit ${info.project.name}`,
    target.denied_unit_id
  );
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk?native_navigation=1`
  );
  await expect(page.locator('[data-card="ivr"]')).toBeVisible();
  await page.locator('[data-card="ivr"]').click();
  const localEditor = page.locator('[data-native-ivr-drafts]');
  await expect(localEditor).toBeVisible();
  await localEditor.scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ivr-configurer-entry.png`,
    fullPage: true,
  });
  await localEditor.click();
  await expect(page).toHaveURL(/contact-center\/ura/);
  await expect(page.locator(`[data-ivr-draft="${own.id}"]`)).toBeVisible();
  await expect(page.locator(`[data-ivr-draft="${denied.id}"]`)).toHaveCount(0);
  for (const suffix of ['', '/versions', '/versions/1', '/export?revision=1']) {
    const result = await page.request.get(endpoint + '/' + denied.id + suffix, {
      headers: target.scoped,
    });
    expect(result.status()).toBe(404);
  }
  const simulated = await page.request.post(
    endpoint + '/' + denied.id + '/simulate',
    {
      headers: target.scoped,
      data: { ivr_simulation: { revision: 1, dtmf: '' } },
    }
  );
  expect(simulated.status()).toBe(404);
  const membershipEndpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/teams/${target.scoped_team_id}/team_members`;
  try {
    const removed = await page.request.delete(membershipEndpoint, {
      headers: target.administrator,
      data: { user_ids: [target.scoped_user_id] },
    });
    expect(removed.status()).toBe(200);
    await page.reload();
    await expect(page.locator('[data-ivr-workspace]')).toBeVisible();
    await expect(page.locator(`[data-ivr-draft="${own.id}"]`)).toHaveCount(0);
    const withheld = await page.request.get(endpoint + '/' + own.id, {
      headers: target.scoped,
    });
    expect(withheld.status()).toBe(404);
    const reactivation = await page.request.post(membershipEndpoint, {
      headers: target.scoped,
      data: { user_ids: [target.scoped_user_id] },
    });
    expect(reactivation.status()).toBe(401);
    await expect(page.locator('[data-ivr-page-count]')).toHaveCount(0);
    await expect(page.locator('[data-ivr-reference-page-count]')).toHaveCount(
      0
    );
    await expect(page.locator('[data-ivr-total]')).toContainText('Total 0');
    await expect(page.getByText('Página 1 de 0', { exact: false })).toHaveCount(
      0
    );
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-team-coverage-denied.png`,
      fullPage: true,
    });
  } finally {
    const rejoined = await page.request.post(membershipEndpoint, {
      headers: target.administrator,
      data: { user_ids: [target.scoped_user_id] },
    });
    expect(rejoined.status()).toBe(200);
  }
  const available = await page.request.get(endpoint + '/' + own.id, {
    headers: target.scoped,
  });
  expect(available.status()).toBe(200);
  await page.reload();
  await expect(page.locator(`[data-ivr-draft="${own.id}"]`)).toBeVisible();
  const accessEndpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/access_authorizations/users/${target.scoped_member_id}`;
  const current = await page.request.get(accessEndpoint, {
    headers: target.administrator,
  });
  expect(current.status()).toBe(200);
  const initial = (await current.json()).item;
  try {
    const revoked = await page.request.patch(accessEndpoint, {
      headers: target.administrator,
      data: {
        expected_revision: initial.revision,
        authorization: { eligible: false },
      },
    });
    expect(revoked.status()).toBe(200);
    await page.reload();
    await expect(page.getByRole('alert')).toContainText(
      'Negado pela verificação nativa'
    );
    await expect(page.locator('[data-ivr-workspace]')).toHaveCount(0);
    const blocked = await page.request.get(endpoint + '/' + own.id, {
      headers: target.scoped,
    });
    expect(blocked.status()).toBe(401);
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-ivr-denied.png`,
      fullPage: true,
    });
  } finally {
    const fresh = await page.request.get(accessEndpoint, {
      headers: target.administrator,
    });
    expect(fresh.status()).toBe(200);
    const restored = await page.request.patch(accessEndpoint, {
      headers: target.administrator,
      data: {
        expected_revision: (await fresh.json()).item.revision,
        authorization: { eligible: initial.eligible },
      },
    });
    expect(restored.status()).toBe(200);
  }
});

test('local IVR pagination, URL filters and stale editor preserve the reviewed draft', async ({
  page,
}, info) => {
  const target = session.ivr_targets[info.project.name];
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/ivr_drafts`;
  expect(info.project.use.baseURL).toBe('http://127.0.0.1:5386');
  const observedEndpoint = new URL(
    new URL(endpoint).pathname,
    info.project.use.baseURL
  ).href;
  const prefix = `SYNTHETIC IVR pages ${info.project.name}`;
  const rows = [];
  for (let index = 0; index < 23; index += 1)
    rows.push(
      await createSyntheticIvr(
        page,
        target,
        `${prefix} ${String(index).padStart(2, '0')}`
      )
    );
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/ura?native_navigation=1`
  );
  await page.locator('#ivr-search').fill(prefix);
  await page
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(page.locator('[data-ivr-list] article')).toHaveCount(20);
  const firstIds = await page
    .locator('[data-ivr-list] article')
    .evaluateAll(elements =>
      elements.map(element => element.getAttribute('data-ivr-draft'))
    );
  await page
    .locator('[data-ivr-pagination]')
    .getByRole('button', { name: 'Próxima', exact: true })
    .click();
  await expect(page).toHaveURL(/ivr_page=2/);
  await expect(page.locator('[data-ivr-list] article')).toHaveCount(3);
  const secondIds = await page
    .locator('[data-ivr-list] article')
    .evaluateAll(elements =>
      elements.map(element => element.getAttribute('data-ivr-draft'))
    );
  expect(firstIds.some(id => secondIds.includes(id))).toBe(false);
  await page.goBack();
  await expect(page.locator('[data-ivr-list] article')).toHaveCount(20);
  const row = rows[22];
  await page
    .locator(`[data-ivr-draft="${row.id}"]`)
    .getByRole('button', { name: 'Abrir rascunho', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await dialog
    .getByLabel('Nome do rascunho', { exact: true })
    .fill(prefix + ' retained local');
  const remote = await page.request.patch(endpoint + '/' + row.id, {
    headers: target.administrator,
    data: {
      ivr_draft: {
        name: prefix + ' accepted server',
        unit_id: String(target.allowed_unit_id),
        status: 'draft',
        definition: row.definition,
        expected_revision: 1,
        request_id: randomUUID(),
      },
    },
  });
  expect(remote.status()).toBe(200);
  const rejected = page.waitForResponse(
    response =>
      response.url() === observedEndpoint + '/' + row.id &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-ivr-save]').click();
  expect((await rejected).status()).toBe(409);
  await expect(dialog.locator('#ivr-name')).toHaveValue(
    prefix + ' retained local'
  );
  await expect(dialog.locator('[data-ivr-save]')).toBeDisabled();
  await dialog
    .locator('[data-configuration-conflict]')
    .getByRole('button')
    .click();
  await expect(dialog.locator('[data-configuration-latest]')).toContainText(
    prefix + ' accepted server'
  );
  await dialog.locator('[data-configuration-review]').check();
  await expect(dialog.locator('[data-ivr-save]')).toBeEnabled();
  await dialog.locator('#ivr-name').fill(prefix + ' changed after review');
  await expect(dialog.locator('[data-ivr-save]')).toBeDisabled();
  await dialog.locator('[data-configuration-review]').check();
  const accepted = page.waitForResponse(
    response =>
      response.url() === observedEndpoint + '/' + row.id &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-ivr-save]').click();
  const response = await accepted;
  expect(response.status()).toBe(200);
  expect(response.request().postDataJSON().ivr_draft.expected_revision).toBe(2);
  expect((await response.json()).item.revision).toBe(3);
  await expect(dialog.locator('[data-ivr-saved]')).toContainText(
    'Revisão local salva e recarregada'
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ivr-conflict-reviewed.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Fechar', exact: true }).click();
  await page
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  await expect(page).not.toHaveURL(/ivr_q=|ivr_page=/);
  await expect(page.locator('[data-ivr-pagination]')).toContainText('Página 1');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
});

test('local IVR supervisor polling clears real scoped units after native eligibility revocation', async ({
  page,
}, info) => {
  const target = session.ivr_targets[info.project.name];
  const api = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  expect(info.project.use.baseURL).toBe('http://127.0.0.1:5386');
  const observedApi = new URL(new URL(api).pathname, info.project.use.baseURL)
    .href;
  const grant =
    api + '/access_authorizations/users/' + target.observer_member_id;
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/supervisor?native_navigation=1`
  );
  const metrics = page.locator(
    '[data-supervisor-observed-metrics] article strong'
  );
  await expect(metrics).toHaveText(['0', '0', '—', '—']);
  await expect(page.locator('[data-supervisor-unit]')).toHaveCount(1);
  await expect(page.locator('[data-supervisor-unit]')).toContainText(
    'SYNTHETIC IVR unit A'
  );
  await expect(page.getByText('active', { exact: true })).toHaveCount(0);
  const previous = await page.request.get(grant, {
    headers: target.administrator,
  });
  expect(previous.status()).toBe(200);
  const original = (await previous.json()).item;
  try {
    const denied = page.waitForResponse(
      response =>
        response.url() === observedApi + '/supervisor' &&
        response.status() === 401,
      { timeout: 15000 }
    );
    const revoked = await page.request.patch(grant, {
      headers: target.administrator,
      data: {
        expected_revision: original.revision,
        authorization: { eligible: false },
      },
    });
    expect(revoked.status()).toBe(200);
    expect((await denied).status()).toBe(401);
    await expect(metrics).toHaveText(['—', '—', '—', '—']);
    await expect(page.locator('[data-supervisor-unit]')).toHaveCount(0);
    await page.screenshot({
      path: `.codex/call-center-native-e2e/${info.project.name}-supervisor-revoked.png`,
      fullPage: true,
    });
    await page.reload();
    await expect(page.getByRole('alert')).toHaveText(
      'Negado pela verificação nativa de rota no ambiente sintético.'
    );
  } finally {
    const current = await page.request.get(grant, {
      headers: target.administrator,
    });
    expect(current.status()).toBe(200);
    const restored = await page.request.patch(grant, {
      headers: target.administrator,
      data: {
        expected_revision: (await current.json()).item.revision,
        authorization: { eligible: original.eligible },
      },
    });
    expect(restored.status()).toBe(200);
    expect(
      (
        await page.request.get(api + '/supervisor', {
          headers: target.observer,
        })
      ).status()
    ).toBe(200);
  }
});

test('linked Customer Master preserves native permissions, persisted values and attendance drafts', async ({
  page,
}, info) => {
  const target = session.customer_master_targets[info.project.name];
  const source = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}`;
  const callRoute = id =>
    `/app/accounts/${target.account_id}/contact-center/chamada/${id}?native_navigation=1`;
  const profile = await page.request.get(
    'http://127.0.0.1:5387/api/v1/profile',
    { headers: target.operator }
  );
  expect(profile.status()).toBe(200);
  const membership = (await profile.json()).accounts.find(
    account => account.id === target.account_id
  );
  expect(membership.role).toBe('agent');
  expect(membership.permissions).toContain('contact_manage');
  expect(membership.permissions).not.toContain('jrc_contact_center_administer');
  expect(membership.permissions).not.toContain('jrc_contact_center_configure');
  await page.goto(callRoute(target.call_id));
  await expect(page.locator('[data-open-linked-master]')).toBeVisible();
  const draft = 'SYNTHETIC unsaved attendance ' + info.project.name;
  await page.getByLabel('Resumo').fill(draft);
  await page.locator('[data-open-linked-master]').click();
  await expectContainedDialog(page);
  const dialog = page.getByRole('dialog');
  const surface = dialog.locator('article').first();
  await expect(surface).toBeVisible();
  const colors = await surface.evaluate(element => ({
    background: getComputedStyle(element).backgroundColor,
    foreground: getComputedStyle(element).color,
  }));
  const background = colors.background;
  expect(background).not.toBe('rgba(0, 0, 0, 0)');
  const channels = background
    .match(/[0-9.]+/g)!
    .slice(0, 3)
    .map(Number);
  expect(channels).toHaveLength(3);
  const brightness = channels.reduce((sum, value) => sum + value, 0);
  const foregroundBrightness = colors.foreground
    .match(/[0-9.]+/g)!
    .slice(0, 3)
    .map(Number)
    .reduce((sum, value) => sum + value, 0);
  if (info.project.name.endsWith('-dark')) {
    expect(brightness).toBeLessThan(300);
    expect(foregroundBrightness).toBeGreaterThan(600);
  } else {
    expect(brightness).toBeGreaterThan(600);
    expect(foregroundBrightness).toBeLessThan(300);
  }
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-linked-master-theme.json`,
    JSON.stringify({ ...colors, channels, viewport: page.viewportSize() })
  );

  await expect(dialog).toContainText('SYNTHETIC master contact 0');
  const fullPage = dialog.getByRole('link', { name: 'Abrir em tela completa', exact: true });
  await expect(fullPage).toHaveAttribute('href', `/app/accounts/${target.account_id}/contacts/${target.contact_id}`);
  await expect(fullPage).toHaveAttribute('target', '_blank');
  await expect(fullPage).toHaveAttribute('rel', 'noopener noreferrer');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await expect(dialog).not.toContainText('SYNTHETIC master contact 1');
  await dialog
    .getByRole('button', { name: 'Empresa e Vínculos', exact: true })
    .click();
  const value = 'SYNTHETIC role ' + info.project.name;
  await dialog.getByLabel('Cargo', { exact: true }).fill(value);
  const saved = page.waitForResponse(
    response =>
      response.url().includes(`/customers/contacts/${target.contact_id}`) &&
      response.request().method() === 'PATCH'
  );
  await dialog
    .getByRole('button', { name: 'Salvar cadastro e vínculo', exact: true })
    .click();
  expect((await saved).status()).toBe(200);
  const stored = await page.request.get(
    source + `/customers/contacts/${target.contact_id}`,
    { headers: target.operator }
  );
  expect(stored.status()).toBe(200);
  expect((await stored.json()).payload.job_title).toBe(value);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-linked-master.png`,
    fullPage: true,
  });
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByLabel('Resumo')).toHaveValue(draft);
  await page.locator('[data-open-linked-master]').click();
  await dialog
    .getByRole('button', { name: 'Empresa e Vínculos', exact: true })
    .click();
  await expect(dialog.getByLabel('Cargo', { exact: true })).toHaveValue(value);
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  for (const id of [target.denied_contact_id, target.foreign_contact_id]) {
    const denied = await page.request.get(
      source + `/customers/contacts/${id}`,
      { headers: target.operator }
    );
    expect(denied.status()).toBe(404);
    expect(await denied.text()).not.toContain('SYNTHETIC master contact 1');
  }
  const foreignAccount = await page.request.get(
    `http://127.0.0.1:5387/api/v1/accounts/${target.foreign_account_id}/customers/contacts/${target.foreign_contact_id}`,
    { headers: target.operator }
  );
  expect(foreignAccount.status()).toBe(401);
  const deniedCall = await page.request.get(
    source + `/jrc_contact_center/call_sessions/${target.denied_call_id}`,
    { headers: target.operator }
  );
  expect(deniedCall.status()).toBe(404);
  await page.goto(callRoute(target.unlinked_call_id));
  await expect(
    page.getByText('SYNTHETIC master contact 0', { exact: true }).first()
  ).toBeVisible();
  await expect(page.locator('[data-open-linked-master]')).toHaveCount(0);
  await page.goto(callRoute(target.call_id));
  await page.locator('[data-open-linked-master]').click();
  await expect(dialog).toBeVisible();
  const roleUrl = source + `/custom_roles/${target.role_id}`;
  const roleResponse = await page.request.get(roleUrl, {
    headers: target.administrator,
  });
  expect(roleResponse.status()).toBe(200);
  const role = await roleResponse.json();
  expect(role.revision).toMatch(/^[a-f0-9]{64}$/);
  const revoked = await page.request.patch(roleUrl, {
    headers: target.administrator,
    data: {
      expected_revision: role.revision,
      custom_role: {
        permissions: ['jrc_contact_center_view', 'jrc_contact_center_operate'],
      },
    },
  });
  expect(revoked.status()).toBe(200);
  const deniedMaster = await page.request.get(
    source + `/customers/contacts/${target.contact_id}`,
    { headers: target.operator }
  );
  expect(deniedMaster.status()).toBe(401);
  await dialog
    .getByRole('button', { name: 'Empresa e Vínculos', exact: true })
    .click();
  await expect(dialog).not.toBeVisible();
  await expect(page.locator('[data-open-linked-master]')).toHaveCount(0);
  const callStillAuthorized = await page.request.get(
    source + `/jrc_contact_center/call_sessions/${target.call_id}`,
    { headers: target.operator }
  );
  expect(callStillAuthorized.status()).toBe(200);
  expect((await callStillAuthorized.json()).item.customer.directory).toBeNull();
});
