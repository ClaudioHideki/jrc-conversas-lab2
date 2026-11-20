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
  const pauseKey = info.title.startsWith('inactive membership native')
    ? 'membership_eligibility'
    : info.title.startsWith('registered ending native')
      ? 'required_endings'
      : info.title.startsWith('ending reason native')
        ? 'form_bindings'
        : info.title.startsWith('Hoya workspace native')
          ? 'hoya_forms'
          : info.title.startsWith('state history native')
            ? 'state_history'
            : info.title.startsWith('operational form native')
              ? 'operational_forms'
              : info.title.startsWith('form bindings native')
                ? 'form_bindings'
                : info.title.startsWith('deferred pause native uncertain')
                  ? 'deferred_pause_retry'
                  : info.title.startsWith('deferred pause native')
                    ? 'deferred_pause'
                    : info.title.startsWith('whole native team deletion')
                      ? 'team_deletion'
                      : info.title.startsWith('pending ACW native navigation')
                        ? 'acw_navigation'
                        : info.title.startsWith('pending ACW native draft')
                          ? 'acw_draft'
                          : info.title.startsWith('pending ACW native review')
                            ? 'acw_review'
                            : info.title.startsWith('team roster last eligible')
                              ? 'team_withdrawal'
                              : info.title.startsWith('native local routing')
                                ? 'routing'
                                : info.title.startsWith('scoped ACW native')
                                  ? 'acw'
                                  : info.title.startsWith(
                                        'last eligible queue withdrawal'
                                      )
                                    ? 'withdrawal'
                                    : info.title.startsWith(
                                          'local pause duration supervisor'
                                        )
                                      ? 'duration'
                                      : info.title.startsWith(
                                            'local pause catalog operator'
                                          )
                                        ? 'operations'
                                        : info.title.startsWith(
                                              'local pause catalog'
                                            )
                                          ? 'editor'
                                          : null;
  const pauseTarget = pauseKey
    ? session.pause_targets[info.project.name][pauseKey]
    : null;
  const auth = info.title.startsWith('ACW form library')
    ? session.acw_form_targets[info.project.name].administrator
    : pauseTarget
      ? info.title.startsWith('Hoya workspace native') ||
        info.title.startsWith('local pause catalog operator') ||
        info.title.startsWith('pending ACW native') ||
        info.title.startsWith('operational form native') ||
        info.title.startsWith('deferred pause native')
        ? pauseTarget.operator
        : pauseTarget.administrator
      : info.title.startsWith('linked Customer Master')
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
    info.title.startsWith('ACW form library') ||
    Boolean(pauseTarget) ||
    info.title.startsWith('local IVR') ||
    info.title.startsWith('linked Customer Master')
  ) {
    const observations = [];
    const prefix = info.title.startsWith('ACW form library')
      ? `/api/v1/accounts/${session.acw_form_targets[info.project.name].account_id}/jrc_contact_center/`
      : pauseKey === 'team_deletion'
        ? `/api/v1/accounts/${pauseTarget.account_id}/`
        : pauseTarget
          ? `/api/v1/accounts/${pauseTarget.account_id}/jrc_contact_center/`
          : info.title.startsWith('linked Customer Master')
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
    'não está elegível para novas atribuições'
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
      const pendingNotice = page
        .locator('[data-administration-section] [role="status"]')
        .filter({ hasText: 'Funcionalidade pendente' });
      await expect(pendingNotice).toHaveCount(1);
      await expect(pendingNotice).toBeVisible();
      await expect(pendingNotice).toContainText('Funcionalidade pendente');
      await expect(page.locator('[data-create]')).toHaveCount(0);
      if (key === 'distribution') {
        await expect(page.locator('[data-routing-create]')).toHaveCount(1);
        await expect(page.locator('[data-publish]')).toHaveCount(0);
      }
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
  const initialRoster = await page.request.get(membershipEndpoint, {
    headers: target.administrator,
  });
  expect(initialRoster.status()).toBe(200);
  const selectedIds = (await initialRoster.json()).map(
    (member: { id: number | string }) => String(member.id)
  );
  expect(selectedIds).toContain(String(target.scoped_user_id));
  const unchangedRoster = await page.request.patch(membershipEndpoint, {
    headers: target.administrator,
    data: { user_ids: selectedIds },
  });
  expect(unchangedRoster.status()).toBe(200);
  const persistedRoster = await page.request.get(membershipEndpoint, {
    headers: target.administrator,
  });
  expect(persistedRoster.status()).toBe(200);
  const persistedIds = (await persistedRoster.json()).map(
    (member: { id: number | string }) => String(member.id)
  );
  expect(persistedIds).toEqual(expect.arrayContaining(selectedIds));
  expect(persistedIds).toHaveLength(selectedIds.length);
  await page.reload();
  await expect(page.locator(`[data-ivr-draft="${own.id}"]`)).toBeVisible();
  await expect(page.locator(`[data-ivr-draft="${denied.id}"]`)).toHaveCount(0);
  const preservedOrigin = await page.request.get(endpoint + '/' + own.id, {
    headers: target.scoped,
  });
  expect(preservedOrigin.status()).toBe(200);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-team-roster-identity.json`,
    JSON.stringify({
      synthetic: true,
      sha: process.env.GITHUB_SHA,
      account_id: target.account_id,
      team_id: target.scoped_team_id,
      selected_ids: selectedIds,
      persisted_ids: persistedIds,
      preserved_origin_id: own.id,
      denied_origin_id: denied.id,
      canonical_string_ids: true,
    })
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-team-roster-preserved.png`,
    fullPage: false,
  });
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
  await expect(page.getByText('Falando', { exact: true })).toBeVisible();
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
  const fullPage = dialog.getByRole('link', {
    name: 'Abrir em tela completa',
    exact: true,
  });
  await expect(fullPage).toHaveAttribute(
    'href',
    `/app/accounts/${target.account_id}/contacts/${target.contact_id}`
  );
  await expect(fullPage).toHaveAttribute('target', '_blank');
  await expect(fullPage).toHaveAttribute('rel', 'noopener noreferrer');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await expect(dialog).not.toContainText('SYNTHETIC master contact 1');
  await expect(dialog.getByText('Carregando...', { exact: true })).toHaveCount(
    0
  );
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-linked-master-overview.png`,
    fullPage: false,
  });
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
  // The native confirmed-update handler performs an authorized reload.
  // Capture the persisted form, never the intermediate loading panel.
  await expect(dialog.getByLabel('Cargo', { exact: true })).toHaveValue(value);
  await expect(dialog.getByText('Carregando...', { exact: true })).toHaveCount(
    0
  );
  await dialog.getByLabel('Cargo', { exact: true }).scrollIntoViewIfNeeded();
  const geometry = await dialog
    .getByLabel('Cargo', { exact: true })
    .evaluate(element => {
      const fieldset = element.closest('fieldset')!;
      const section = fieldset.closest('section')!;
      const outer = section.getBoundingClientRect();
      const inner = fieldset.getBoundingClientRect();
      const style = getComputedStyle(section);
      const controls = [...fieldset.querySelectorAll('input, select, button')]
        .filter(control => control.getClientRects().length > 0)
        .map(control => {
          const rect = control.getBoundingClientRect();
          return { tag: control.tagName, left: rect.left, right: rect.right };
        });
      return {
        section: { left: outer.left, right: outer.right },
        fieldset: { left: inner.left, right: inner.right },
        paddingLeft: parseFloat(style.paddingLeft),
        paddingRight: parseFloat(style.paddingRight),
        controls,
      };
    });
  expect(geometry.fieldset.left).toBeGreaterThanOrEqual(
    geometry.section.left + geometry.paddingLeft
  );
  expect(geometry.fieldset.right).toBeLessThanOrEqual(
    geometry.section.right - geometry.paddingRight
  );
  expect(geometry.controls.length).toBeGreaterThan(4);
  for (const control of geometry.controls) {
    expect(control.left).toBeGreaterThanOrEqual(geometry.fieldset.left - 1);
    expect(control.right).toBeLessThanOrEqual(geometry.fieldset.right + 1);
  }
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-linked-master-form-geometry.json`,
    JSON.stringify(geometry)
  );
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-linked-master.png`,
    fullPage: false,
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

test('global ACW revision preserves drafts across both native editors and requires reviewed retry', async ({
  page,
}, info) => {
  const confirm =
    'Revisei a versão atual e confirmo as alterações do meu rascunho.';
  await page.goto(base + '/closures');
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByLabel('Voz', { exact: true }).fill('00:07');
  const initial = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  expect(initial.status()).toBe(200);
  const original = (await initial.json()).item;
  expect(original.id).toBe(String(session.account_id));
  expect(original.revision).toMatch(/^[a-f0-9]{64}$/);
  const concurrentSeconds = original.limits.voice === 240 ? 300 : 240;
  const changed = await page.request.patch(api + '/acw_policy', {
    headers: session.administrator,
    data: {
      limits: { ...original.limits, voice: concurrentSeconds },
      expected_revision: original.revision,
    },
  });
  expect(changed.status()).toBe(200);
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await rejected).status()).toBe(409);
  await expect(dialog.getByLabel('Voz', { exact: true })).toHaveValue('00:07');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  const conflict = dialog.locator('[data-configuration-conflict]');
  await conflict
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(conflict.locator('[data-configuration-latest]')).toContainText(
    String(concurrentSeconds)
  );
  await expect(conflict.locator('[data-configuration-latest]')).toContainText(
    '420'
  );
  await conflict.getByLabel(confirm, { exact: true }).check();
  await dialog.getByLabel('Voz', { exact: true }).fill('00:08');
  await expect(conflict.getByLabel(confirm, { exact: true })).not.toBeChecked();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await conflict.getByLabel(confirm, { exact: true }).check();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeEnabled();
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-revision-popup.png`,
    fullPage: false,
  });
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  const persisted = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  expect((await persisted.json()).item.limits.voice).toBe(480);

  await page.goto(
    `/app/accounts/${session.account_id}/contact-center/configuracoes?native_navigation=1`
  );
  const form = page
    .locator('form')
    .filter({ has: page.locator('[data-save-acw-policy]') });
  await expect(form).toBeVisible();
  const numbers = form.locator('input[type="number"]');
  await numbers.nth(0).fill('540');
  const current = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  const currentPolicy = (await current.json()).item;
  const second = await page.request.patch(api + '/acw_policy', {
    headers: session.administrator,
    data: {
      limits: { ...currentPolicy.limits, voice: 600 },
      expected_revision: currentPolicy.revision,
    },
  });
  expect(second.status()).toBe(200);
  const legacyRejected = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-acw-policy]').click();
  expect((await legacyRejected).status()).toBe(409);
  await expect(numbers.nth(0)).toHaveValue('540');
  const legacyConflict = form.locator('[data-configuration-conflict]');
  await legacyConflict
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(
    legacyConflict.locator('[data-configuration-latest]')
  ).toContainText('600');
  await expect(
    legacyConflict.locator('[data-configuration-latest]')
  ).toContainText('540');
  await expect(form.locator('[data-save-acw-policy]')).toBeDisabled();
  await legacyConflict.getByLabel(confirm, { exact: true }).check();
  await expect(form.locator('[data-save-acw-policy]')).toBeEnabled();
  const settingsHeading = page.getByRole('heading', {
    level: 1,
    name: 'Configuracoes Contact Center',
    exact: true,
  });
  await expect(settingsHeading).toHaveCount(1);
  await expect(settingsHeading).toHaveCSS('color', 'rgb(255, 255, 255)');
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-revision-settings.png`,
    fullPage: true,
  });
  const confirmed = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-acw-policy]').click();
  expect((await confirmed).status()).toBe(200);
  const final = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  expect((await final.json()).item.limits.voice).toBe(540);
  const scopedMetadata = await page.request.get(api + '/administration', {
    headers: session.restricted,
  });
  expect(scopedMetadata.status()).toBe(200);
  expect((await scopedMetadata.json()).capabilities.configuration_global).toBe(
    false
  );
  await page.addInitScript(
    auth => Reflect.set(window, '__SYNTHETIC_AUTH__', auth),
    session.restricted
  );
  await page.goto(
    `/app/accounts/${session.account_id}/contact-center/configuracoes?native_navigation=1`
  );
  await expect(page.locator('[data-global-acw-denied]')).toBeVisible();
  await expect(page.locator('[data-save-acw-policy]')).toHaveCount(0);
  const currentGlobal = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  const globalPolicy = (await currentGlobal.json()).item;
  const deniedGlobal = await page.request.patch(api + '/acw_policy', {
    headers: session.restricted,
    data: {
      limits: { ...globalPolicy.limits, voice: 660 },
      expected_revision: globalPolicy.revision,
    },
  });
  expect(deniedGlobal.status()).toBe(401);
  const unchanged = await page.request.get(api + '/acw_policy', {
    headers: session.administrator,
  });
  expect((await unchanged.json()).item).toEqual(globalPolicy);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-revision-scoped-settings.png`,
    fullPage: true,
  });
});

test('linked Customer Master operating records remain visible in their native scope after real UI creation', async ({
  page,
}, info) => {
  const target = session.customer_master_targets[info.project.name];
  const source = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const route = `/app/accounts/${target.account_id}/contact-center/chamada/${target.call_id}?native_navigation=1`;
  await page.goto(route);
  const uiOrigin = new URL(page.url()).origin;
  expect(uiOrigin).toBe('http://127.0.0.1:5386');
  const sourcePath = new URL(source).pathname;
  await expect(page.getByText('Falando', { exact: true })).toBeVisible();
  await expect(
    page.getByText('Falando · Fila ' + target.queue_id, { exact: true })
  ).toBeVisible();
  const summary = 'SYNTHETIC persisted origin ' + info.project.name;
  await page
    .getByLabel('Motivo do atendimento', { exact: true })
    .fill('SYNTHETIC callback follow-up');
  await page.getByLabel('Resumo', { exact: true }).fill(summary);
  const caseSaved = page.waitForResponse(response => {
    const address = new URL(response.url());
    return (
      address.origin === uiOrigin &&
      address.pathname === sourcePath + '/cases' &&
      response.request().method() === 'POST'
    );
  });
  await page
    .getByRole('button', { name: 'Criar ocorrencia', exact: true })
    .click();
  const created = await caseSaved;
  expect(created.status()).toBe(201);
  const occurrence = (await created.json()).item;
  expect(occurrence.call_session_id).toBe(target.call_id);
  expect(occurrence.unit_id).toBe(target.unit_id);
  expect(occurrence.queue_id).toBe(target.queue_id);
  const cases = await page.request.get(source + '/cases', {
    headers: target.operator,
  });
  expect(cases.status()).toBe(200);
  expect((await cases.json()).items).toContainEqual(
    expect.objectContaining({ id: occurrence.id, summary })
  );
  await page.reload();
  await expect(page.getByText('Falando', { exact: true })).toBeVisible();
  await page
    .getByLabel('Agendado para', { exact: true })
    .fill('2026-12-01T14:30');
  const callbackSaved = page.waitForResponse(response => {
    const address = new URL(response.url());
    return (
      address.origin === uiOrigin &&
      address.pathname === sourcePath + '/callbacks' &&
      response.request().method() === 'POST'
    );
  });
  await page
    .getByRole('button', {
      name: 'Agendar callback na Minha Agenda',
      exact: true,
    })
    .click();
  const callbackResponse = await callbackSaved;
  expect(callbackResponse.status()).toBe(201);
  const callback = (await callbackResponse.json()).item;
  expect(callback.call_session_id).toBe(target.call_id);
  expect(callback.queue_id).toBe(target.queue_id);
  const callbacks = await page.request.get(source + '/callbacks', {
    headers: target.operator,
  });
  expect(callbacks.status()).toBe(200);
  expect((await callbacks.json()).items).toContainEqual(
    expect.objectContaining({ id: callback.id, queue_id: target.queue_id })
  );
  const caseDetails = await page.request.get(
    source + `/cases/${occurrence.id}`,
    { headers: target.operator }
  );
  expect(caseDetails.status()).toBe(200);
  expect((await caseDetails.json()).item.events).toContainEqual(
    expect.objectContaining({ event_type: 'created' })
  );
  const forbidden = await page.request.post(source + '/callbacks', {
    headers: target.operator,
    data: {
      callback: {
        ...callback,
        id: undefined,
        call_session_id: target.denied_call_id,
        idempotency_key: randomUUID(),
      },
    },
  });
  expect(forbidden.status()).toBe(404);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-scoped-operating-records.png`,
    fullPage: true,
  });
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-scoped-operating-records.json`,
    JSON.stringify({
      synthetic: true,
      sha: process.env.GITHUB_SHA,
      account_id: target.account_id,
      call_id: target.call_id,
      case_id: occurrence.id,
      callback_id: callback.id,
      unit_id: target.unit_id,
      queue_id: target.queue_id,
      denied_source_status: forbidden.status(),
    })
  );
});

test('local pause catalog editor persists HH:MM, pagination, explicit policy and reviewed conflicts', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].editor;
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
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await catalog
    .getByRole('button', { name: 'Novo motivo de pausa', exact: true })
    .click();
  await expectContainedDialog(page);
  let dialog = page.getByRole('dialog');
  await dialog.getByLabel('Código', { exact: true }).fill('synthetic_created');
  await dialog
    .getByLabel('Nome', { exact: true })
    .fill('SYNTHETIC created by real UI');
  await dialog.getByLabel('Categoria', { exact: true }).fill('SYNTHETIC');
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
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-popup.png`,
    fullPage: false,
  });
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
});

test('local pause catalog operator preserves legacy history and enforces only authorized new reasons', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].operations;
  const api = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const catalogUrl = api + '/pause_catalog';
  const initial = await page.request.get(catalogUrl, {
    headers: target.administrator,
  });
  const old = (await initial.json()).item;
  const definitions = [
    {
      code: 'synthetic_a',
      name: 'SYNTHETIC allowed pause A',
      justification_required: true,
      category: 'SYNTHETIC',
      description: '',
      active: true,
      minimum_minutes: 0,
      default_minutes: 30,
      maximum_minutes: 60,
      unit_ids: [target.unit_id],
      custom_role_ids: [target.operator_role_id],
    },
    {
      code: 'synthetic_b',
      name: 'SYNTHETIC denied pause B',
      category: 'SYNTHETIC',
      description: '',
      active: true,
      minimum_minutes: 0,
      default_minutes: 30,
      maximum_minutes: 60,
      unit_ids: [target.denied_unit_id],
      custom_role_ids: [],
    },
  ];
  const saved = await page.request.patch(catalogUrl, {
    headers: target.administrator,
    data: {
      pause_catalog: { enforced: false, entries: definitions },
      expected_revision: old.revision,
    },
  });
  expect(saved.status()).toBe(200);
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/operacao?native_navigation=1`
  );
  const observedContext = await page.request.get(api + '/context', {
    headers: target.operator,
  });
  expect(observedContext.status()).toBe(200);
  const counts = (await observedContext.json()).counts;
  const cockpit = page.locator('[data-cockpit-observed-metrics]');
  await expect(cockpit.locator('article strong')).toHaveText([
    String(counts.active_calls),
    String(counts.pending_callbacks),
    '—',
    String(counts.open_cases),
  ]);
  await expect(cockpit).toContainText('Chamadas ativas');
  await expect(cockpit).toContainText('Retornos pendentes');
  await expect(cockpit).toContainText('Ocorrências abertas');
  await expect(cockpit).toContainText('Tempo médio pendente de fonte');
  const reasons = page.getByRole('combobox', {
    name: 'Motivo da pausa',
    exact: true,
  });
  await expect(reasons.locator('option[value="coffee"]')).toHaveCount(1);
  await expect(reasons.locator('option[value="synthetic_a"]')).toHaveCount(1);
  await expect(reasons.locator('option[value="synthetic_b"]')).toHaveCount(0);
  await reasons.selectOption('coffee');
  await page.getByRole('button', { name: 'Em pausa', exact: true }).click();
  await expect(page.getByRole('timer')).toBeVisible();
  const legacy = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  const legacyState = (await legacy.json()).item;
  expect(legacyState.reason_code).toBe('coffee');
  const activated = await page.request.patch(catalogUrl, {
    headers: target.administrator,
    data: {
      pause_catalog: { enforced: true, entries: definitions },
      expected_revision: (await saved.json()).item.revision,
      activation_confirmed: true,
    },
  });
  expect(activated.status()).toBe(200);
  await page.reload();
  await expect(page.getByRole('timer')).toBeVisible();
  const stillPaused = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  expect((await stillPaused.json()).item).toMatchObject({
    state: 'paused',
    state_version: legacyState.state_version,
    reason_code: 'coffee',
  });
  await expect(reasons.locator('option[value="coffee"]')).toHaveCount(0);
  await expect(reasons.locator('option[value="synthetic_b"]')).toHaveCount(0);
  await page.getByRole('button', { name: 'Retomar', exact: true }).click();
  await expect(page.getByRole('timer')).toHaveCount(0);
  const ready = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  const before = (await ready.json()).item;
  const denied = await page.request.patch(api + '/agent_state', {
    headers: target.operator,
    data: {
      agent_state: {
        state: 'paused',
        reason_code: 'synthetic_b',
        queue_id: target.queue_id,
        expected_state_version: before.state_version,
        command_id: randomUUID(),
      },
    },
  });
  expect(denied.status()).toBe(422);
  const deniedGlobal = await page.request.get(catalogUrl, {
    headers: target.scoped,
  });
  expect(deniedGlobal.status()).toBe(401);
  const deniedOperator = await page.request.get(catalogUrl, {
    headers: target.operator,
  });
  expect(deniedOperator.status()).toBe(401);
  await page
    .getByRole('combobox', { name: 'Filas', exact: true })
    .selectOption(String(target.queue_id));
  await reasons.selectOption('synthetic_a');
  const justification = page.getByRole('textbox', {
    name: 'Justificativa da pausa',
    exact: true,
  });
  await expect(justification).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Em pausa', exact: true })
  ).toBeDisabled();
  const requiredDenied = await page.request.patch(api + '/agent_state', {
    headers: target.operator,
    data: {
      agent_state: {
        state: 'paused',
        reason_code: 'synthetic_a',
        queue_id: target.queue_id,
        expected_state_version: before.state_version,
        command_id: randomUUID(),
      },
    },
  });
  expect(requiredDenied.status()).toBe(422);
  expect((await requiredDenied.json()).error).toBe(
    'pause_justification_required'
  );
  const afterRequired = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  expect((await afterRequired.json()).item.state_version).toBe(
    before.state_version
  );
  await justification.fill('SYNTHETIC private explanation from real UI');
  await expect(
    page.getByRole('button', { name: 'Em pausa', exact: true })
  ).toBeEnabled();
  await page.getByRole('button', { name: 'Em pausa', exact: true }).click();
  await expect(page.getByRole('timer')).toContainText(
    'SYNTHETIC allowed pause A'
  );
  const final = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  const paused = (await final.json()).item;
  expect(paused).toMatchObject({
    state: 'paused',
    reason_code: 'synthetic_a',
    provider_confirmed: false,
    pause_definition: {
      name: 'SYNTHETIC allowed pause A',
      justification: 'SYNTHETIC private explanation from real UI',
      justification_required: true,
      default_minutes: 30,
      maximum_minutes: 60,
    },
  });
  await page.reload();
  await expect(page.locator('[data-own-pause-justification]')).toContainText(
    'SYNTHETIC private explanation from real UI'
  );
  expect(paused.pause_definition).not.toHaveProperty('unit_ids');
  expect(paused.pause_catalog.entries.map(row => row.code)).toEqual([
    'synthetic_a',
  ]);
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await page.locator('[data-own-pause-justification]').scrollIntoViewIfNeeded();
  await expect(page.locator('[data-own-pause-justification]')).toBeVisible();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pause-catalog-operator.png`,
    fullPage: false,
  });
});

test('team roster last eligible withdrawal uses real native review, persistence and scoped audit', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].team_withdrawal;
  const nativeBase = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}`;
  const rosterEndpoint = `${nativeBase}/teams/${target.team_id}/team_members`;
  const rosterPath = new URL(rosterEndpoint).pathname;
  const queueEndpoint = `${nativeBase}/jrc_contact_center/queue_memberships?queue_id=${target.queue_id}`;
  const initial = await page.request.get(queueEndpoint, {
    headers: target.administrator,
  });
  expect(initial.status()).toBe(200);
  const originalMembership = (await initial.json()).items[0];
  const nativeWrites = [];
  page.on('request', request => {
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        request.url()
      ) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      nativeWrites.push(request.url());
  });
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/queues?queues_tab=teams`
  );
  const teamRow = page
    .locator('[data-resource-row]')
    .filter({ hasText: target.team_name });
  await expect(teamRow).toHaveCount(1);
  await teamRow.locator('[data-edit]').click();
  await expectContainedDialog(page);
  const dialog = page.getByRole('dialog');
  const selection = dialog.locator(
    `[data-team-member="${target.operator_user_id}"]`
  );
  await expect(selection).toBeChecked();
  await selection.uncheck();
  const first = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === rosterPath &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-save-team-members]').click();
  const blocked = await first;
  expect(new URL(blocked.url()).origin).toBe('http://127.0.0.1:5386');
  expect(blocked.status()).toBe(409);
  const review = (await blocked.json()).review;
  expect(review).toMatchObject({
    account_id: String(target.account_id),
    team_id: String(target.team_id),
    operation: 'update',
  });
  expect(review.queues).toEqual([
    expect.objectContaining({
      queue_id: String(target.queue_id),
      previous_count: 1,
      remaining_count: 0,
    }),
  ]);
  const impact = dialog.locator('[data-team-roster-withdrawal-review]');
  await expect(impact).toBeVisible();
  await expect(impact).toContainText(review.queues[0].queue_name);
  await expect(dialog.locator('[data-save-team-members]')).toBeDisabled();
  const intact = await page.request.get(rosterEndpoint, {
    headers: target.administrator,
  });
  expect((await intact.json()).map(member => member.id)).toContain(
    target.operator_user_id
  );
  const denied = await page.request.patch(rosterEndpoint, {
    headers: target.operator,
    data: { user_ids: [] },
  });
  expect(denied.status()).toBe(401);
  const forged = await page.request.patch(rosterEndpoint, {
    headers: target.administrator,
    data: {
      user_ids: [],
      manager_confirmation: {
        confirmed: 'true',
        review_token: review.review_token,
      },
    },
  });
  expect(forged.status()).toBe(409);
  await selection.check();
  await expect(impact).toHaveCount(0);
  await selection.uncheck();
  const next = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === rosterPath &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-save-team-members]').click();
  expect((await next).status()).toBe(409);
  await dialog.locator('[data-team-manager-withdrawal-confirm]').check();
  await expect(dialog.locator('[data-save-team-members]')).toBeEnabled();
  await impact.scrollIntoViewIfNeeded();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  const reviewColor = await impact.evaluate(
    element => getComputedStyle(element).color
  );
  const reviewBrightness = reviewColor
    .match(/[\d.]+/g)
    .slice(0, 3)
    .map(Number)
    .reduce((sum, value) => sum + value, 0);
  if (info.project.name.endsWith('dark'))
    expect(reviewBrightness).toBeGreaterThan(600);
  else expect(reviewBrightness).toBeLessThan(300);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-team-last-agent-theme.json`,
    JSON.stringify({ color: reviewColor, brightness: reviewBrightness })
  );
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-team-last-agent-manager-review.png`,
    fullPage: false,
  });
  const save = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === rosterPath &&
      response.request().method() === 'PATCH'
  );
  await dialog.locator('[data-save-team-members]').click();
  expect((await save).status()).toBe(200);
  await expect(impact).toHaveCount(0);
  await page.reload();
  const persisted = await page.request.get(rosterEndpoint, {
    headers: target.administrator,
  });
  expect(await persisted.json()).toEqual([]);
  const assignments = await page.request.get(queueEndpoint, {
    headers: target.administrator,
  });
  expect((await assignments.json()).items[0]).toMatchObject({
    id: originalMembership.id,
    active: true,
  });
  const historyUrl = `${nativeBase}/jrc_contact_center/configuration_audits?resource_type=queue&resource_id=${target.queue_id}&history=true`;
  const history = await page.request.get(historyUrl, {
    headers: target.administrator,
  });
  expect(history.status()).toBe(200);
  const reviews = (await history.json()).items.filter(
    row => row.manager_review?.kind === 'jrc_cc_team_roster_withdrawal_v1'
  );
  expect(reviews).toHaveLength(1);
  expect(reviews[0].manager_review).toMatchObject({
    team_id: String(target.team_id),
    queue_id: String(target.queue_id),
    previous_count: 1,
    remaining_count: 0,
  });
  expect(reviews[0].manager_review.receipt_sha256).toMatch(/^[a-f0-9]{64}$/);
  expect(reviews[0].manager_review).not.toHaveProperty('review_token');
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/audit?audit_source=configuration&audit_config_resource_type=queue&audit_config_resource_id=${target.queue_id}&audit_config_history=true`
  );
  const auditPanel = page.locator('[data-configuration-audit]');
  await expect(auditPanel).toBeVisible();
  await auditPanel
    .locator('[data-audit-row]')
    .filter({ hasText: `Fila #${target.queue_id} · Alteração` })
    .locator('[data-audit-detail]')
    .click();
  const auditDialog = page.getByRole('dialog', {
    name: 'Detalhes do evento',
    exact: true,
  });
  await expect(auditDialog).toBeVisible();
  const managerReview = auditDialog.locator(
    '[data-audited-manager-withdrawal]'
  );
  await expect(managerReview).toHaveCount(1);
  await managerReview.scrollIntoViewIfNeeded();
  await expect(managerReview).toBeVisible();
  await expect(managerReview).toContainText(`equipe #${target.team_id}`);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-team-last-agent-audit.png`,
    fullPage: false,
  });
  expect(nativeWrites).toEqual([]);
});

test('last eligible queue withdrawal requires actual manager review and preserves native audit and scope', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].withdrawal;
  const api = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const read = await page.request.get(
    `${api}/queue_memberships?queue_id=${target.queue_id}&page=1`,
    { headers: target.administrator }
  );
  expect(read.status()).toBe(200);
  const rows = (await read.json()).items;
  expect(rows).toHaveLength(1);
  const membership = rows[0];
  expect(membership.active).toBe(true);
  const endpoint = `${api}/queue_memberships/${membership.id}`;
  const writes = [];
  page.on('request', request => {
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        request.url()
      ) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      writes.push(request.url());
  });
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/queues?queues_tab=memberships`
  );
  const row = page
    .locator('[data-resource-row]')
    .filter({ hasText: membership.queue_name });
  await expect(row).toHaveCount(1);
  await row.locator('[data-edit]').click();
  await expectContainedDialog(page);
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Ativo', { exact: true }).uncheck();
  const uiPath = new URL(endpoint).pathname;
  const first = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === uiPath &&
      new URL(response.url()).origin === 'http://127.0.0.1:5386' &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const rejected = await first;
  expect(rejected.status()).toBe(409);
  const review = (await rejected.json()).review;
  expect(review).toMatchObject({
    account_id: String(target.account_id),
    membership_id: String(membership.id),
    previous_count: 1,
    remaining_count: 0,
  });
  await expect(dialog.locator('[data-queue-withdrawal-review]')).toContainText(
    membership.queue_name
  );
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  const intact = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect((await intact.json()).item.active).toBe(true);
  const unconfirmed = await page.request.patch(endpoint, {
    headers: target.administrator,
    data: {
      queue_membership: { active: false },
      expected_revision: membership.revision,
      manager_confirmation: {
        confirmed: 'true',
        review_token: review.review_token,
      },
    },
  });
  expect(unconfirmed.status()).toBe(409);
  await dialog.locator('[data-manager-withdrawal-confirm]').check();
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeEnabled();
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-last-eligible-manager-review.png`,
    fullPage: false,
  });
  const saved = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === uiPath &&
      new URL(response.url()).origin === 'http://127.0.0.1:5386' &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(200);
  await expect(dialog).toBeHidden();
  await page.reload();
  const persisted = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect((await persisted.json()).item.active).toBe(false);
  const history = await page.request.get(
    `${api}/configuration_audits?resource_type=membership&resource_id=${membership.id}&history=true`,
    { headers: target.administrator }
  );
  expect(history.status()).toBe(200);
  const events = (await history.json()).items.filter(
    event => event.operation === 'update'
  );
  expect(events).toHaveLength(1);
  expect(events[0].manager_review).toMatchObject({
    kind: 'jrc_cc_last_eligible_withdrawal_v1',
    membership_id: String(membership.id),
    queue_id: String(target.queue_id),
    previous_count: 1,
    remaining_count: 0,
  });
  expect(events[0].manager_review.receipt_sha256).toMatch(/^[a-f0-9]{64}$/);
  expect(events[0].manager_review).not.toHaveProperty('review_token');
  const denied = await page.request.patch(endpoint, {
    headers: target.operator,
    data: { queue_membership: { active: true } },
  });
  expect(denied.status()).toBe(401);
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/audit?audit_source=configuration&audit_config_resource_type=membership&audit_config_resource_id=${membership.id}&audit_config_history=true`
  );
  const auditPanel = page.locator('[data-configuration-audit]');
  await expect(auditPanel).toBeVisible();
  const withdrawalRow = auditPanel.locator('[data-audit-row]').filter({
    hasText: `Vínculo de agente #${membership.id} · Alteração`,
  });
  await expect(withdrawalRow).toHaveCount(1);
  const detailResponse = page.waitForResponse(response => {
    const url = new URL(response.url());
    return (
      url.origin === 'http://127.0.0.1:5386' &&
      url.pathname ===
        `/api/v1/accounts/${target.account_id}/jrc_contact_center/configuration_audits/${events[0].id}` &&
      response.request().method() === 'GET'
    );
  });
  await withdrawalRow.locator('[data-audit-detail]').click();
  const loadedDetail = await detailResponse;
  expect(loadedDetail.status()).toBe(200);
  expect((await loadedDetail.json()).item.id).toBe(events[0].id);
  const auditDialog = page.getByRole('dialog');
  await expect(auditDialog).toBeVisible();
  await expect(
    auditDialog.locator('[data-audited-manager-withdrawal]')
  ).toHaveCount(1);
  await expect(
    auditDialog.locator('[data-audited-manager-withdrawal]')
  ).toContainText('Retirada confirmada pelo gestor');
  await expect(auditDialog).toContainText('Não comprova publicação');
  const auditedConfirmation = auditDialog.locator(
    '[data-audited-manager-withdrawal]'
  );
  await auditedConfirmation.scrollIntoViewIfNeeded();
  await expect(auditedConfirmation).toBeVisible();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-last-eligible-audit.png`,
    fullPage: false,
  });
  expect(writes).toEqual([]);
});

test('local pause duration supervisor shows authorized real elapsed evidence without private text or automatic resumption', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].duration;
  const api = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const previous = await page.request.get(api + '/pause_catalog', {
    headers: target.administrator,
  });
  expect(previous.status()).toBe(200);
  const saved = await page.request.patch(api + '/pause_catalog', {
    headers: target.administrator,
    data: {
      pause_catalog: {
        enforced: true,
        entries: [
          {
            code: 'synthetic_duration',
            name: 'SYNTHETIC duration notice',
            category: 'SYNTHETIC',
            active: true,
            minimum_minutes: 0,
            default_minutes: 0,
            maximum_minutes: 0,
            unit_ids: [target.unit_id],
            custom_role_ids: [target.operator_role_id],
            justification_required: true,
          },
        ],
      },
      expected_revision: (await previous.json()).item.revision,
      activation_confirmed: true,
    },
  });
  expect(saved.status()).toBe(200);
  const paused = await page.request.patch(api + '/agent_state', {
    headers: target.operator,
    data: {
      agent_state: {
        state: 'paused',
        reason_code: 'synthetic_duration',
        queue_id: target.queue_id,
        command_id: randomUUID(),
        expected_state_version: '0',
        justification: 'SYNTHETIC PRIVATE duration text',
      },
    },
  });
  expect(paused.status()).toBe(200);
  const version = (await paused.json()).item.state_version;
  const writes = [];
  page.on('request', request => {
    const pathname = new URL(request.url()).pathname;
    const operational =
      pathname.startsWith(
        `/api/v1/accounts/${target.account_id}/jrc_contact_center/`
      ) ||
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(pathname);
    if (operational && !['GET', 'HEAD'].includes(request.method()))
      writes.push(pathname);
  });
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/supervisor?native_navigation=1`
  );
  const notice = page.locator('[data-supervisor-pause-notice]');
  await expect(notice).toHaveCount(1);
  await expect(notice).toContainText('Tempo em pausa:');
  await expect(notice.getByRole('status')).toContainText(
    'A pausa continua ativa',
    { timeout: 15000 }
  );
  await notice.scrollIntoViewIfNeeded();
  await expect(notice).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  await notice.scrollIntoViewIfNeeded();
  await expect(notice).toBeVisible();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-supervisor-pause-notice.png`,
    fullPage: false,
  });
  const observed = await page.request.get(api + '/supervisor', {
    headers: target.administrator,
  });
  expect(observed.status()).toBe(200);
  const body = await observed.json();
  expect(body.agents).toHaveLength(1);
  expect(body.agents[0].pause_notice.exceeded).toBe(true);
  expect(JSON.stringify(body)).not.toContain('SYNTHETIC PRIVATE duration text');
  const unchanged = await page.request.get(api + '/agent_state', {
    headers: target.operator,
  });
  expect((await unchanged.json()).item).toMatchObject({
    state: 'paused',
    state_version: version,
    provider_confirmed: false,
    eligible: false,
  });
  expect(writes).toEqual([]);
});

test('pending ACW native draft persists incomplete answers and completes only after explicit tabulation', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].acw_draft;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + `/qualifications/${target.qualification_id}`;
  const previewEndpoint = endpoint.replace(':5387/', ':5386/');
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}`
  );
  const form = page.locator('[data-pending-qualification-form]');
  await expect(form).toBeVisible();
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="note"]')
    .fill('SYNTHETIC unfinished answer');
  await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
  const saved = page.waitForResponse(
    response =>
      response.url() === previewEndpoint + '/draft' &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  const response = await saved;
  expect(response.status()).toBe(200);
  expect(response.headers()['cache-control']).toContain('no-store');
  const body = await response.json();
  expect(body.item).toMatchObject({
    reason_code: 'order',
    outcome_code: '',
    notes: 'SYNTHETIC unfinished answer',
    completed_at: null,
    acw_limit_seconds: 60,
    overdue: true,
  });
  expect(Date.parse(body.item.started_at)).toBe(
    Date.parse(target.qualification_started_at)
  );
  expect(
    body.agent.pending_qualifications.some(
      record => record.id === target.qualification_id
    )
  ).toBe(true);
  expect(JSON.stringify(body.agent)).not.toContain(
    'SYNTHETIC unfinished answer'
  );
  await page.reload();
  await expect(form.locator('[data-qualification-field="note"]')).toHaveValue(
    'SYNTHETIC unfinished answer'
  );
  await expect(form.locator('[data-qualification-field="reason"]')).toHaveValue(
    'order'
  );
  await expect(page.locator('[data-acw-limit]')).toHaveText('60');
  await expect(page.locator('[data-qualification-clock]')).toHaveAttribute(
    'data-overdue',
    'true'
  );
  const before = Number(await page.locator('[data-acw-elapsed]').textContent());
  await expect
    .poll(async () =>
      Number(await page.locator('[data-acw-elapsed]').textContent())
    )
    .toBeGreaterThan(before);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  const color = await form
    .locator('[data-save-qualification-draft]')
    .evaluate(element => getComputedStyle(element).backgroundColor);
  expect(color).not.toBe('rgba(0, 0, 0, 0)');
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pending-acw-draft.png`,
    fullPage: true,
  });
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  const completed = page.waitForResponse(
    result =>
      result.url() === previewEndpoint && result.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  expect((await completed).status()).toBe(200);
  await expect(page.locator('[data-qualification-completed]')).toBeVisible();
  await page.reload();
  await expect(page.locator('[data-qualification-completed]')).toBeVisible();
  await expect(form).toHaveCount(0);
  const history = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect(history.status()).toBe(200);
  const rows = (await history.json()).items;
  expect(
    rows.filter(record => record.id === target.qualification_id)
  ).toHaveLength(1);
  expect(rows[0].completed_at).toBeTruthy();
  expect(rows[0].notes).toBe('SYNTHETIC unfinished answer');
  expect(
    nativeObservations
      .get(page)
      .filter(record => record.method !== 'GET')
      .map(record => record.pathname)
  ).toEqual([
    new URL(endpoint + '/draft').pathname,
    new URL(endpoint).pathname,
  ]);
});

test('pending ACW native review preserves local answers blocks stale writes and requires explicit reconciliation', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].acw_review;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + `/qualifications/${target.qualification_id}/draft`;
  const previewEndpoint = endpoint.replace(':5387/', ':5386/');
  const serverAnswer =
    'SYNTHETIC competing saved answer ' + 'wrapped-answer-'.repeat(30);
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}`
  );
  const form = page.locator('[data-pending-qualification-form]');
  await expect(form).toBeVisible();
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="note"]')
    .fill('SYNTHETIC local uncommitted answer');
  const read = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect(read.status()).toBe(200);
  const original = (await read.json()).items.find(
    record => record.id === target.qualification_id
  );
  const competing = await page.request.patch(endpoint, {
    headers: target.operator,
    data: {
      expected_draft_revision: original.draft_revision,
      qualification: {
        reason_code: 'order',
        notes: serverAnswer,
      },
    },
  });
  expect(competing.status()).toBe(200);
  const stale = await page.request.patch(endpoint, {
    headers: target.operator,
    data: {
      expected_draft_revision: original.draft_revision,
      qualification: { notes: 'SYNTHETIC stale request' },
    },
  });
  expect(stale.status()).toBe(409);
  const remote = page.locator('[data-qualification-remote-field="notes"]');
  // Observe the real five-second polling cycle plus its scoped Rails read.
  await expect(remote).toContainText(serverAnswer, { timeout: 10000 });
  await expect(
    page.locator('[data-qualification-remote-field="reason_code"] dd')
  ).toHaveText('Consulta de pedido');
  await expect(form.locator('[data-qualification-field="note"]')).toHaveValue(
    'SYNTHETIC local uncommitted answer'
  );
  await expect(form.locator('[data-save-qualification-draft]')).toBeDisabled();
  await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pending-acw-review.png`,
    fullPage: true,
  });
  await page.locator('[data-qualification-review="reapply"]').click();
  await expect(remote).toHaveCount(0);
  await expect(form.locator('[data-qualification-field="note"]')).toHaveValue(
    'SYNTHETIC local uncommitted answer'
  );
  const saved = page.waitForResponse(
    response =>
      response.url() === previewEndpoint &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  const savedResponse = await saved;
  expect(savedResponse.status()).toBe(200);
  const latest = (await savedResponse.json()).item;
  expect(latest.notes).toBe('SYNTHETIC local uncommitted answer');
  expect(latest.completed_at).toBeNull();
  const denied = await page.request.patch(endpoint, {
    headers: target.scoped,
    data: {
      expected_draft_revision: latest.draft_revision,
      qualification: { notes: 'SYNTHETIC other user overwrite' },
    },
  });
  expect(denied.status()).toBe(404);
  const foreign = session.pause_targets[info.project.name].acw_draft;
  const crossAccount = await page.request.patch(endpoint, {
    headers: foreign.operator,
    data: {
      expected_draft_revision: latest.draft_revision,
      qualification: { notes: 'SYNTHETIC foreign account' },
    },
  });
  expect(crossAccount.status()).toBe(401);
  await page.reload();
  await expect(form.locator('[data-qualification-field="note"]')).toHaveValue(
    'SYNTHETIC local uncommitted answer'
  );
  const unchanged = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect((await unchanged.json()).items[0].draft_revision).toBe(
    latest.draft_revision
  );
  expect(
    nativeObservations
      .get(page)
      .filter(record => record.method !== 'GET')
      .map(record => record.pathname)
  ).toEqual([new URL(endpoint).pathname]);
});

test('pending ACW native navigation reviews unsaved edits preserves saved state and leaves other modules untouched', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].acw_navigation;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const fixture = `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}`;
  const baseUrl = new RegExp(
    `/app/accounts/${target.account_id}/contact-center/control-desk$`
  );
  await page.goto(fixture);
  const form = page.locator('[data-pending-qualification-form]');
  const note = form.locator('[data-qualification-field="note"]');
  await expect(note).toBeVisible();
  await note.fill('SYNTHETIC unsaved navigation answer');
  await page.locator('[data-qualification-leave-link]').click();
  const review = page.getByRole('dialog', {
    name: 'Alterações do pós-atendimento não salvas',
    exact: true,
  });
  await expect(review).toBeVisible();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-pending-acw-navigation-review.png`,
    fullPage: true,
  });
  await review.getByRole('button', { name: 'Permanecer', exact: true }).click();
  await expect(review).not.toBeVisible();
  await expect(note).toHaveValue('SYNTHETIC unsaved navigation answer');
  await expect(page).toHaveURL(new RegExp(fixture + '$'));
  const browserPrompt = page.waitForEvent('dialog').then(async dialog => {
    expect(dialog.type()).toBe('beforeunload');
    await dialog.dismiss();
  });
  await Promise.all([
    browserPrompt,
    page.evaluate(() => window.location.reload()),
  ]);
  await expect(note).toHaveValue('SYNTHETIC unsaved navigation answer');
  expect(
    nativeObservations.get(page).filter(record => record.method !== 'GET')
  ).toEqual([]);
  await page.locator('[data-qualification-leave-link]').click();
  await review
    .getByRole('button', { name: 'Sair sem salvar', exact: true })
    .click();
  await expect(page).toHaveURL(baseUrl);
  const afterDiscard = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect(afterDiscard.status()).toBe(200);
  const pending = (await afterDiscard.json()).items.find(
    record => record.id === target.qualification_id
  );
  expect(pending.notes).toBeNull();
  expect(pending.completed_at).toBeNull();
  expect(Date.parse(pending.started_at)).toBe(
    Date.parse(target.qualification_started_at)
  );
  await page.goto(fixture);
  await expect(note).toHaveValue('');
  await note.fill('SYNTHETIC explicitly saved before navigation');
  const saved = page.waitForResponse(
    response =>
      response
        .url()
        .endsWith(`/qualifications/${target.qualification_id}/draft`) &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  expect((await saved).status()).toBe(200);
  await expect(form.locator('[data-save-qualification-draft]')).toBeDisabled();
  await page.locator('[data-qualification-leave-link]').click();
  await expect(page).toHaveURL(baseUrl);
  await page.goto(fixture);
  await expect(note).toHaveValue(
    'SYNTHETIC explicitly saved before navigation'
  );
  await expect(page.locator('[data-qualification-clock]')).toBeVisible();
  expect(
    nativeObservations.get(page).filter(record => record.method !== 'GET')
  ).toHaveLength(1);
});

test('scoped ACW native popup persists queue rules blocks conflicts and keeps scoped viewers denied', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].acw;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const ownBase = `/app/accounts/${target.account_id}/contact-center/control-desk`;
  const before = await page.request.get(ownApi + '/acw_policy', {
    headers: target.administrator,
  });
  expect(before.status()).toBe(200);
  expect((await before.json()).item.voice_rules).toEqual([]);
  await page.goto(ownBase + '/closures');
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await expect(
    dialog.getByRole('heading', {
      name: 'Configurar regras de pós-atendimento',
      exact: true,
    })
  ).toBeVisible();
  await expectContainedDialog(page);
  await dialog.locator('[data-add-acw-rule]').click();
  let row = dialog.locator('[data-acw-rule-row]').first();
  await expect(row.locator('[data-acw-rule-active]')).not.toBeChecked();
  await row.locator('[data-acw-rule-reason]').selectOption('order');
  await row.locator('[data-acw-rule-scope]').selectOption('queue');
  await row
    .locator('[data-acw-rule-target] select')
    .selectOption(String(target.queue_id));
  await row.locator('[data-acw-rule-time]').fill('00:02');
  await row.locator('[data-acw-rule-active]').check();
  const saved = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  const read = await page.request.get(ownApi + '/acw_policy', {
    headers: target.administrator,
  });
  const policy = (await read.json()).item;
  expect(policy.voice_rules).toHaveLength(1);
  expect(policy.voice_rules[0]).toMatchObject({
    reason_code: 'order',
    scope: 'queue',
    scope_id: String(target.queue_id),
    active: true,
    limit_seconds: 120,
  });
  await page.reload();
  await page.locator('[data-create]').click();
  row = dialog.locator('[data-acw-rule-row]').first();
  await expect(row.locator('[data-acw-rule-time]')).toHaveValue('00:02');
  await expect(row.locator('[data-acw-rule-reason]')).toHaveValue('order');
  await dialog.locator('[data-add-acw-rule]').click();
  const duplicate = dialog.locator('[data-acw-rule-row]').nth(1);
  await duplicate.locator('[data-acw-rule-reason]').selectOption('order');
  await duplicate.locator('[data-acw-rule-scope]').selectOption('queue');
  await duplicate
    .locator('[data-acw-rule-target] select')
    .selectOption(String(target.queue_id));
  await duplicate.locator('[data-acw-rule-time]').fill('00:03');
  await duplicate.locator('[data-acw-rule-active]').check();
  const rejected = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await rejected).status()).toBe(422);
  await expect(dialog.getByRole('alert')).toContainText(
    'Há regras de ACW conflitantes no mesmo nível.'
  );
  await expect(dialog.locator('[data-acw-rule-row]')).toHaveCount(2);
  const unchanged = await page.request.get(ownApi + '/acw_policy', {
    headers: target.administrator,
  });
  expect((await unchanged.json()).item).toEqual(policy);
  await duplicate.locator('[data-remove-acw-rule]').click();
  await row.locator('[data-acw-rule-time]').fill('00:03');
  await row.scrollIntoViewIfNeeded();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  const addRuleColor = await dialog
    .locator('[data-add-acw-rule]')
    .evaluate(element => getComputedStyle(element).color);
  const brightness = addRuleColor
    .match(/[\d.]+/g)
    .slice(0, 3)
    .map(Number)
    .reduce((sum, value) => sum + value, 0);
  if (info.project.name.endsWith('dark'))
    expect(brightness).toBeGreaterThan(600);
  else expect(brightness).toBeLessThan(300);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-acw-rule-theme.json`,
    JSON.stringify({ color: addRuleColor, brightness })
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-scoped-rules.png`,
    fullPage: true,
  });
  const edited = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await edited).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  const final = await page.request.get(ownApi + '/acw_policy', {
    headers: target.administrator,
  });
  const latest = (await final.json()).item;
  expect(latest.voice_rules[0].limit_seconds).toBe(180);
  const scoped = await page.request.get(ownApi + '/acw_policy', {
    headers: target.scoped,
  });
  expect(scoped.status()).toBe(200);
  expect((await scoped.json()).item.voice_rules).toBeUndefined();
  const denied = await page.request.patch(ownApi + '/acw_policy', {
    headers: target.scoped,
    data: {
      limits: latest.limits,
      expected_revision: latest.revision,
      voice_rules: [],
    },
  });
  expect(denied.status()).toBe(401);
  const audit = await page.request.get(
    ownApi +
      `/configuration_audits?resource_type=acw_policy&resource_id=${target.account_id}&history=true`,
    { headers: target.administrator }
  );
  expect(audit.status()).toBe(200);
  const history = (await audit.json()).items;
  expect(history).toHaveLength(2);
  expect(history[0].after.voice_rules[0].limit_seconds).toBe(180);
  expect(history[0].before.voice_rules[0].limit_seconds).toBe(120);
  const commands = await page.request.get(ownApi + '/commands', {
    headers: target.administrator,
  });
  expect(commands.status()).toBe(200);
  expect((await commands.json()).items).toEqual([]);
});

test('native local routing drafts persist paginate review conflicts and deny unauthorized targets', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].routing;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const ownBase = `/app/accounts/${target.account_id}/contact-center/control-desk/distribution`;
  const seedIds = [];
  for (let index = 0; index < 22; index += 1) {
    const created = await page.request.post(ownApi + '/routing_rules', {
      headers: target.administrator,
      data: {
        routing_rule: {
          version: 1,
          rule_key: `SYNTHETIC seeded routing ${String(index).padStart(2, '0')}`,
          kind: 'ddd',
          source_value: '11',
          priority: 1,
          state: 'draft',
          target_unit_id: index === 21 ? target.denied_unit_id : target.unit_id,
        },
      },
    });
    expect(created.status()).toBe(201);
    seedIds.push((await created.json()).item.id);
  }
  await page.goto(
    ownBase +
      '?audit_config_page=55&audit_config_operation=destroy&unrelated=preserved'
  );
  await expect(page.locator('[data-routing-workspace]')).toBeVisible();
  await expect(page.locator('[data-routing-row]')).toHaveCount(20);
  await expect(page.locator('[data-routing-total]')).toContainText('22');
  await page.locator('[data-routing-next]').click();
  await expect(page.locator('[data-routing-row]')).toHaveCount(2);
  await expect(page).toHaveURL(/routing_page=2/);
  await page.reload();
  await expect(page.locator('[data-routing-row]')).toHaveCount(2);
  await page.locator('[data-routing-create]').click();
  const dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  const key = `SYNTHETIC edited routing ${info.project.name}`;
  await dialog.locator('[data-routing-key]').fill(key);
  await dialog.locator('[data-routing-source]').fill('11');
  await dialog.locator('#routing-unit').selectOption(String(target.unit_id));
  await dialog.locator('#routing-queue').selectOption(String(target.queue_id));
  const created = page.waitForResponse(
    response =>
      response.url().endsWith('/routing_rules') &&
      response.request().method() === 'POST'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  const createdResponse = await created;
  expect(createdResponse.status()).toBe(201);
  const record = (await createdResponse.json()).item;
  await expect(dialog).not.toBeVisible();
  await page.locator('[data-routing-search]').fill(key);
  await page.locator('[data-routing-filter-kind]').selectOption('ddd');
  await page
    .locator('[data-routing-workspace] form')
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  await expect(page.locator('[data-routing-row]')).toHaveCount(1);
  await page.locator('[data-routing-open]').click();
  await expect(dialog.locator('[data-routing-source]')).toHaveValue('11');
  await dialog.locator('[data-routing-source]').fill('21');
  const edited = page.waitForResponse(
    response =>
      response.url().endsWith(`/routing_rules/${record.id}`) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await edited).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  await page.reload();
  await expect(page.locator('[data-routing-row]')).toContainText('21');
  await page.locator('[data-routing-open]').click();
  const before = await page.request.get(
    `${ownApi}/routing_rules/${record.id}`,
    { headers: target.administrator }
  );
  expect(before.status()).toBe(200);
  const concurrent = await page.request.patch(
    `${ownApi}/routing_rules/${record.id}`,
    {
      headers: target.administrator,
      data: {
        routing_rule: { priority: 2 },
        expected_revision: (await before.json()).item.revision,
      },
    }
  );
  expect(concurrent.status()).toBe(200);
  await dialog.locator('[data-routing-source]').fill('31');
  const stale = page.waitForResponse(
    response =>
      response.url().endsWith(`/routing_rules/${record.id}`) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await stale).status()).toBe(409);
  await expect(dialog.locator('[data-configuration-conflict]')).toBeVisible();
  await expect(dialog.locator('[data-routing-source]')).toHaveValue('31');
  await expect(
    dialog.getByRole('button', { name: 'Salvar', exact: true })
  ).toBeDisabled();
  await dialog
    .getByRole('button', {
      name: 'Carregar versão atual para comparar',
      exact: true,
    })
    .click();
  await expect(dialog.locator('[data-configuration-latest]')).toBeVisible();
  await dialog.locator('[data-configuration-review]').check();
  const reviewed = page.waitForResponse(
    response =>
      response.url().endsWith(`/routing_rules/${record.id}`) &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await reviewed).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  await page.locator('[data-routing-open]').click();
  await expect(dialog.locator('[data-routing-source]')).toHaveValue('31');
  const unitDetail = await page.request.get(
    `${ownApi}/units/${target.unit_id}`,
    { headers: target.administrator }
  );
  const queueDetail = await page.request.get(
    `${ownApi}/queues/${target.queue_id}`,
    { headers: target.administrator }
  );
  expect(unitDetail.status()).toBe(200);
  expect(queueDetail.status()).toBe(200);
  const currentUnit = (await unitDetail.json()).item;
  const currentQueue = (await queueDetail.json()).item;
  expect(String(currentUnit.id)).toBe(String(target.unit_id));
  expect(String(currentQueue.id)).toBe(String(target.queue_id));
  await expect(dialog.locator('#routing-unit')).toBeEnabled();
  await expect(dialog.locator('#routing-queue')).toBeEnabled();
  await expect(dialog.locator('#routing-unit option:checked')).toContainText(
    currentUnit.name
  );
  await expect(dialog.locator('#routing-queue option:checked')).toContainText(
    currentQueue.name
  );
  await expect(
    dialog.getByRole('combobox', {
      name: 'Critério de roteamento',
      exact: true,
    })
  ).toBeVisible();
  await expect(
    dialog.getByRole('combobox', {
      name: 'Critério de roteamento',
      exact: true,
    })
  ).toHaveValue('ddd');
  await expect(
    dialog.getByText('Tipo de unidade', { exact: true })
  ).toHaveCount(0);
  await expect(dialog.getByText('Versão', { exact: true })).toBeVisible();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  const color = await dialog
    .locator('[data-routing-key]')
    .evaluate(element => getComputedStyle(element).color);
  const brightness = color
    .match(/[\d.]+/g)
    .slice(0, 3)
    .map(Number)
    .reduce((sum, item) => sum + item, 0);
  if (info.project.name.endsWith('dark'))
    expect(brightness).toBeGreaterThan(600);
  else expect(brightness).toBeLessThan(300);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-routing-theme.json`,
    JSON.stringify({ color, brightness })
  );
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-routing-draft.png`,
    fullPage: false,
  });
  await dialog.locator('#routing-queue').scrollIntoViewIfNeeded();
  await expect(dialog.locator('#routing-queue option:checked')).toContainText(
    currentQueue.name
  );
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-routing-targets.png`,
    fullPage: false,
  });
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  await page.locator('[data-routing-clear]').click();
  await expect(page.locator('[data-routing-total]')).toContainText('23');
  const scoped = await page.request.get(ownApi + '/routing_rules?page=1', {
    headers: target.scoped,
  });
  expect(scoped.status()).toBe(200);
  expect((await scoped.json()).meta.total).toBe(22);
  const outside = await page.request.get(
    `${ownApi}/routing_rules/${seedIds[21]}`,
    { headers: target.scoped }
  );
  expect(outside.status()).toBe(404);
  const denied = await page.request.post(ownApi + '/routing_rules', {
    headers: target.scoped,
    data: {
      routing_rule: {
        version: 1,
        rule_key: 'SYNTHETIC denied scope',
        kind: 'ddd',
        priority: 1,
        target_unit_id: target.denied_unit_id,
        state: 'draft',
      },
    },
  });
  expect(denied.status()).toBe(404);
  const operator = await page.request.post(ownApi + '/routing_rules', {
    headers: target.operator,
    data: {
      routing_rule: {
        version: 1,
        rule_key: 'SYNTHETIC denied operator',
        kind: 'ddd',
        priority: 1,
        target_unit_id: target.unit_id,
        state: 'draft',
      },
    },
  });
  expect(operator.status()).toBe(401);
  const history = await page.request.get(
    `${ownApi}/configuration_audits?resource_type=routing_rule&resource_id=${record.id}&history=true`,
    { headers: target.administrator }
  );
  expect(history.status()).toBe(200);
  expect((await history.json()).items).toHaveLength(4);
  const commands = await page.request.get(ownApi + '/commands', {
    headers: target.administrator,
  });
  expect(commands.status()).toBe(200);
  expect((await commands.json()).items).toEqual([]);
  await expect(page.locator('[data-publish]')).toHaveCount(0);
  const auditNavigation = page.waitForResponse(response => {
    const address = new URL(response.url());
    return (
      address.pathname.endsWith('/configuration_audits') &&
      address.searchParams.get('resource_id') === String(record.id)
    );
  });
  await page
    .locator(`[data-routing-row="${record.id}"] [data-routing-history]`)
    .click();
  expect((await auditNavigation).status()).toBe(200);
  await expect(page.locator('[data-audit-row]')).toHaveCount(4);
  await page.locator('[data-audit-detail]').first().click();
  await expect(
    page
      .getByRole('dialog')
      .getByRole('heading', { name: 'Critério de roteamento', exact: true })
  ).toHaveCount(1);
  const auditSource = page
    .getByRole('dialog')
    .getByRole('heading', { name: 'Origem de roteamento', exact: true });
  await expect(auditSource.locator('..')).toContainText('31');
  await auditSource.scrollIntoViewIfNeeded();
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-routing-audit.png`,
    fullPage: false,
  });
});

test('whole native team deletion preserves generic confirmation requires scoped manager review and records real audit', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].team_deletion;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}`;
  await page.goto(
    `/app/accounts/${target.account_id}/settings/teams/list?native_navigation=1`
  );
  const remove = page.locator(`[data-team-delete="${target.team_id}"]`);
  await expect(remove).toBeVisible();
  await remove.click();
  const generic = page
    .locator('form')
    .filter({ has: page.locator('input[type="text"]') });
  await expect(generic).toBeVisible();
  const genericBox = await generic.boundingBox();
  const viewport = page.viewportSize();
  expect(genericBox.x).toBeGreaterThanOrEqual(0);
  expect(genericBox.x + genericBox.width).toBeLessThanOrEqual(viewport.width);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-whole-team-native-name-confirmation.png`,
    fullPage: true,
  });
  await expect(generic.locator('button[type="submit"]')).toBeDisabled();
  await generic.locator('input[type="text"]').fill(target.team_name);
  const requested = page.waitForResponse(
    response =>
      response.url().endsWith(`/teams/${target.team_id}`) &&
      response.request().method() === 'DELETE'
  );
  await generic.locator('button[type="submit"]').click();
  expect((await requested).status()).toBe(409);
  const review = page.locator('[data-team-roster-withdrawal-review]');
  await expect(review).toBeVisible();
  await expect(review).toContainText(target.team_name);
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await expect(review.locator('[data-apply-team-withdrawal]')).toBeDisabled();
  const stillPresent = await page.request.get(
    `${ownApi}/teams/${target.team_id}`,
    { headers: target.administrator }
  );
  expect(stillPresent.status()).toBe(200);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-whole-team-deletion-review.png`,
    fullPage: true,
  });
  await review.locator('[data-team-manager-withdrawal-confirm]').check();
  const deleted = page.waitForResponse(
    response =>
      response.url().endsWith(`/teams/${target.team_id}`) &&
      response.request().method() === 'DELETE'
  );
  await review.locator('[data-apply-team-withdrawal]').click();
  expect((await deleted).status()).toBe(200);
  await expect(review).not.toBeVisible();
  await expect(remove).not.toBeVisible();
  await page.reload();
  await expect(remove).not.toBeVisible();
  const missing = await page.request.get(`${ownApi}/teams/${target.team_id}`, {
    headers: target.administrator,
  });
  expect(missing.status()).toBe(404);
  const history = await page.request.get(
    `${ownApi}/jrc_contact_center/configuration_audits?resource_type=queue&resource_id=${target.queue_id}&history=true`,
    { headers: target.administrator }
  );
  expect(history.status()).toBe(200);
  const event = (await history.json()).items.find(
    row => row.manager_review?.kind === 'jrc_cc_team_deletion_v1'
  );
  expect(event.manager_review.team_id).toBe(String(target.team_id));
  expect(event.manager_review.previous_count).toBe(1);
  expect(event.manager_review.remaining_count).toBe(0);
  expect(JSON.stringify(event)).not.toContain('review_token');
  const deny = await page.request.delete(`${ownApi}/teams/${target.team_id}`, {
    headers: session.administrator,
  });
  expect([401, 403, 404]).toContain(deny.status());
  expect(
    nativeObservations
      .get(page)
      .filter(
        row =>
          row.method === 'DELETE' &&
          row.pathname.endsWith(`/teams/${target.team_id}`)
      )
  ).toHaveLength(2);
});

test('ACW form library persists native schema revisions and preserves immutable history without operational activation', async ({
  page,
}, info) => {
  const target = session.acw_form_targets[info.project.name];
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/acw_forms`;
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/closures`
  );
  const browserEndpoint = new URL(new URL(endpoint).pathname, page.url()).href;
  await page.locator('[data-manage-acw-forms]').click();
  const library = page.locator('[data-acw-form-library]');
  await expect(library).toBeVisible();
  await expectContainedDialog(page);
  await page.locator('[data-acw-form-new]').click();
  await page
    .locator('[data-acw-form-name]')
    .fill(`SYNTHETIC created ${info.project.name}`);
  await expect(page.locator('[data-acw-form-save]')).toBeDisabled();
  await page.locator('[data-add-acw-form-field]').click();
  await page
    .locator('[data-acw-schema-label]')
    .fill('SYNTHETIC required feedback');
  await page.locator('[data-acw-schema-required]').check();
  const created = page.waitForResponse(
    response =>
      response.url() === browserEndpoint &&
      response.request().method() === 'POST'
  );
  await page.locator('[data-acw-form-save]').click();
  const saved = await created;
  expect(saved.status()).toBe(201);
  const first = (await saved.json()).item;
  expect(first.revision).toBe(1);
  expect(first.provider_applied).toBe(false);
  await expect(page.locator('[data-acw-form-saved]')).toBeVisible();
  await page
    .locator('[data-acw-form-name]')
    .fill(`SYNTHETIC revised ${info.project.name}`);
  const updated = page.waitForResponse(
    response =>
      response.url() === `${browserEndpoint}/${first.id}` &&
      response.request().method() === 'PATCH'
  );
  await page.locator('[data-acw-form-save]').click();
  expect((await updated).status()).toBe(200);
  await expect(page.locator('[data-acw-form-saved]')).toBeVisible();
  await page.locator('[data-acw-form-preview]').click();
  await page
    .locator(`[data-acw-answer="${first.definition.fields[0].key}"]`)
    .fill('SYNTHETIC preview only');
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-form-preview.png`,
    fullPage: true,
  });
  const persisted = await page.request.get(`${endpoint}/${first.id}`, {
    headers: target.administrator,
  });
  expect(persisted.status()).toBe(200);
  expect((await persisted.json()).item).toMatchObject({
    name: `SYNTHETIC revised ${info.project.name}`,
    revision: 2,
  });
  expect(JSON.stringify(await persisted.json())).not.toContain(
    'SYNTHETIC preview only'
  );
  await page.locator('[data-acw-form-history]').click();
  await expect(library).toContainText(`SYNTHETIC created ${info.project.name}`);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-form-history.png`,
    fullPage: true,
  });
  const original = await page.request.get(
    `${endpoint}/${first.id}/versions/1`,
    { headers: target.administrator }
  );
  expect(original.status()).toBe(200);
  expect((await original.json()).item.name).toBe(
    `SYNTHETIC created ${info.project.name}`
  );
  const audits = await page.request.get(
    endpoint.replace('/acw_forms', '/configuration_audits') +
      `?resource_type=acw_form_revision&resource_id=${first.version_id}`,
    { headers: target.administrator }
  );
  expect(audits.status()).toBe(200);
  const evidence = await audits.json();
  expect(evidence.items.length).toBeGreaterThan(0);
  expect(JSON.stringify(evidence)).not.toContain('SYNTHETIC required feedback');
  const denied = await page.request.get(`${endpoint}/${first.id}`, {
    headers: target.scoped,
  });
  expect([401, 403, 404]).toContain(denied.status());
});

test('ACW form library native pagination filters clearing reload and account denials stay scoped', async ({
  page,
}, info) => {
  const target = session.acw_form_targets[info.project.name];
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/acw_forms`;
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/closures`
  );
  await page.locator('[data-manage-acw-forms]').click();
  const browserEndpoint = new URL(new URL(endpoint).pathname, page.url()).href;
  const library = page.locator('[data-acw-form-library]');
  await page.locator('[data-acw-form-search]').fill('SYNTHETIC page');
  const filtered = page.waitForResponse(
    response =>
      response.url().includes('/acw_forms?') &&
      new URL(response.url()).searchParams.get('q') === 'SYNTHETIC page'
  );
  await library
    .getByRole('button', { name: 'Aplicar filtros', exact: true })
    .click();
  expect((await filtered).status()).toBe(200);
  await expect(library.locator('[data-acw-form-row]')).toHaveCount(20);
  await library.getByRole('button', { name: 'Próxima', exact: true }).click();
  await expect(library.locator('[data-acw-form-row]')).toHaveCount(1);
  await expect(library).toContainText('Página 2 de 2');
  await library.getByRole('button', { name: 'Anterior', exact: true }).click();
  await expect(library.locator('[data-acw-form-row]')).toHaveCount(20);
  const cleared = page.waitForResponse(
    response =>
      new URL(response.url()).origin + new URL(response.url()).pathname ===
        browserEndpoint &&
      response.request().method() === 'GET' &&
      new URL(response.url()).searchParams.get('q') === '' &&
      new URL(response.url()).searchParams.get('status') === ''
  );
  await library
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  expect((await cleared).status()).toBe(200);
  await expect(page.locator('[data-acw-form-search]')).toHaveValue('');
  await expect(page.locator('[data-acw-form-status]')).toHaveValue('');
  await expect(library.locator('[data-acw-form-row]')).toHaveCount(20);
  await expect(
    library.getByText('Carregando Contact Center...', { exact: true })
  ).toHaveCount(0);
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-acw-form-library.png`,
    fullPage: true,
  });
  const foreign = await page.request.get(endpoint, {
    headers: session.administrator,
  });
  expect([401, 403, 404]).toContain(foreign.status());
  const observer = await page.request.get(endpoint, {
    headers: target.observer,
  });
  expect([401, 403, 404]).toContain(observer.status());
  await page.reload();
  await expect(page.locator('[data-acw-form-library]')).not.toBeVisible();
  await page.locator('[data-manage-acw-forms]').click();
  await expect(page.locator('[data-acw-form-row]')).toHaveCount(20);
});

test('deferred pause native waits through ACW and starts only after explicit completion without administrative access', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].deferred_pause;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}?with_pause=1`
  );
  const widget = page.locator('[data-native-deferred-pause]');
  const form = page.locator('[data-pending-qualification-form]');
  await expect(widget).toBeVisible();
  await expect(form).toBeVisible();
  const browserApi = new URL(new URL(ownApi).pathname, page.url()).href;
  const denied = await page.request.get(ownApi + '/acw_forms', {
    headers: target.operator,
  });
  expect([401, 403, 404]).toContain(denied.status());
  await widget.locator('select').first().selectOption(String(target.queue_id));
  await widget.locator('select').nth(1).selectOption('lunch');
  await widget
    .getByRole('button', { name: 'Solicitar pausa após ACW', exact: true })
    .click();
  await expect(page.locator('[data-deferred-pause-dialog]')).toBeVisible();
  await expectContainedDialog(page);
  const submitted = page.waitForResponse(
    response =>
      response.url() === browserApi + '/deferred_pause_request' &&
      response.request().method() === 'POST'
  );
  await page.locator('[data-deferred-pause-confirm]').click();
  const accepted = await submitted;
  expect(accepted.status()).toBe(200);
  const first = await accepted.json();
  expect(first.receipt.state).toBe('pending');
  expect(first.item.state).toBe('acw');
  expect(first.item.provider_confirmed).toBe(false);
  const supervision = await page.request.get(ownApi + '/supervisor', {
    headers: target.administrator,
  });
  expect(supervision.status()).toBe(200);
  const supervised = (await supervision.json()).agents.find(
    agent => agent.account_user_id === String(target.operator_id)
  );
  expect(supervised.deferred_pause_notice).toEqual({ state: 'pending' });
  expect(JSON.stringify(supervised)).not.toContain(first.receipt.request_id);
  await expect(widget.locator('[data-deferred-pause-pending]')).toBeVisible();
  await page.reload();
  await expect(widget.locator('[data-deferred-pause-pending]')).toBeVisible();
  const ownState = await page.request.get(ownApi + '/agent_state', {
    headers: target.operator,
  });
  expect(ownState.status()).toBe(200);
  expect((await ownState.json()).item.deferred_pause_request.request_id).toBe(
    first.receipt.request_id
  );
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="note"]')
    .fill('SYNTHETIC deferred pause private draft');
  const saved = page.waitForResponse(
    response =>
      response.url() ===
        browserApi + `/qualifications/${target.qualification_id}/draft` &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  const savedResponse = await saved;
  expect(savedResponse.status()).toBe(200);
  expect((await savedResponse.json()).item).toMatchObject({
    completed_at: null,
    notes: 'SYNTHETIC deferred pause private draft',
    overdue: true,
  });
  await expect(widget.locator('[role="timer"]')).toHaveCount(0);
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  const completed = page.waitForResponse(
    response =>
      response.url() ===
        browserApi + `/qualifications/${target.qualification_id}` &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  expect((await completed).status()).toBe(200);
  await expect(page.locator('[data-qualification-completed]')).toBeVisible();
  await expect(widget.locator('[role="timer"]')).toBeVisible({
    timeout: 15000,
  });
  await expect(widget).toHaveAttribute('data-agent-state', 'paused');
  await expect(widget.locator('[data-deferred-pause-pending]')).toHaveCount(0);
  const paused = await page.request.get(ownApi + '/agent_state', {
    headers: target.operator,
  });
  expect(paused.status()).toBe(200);
  expect((await paused.json()).item).toMatchObject({
    state: 'paused',
    reason_code: 'lunch',
    eligible: false,
    provider_confirmed: false,
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-deferred-pause-applied.png`,
    fullPage: true,
  });
  await page.reload();
  await expect(widget.locator('[role="timer"]')).toBeVisible();
});

test('deferred pause native uncertain response reuses one durable receipt and explicit cancellation preserves ACW', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].deferred_pause_retry;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}?with_pause=1`
  );
  const widget = page.locator('[data-native-deferred-pause]');
  const form = page.locator('[data-pending-qualification-form]');
  await expect(widget).toBeVisible();
  const browserApi = new URL(new URL(ownApi).pathname, page.url()).href;
  const bodies = [];
  let firstReceipt;
  await page.route(browserApi + '/deferred_pause_request', async route => {
    if (route.request().method() !== 'POST') {
      await route.continue();
      return;
    }
    bodies.push(route.request().postDataJSON());
    if (bodies.length === 1) {
      const response = await route.fetch();
      expect(response.status()).toBe(200);
      firstReceipt = (await response.json()).receipt;
      // The native request and PostgreSQL commit actually happen; only its browser reply is lost.
      await route.abort('failed');
    } else await route.continue();
  });
  await widget.locator('select').first().selectOption(String(target.queue_id));
  await widget.locator('select').nth(1).selectOption('lunch');
  await widget
    .getByRole('button', { name: 'Solicitar pausa após ACW', exact: true })
    .click();
  await page.locator('[data-deferred-pause-confirm]').click();
  await expect(page.locator('[data-deferred-pause-uncertain]')).toBeVisible();
  expect(bodies).toHaveLength(1);
  const stored = await page.request.get(ownApi + '/agent_state', {
    headers: target.operator,
  });
  expect(stored.status()).toBe(200);
  expect((await stored.json()).item.deferred_pause_request.request_id).toBe(
    firstReceipt.request_id
  );
  await expectContainedDialog(page);
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-deferred-pause-uncertain.png`,
    fullPage: true,
  });
  const retried = page.waitForResponse(
    response =>
      response.url() === browserApi + '/deferred_pause_request' &&
      response.request().method() === 'POST'
  );
  await page.locator('[data-deferred-pause-confirm]').click();
  const replay = await retried;
  expect(replay.status()).toBe(200);
  expect((await replay.json()).receipt.request_id).toBe(
    firstReceipt.request_id
  );
  expect(bodies).toHaveLength(2);
  expect(bodies[1]).toEqual(bodies[0]);
  await expect(widget.locator('[data-deferred-pause-pending]')).toBeVisible();
  await widget.locator('[data-deferred-pause-cancel]').click();
  await expect(page.locator('[data-deferred-pause-dialog]')).toBeVisible();
  const cancelled = page.waitForResponse(
    response =>
      response.url() === browserApi + '/deferred_pause_request' &&
      response.request().method() === 'DELETE'
  );
  await page.locator('[data-deferred-pause-confirm]').click();
  const cancellation = await cancelled;
  expect(cancellation.status()).toBe(200);
  expect((await cancellation.json()).receipt).toMatchObject({
    request_id: firstReceipt.request_id,
    state: 'cancelled',
  });
  await expect(widget.locator('[data-deferred-pause-pending]')).toHaveCount(0);
  await expect(form).toBeVisible();
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  await form
    .locator('[data-qualification-field="note"]')
    .fill('SYNTHETIC completed after withdrawal');
  const completed = page.waitForResponse(
    response =>
      response.url() ===
        browserApi + `/qualifications/${target.qualification_id}` &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  expect((await completed).status()).toBe(200);
  await expect(page.locator('[data-qualification-completed]')).toBeVisible();
  await expect
    .poll(async () => {
      const response = await page.request.get(ownApi + '/agent_state', {
        headers: target.operator,
      });
      expect(response.status()).toBe(200);
      return (await response.json()).item.state;
    })
    .toBe('available');
  await expect(widget).toHaveAttribute('data-agent-state', 'available', {
    timeout: 15000,
  });
  await expect(widget.locator('[role="timer"]')).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page
      .locator('html')
      .evaluate(element => element.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-deferred-pause-withdrawn.png`,
    fullPage: true,
  });
});

test('operational form native preserves typed private drafts and blocks pause until required explicit completion', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].operational_forms;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + `/qualifications/${target.qualification_id}`;
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-pending-acw/${target.call_session_id}?with_pause=1`
  );
  const form = page.locator('[data-pending-qualification-form]');
  await expect(form).toBeVisible();
  await expect(form.locator('[data-qualification-draft-saved]')).toHaveCount(0);
  const browserApi = new URL(new URL(ownApi).pathname, page.url()).href;
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  const fields = form.locator('[data-acw-form-fields]');
  await expect(fields).toBeVisible();
  await expect(fields.locator('[data-acw-answer]')).toHaveCount(3);
  await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
  const denied = await page.request.get(ownApi + '/acw_forms', {
    headers: target.operator,
  });
  expect([401, 403, 404]).toContain(denied.status());
  const incomplete = await page.request.patch(endpoint, {
    headers: target.operator,
    data: {
      qualification: { reason_code: 'order', outcome_code: 'completed' },
    },
  });
  expect(incomplete.status()).toBe(422);
  const widget = page.locator('[data-native-deferred-pause]');
  await widget.locator('select').first().selectOption(String(target.queue_id));
  await widget.locator('select').nth(1).selectOption('lunch');
  await widget
    .getByRole('button', { name: 'Solicitar pausa após ACW', exact: true })
    .click();
  await expectContainedDialog(page);
  await page.locator('[data-deferred-pause-confirm]').click();
  await expect(widget.locator('[data-deferred-pause-pending]')).toBeVisible();
  await fields
    .locator('[data-acw-answer="feedback"]')
    .fill('SYNTHETIC browser private response');
  await fields.locator('[data-acw-answer="verified"]').selectOption('false');
  await fields.locator('[data-acw-answer="quantity"]').fill('0');
  const saved = page.waitForResponse(
    response =>
      response.url() ===
        browserApi + `/qualifications/${target.qualification_id}/draft` &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  const savedResponse = await saved;
  expect(savedResponse.status()).toBe(200);
  const savedBody = await savedResponse.json();
  expect(savedBody.item.completed_at).toBeNull();
  expect(savedBody.item.acw_form_context.answers[target.form_rule_id]).toEqual({
    feedback: 'SYNTHETIC browser private response',
    verified: false,
    quantity: 0,
  });
  expect(JSON.stringify(savedBody.agent)).not.toContain(
    'SYNTHETIC browser private response'
  );
  await expect(widget.locator('[role="timer"]')).toHaveCount(0);
  await page.reload();
  await expect(fields.locator('[data-acw-answer="feedback"]')).toHaveValue(
    'SYNTHETIC browser private response'
  );
  await expect(fields.locator('[data-acw-answer="verified"]')).toHaveValue(
    'false'
  );
  await expect(fields.locator('[data-acw-answer="quantity"]')).toHaveValue('0');
  await expect(form.locator('[data-qualification-draft-saved]')).toBeVisible();
  await expect(page.locator('[data-acw-limit]')).toHaveText('60');
  await expect(widget.locator('[data-deferred-pause-pending]')).toBeVisible();
  await expect(form.locator('[data-complete-qualification]')).toBeEnabled();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  const background = await fields
    .locator('textarea')
    .evaluate(el => getComputedStyle(el).backgroundColor);
  expect(background).not.toBe('rgba(0, 0, 0, 0)');
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-operational-form-draft.png`,
    fullPage: true,
  });
  const completed = page.waitForResponse(
    response =>
      response.url() ===
        browserApi + `/qualifications/${target.qualification_id}` &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  expect((await completed).status()).toBe(200);
  await expect(page.locator('[data-qualification-completed]')).toBeVisible();
  await expect(widget).toHaveAttribute('data-agent-state', 'paused', {
    timeout: 15000,
  });
  const state = await page.request.get(ownApi + '/agent_state', {
    headers: target.operator,
  });
  expect((await state.json()).item).toMatchObject({
    state: 'paused',
    provider_confirmed: false,
  });
  const lateDraft = await page.request.patch(endpoint + '/draft', {
    headers: target.operator,
    data: {
      expected_draft_revision: savedBody.item.draft_revision,
      qualification: { reason_code: 'order', notes: 'must not overwrite' },
    },
  });
  expect(lateDraft.status()).toBe(409);
  const recovered = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect(
    (await recovered.json()).items[0].acw_form_context.answers[
      target.form_rule_id
    ]
  ).toEqual(savedBody.item.acw_form_context.answers[target.form_rule_id]);
});

test('form bindings native persists exact latest version while existing attendance retains its original form and clock', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].form_bindings;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/closures`
  );
  await page.locator('[data-create]').click();
  let dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  let row = dialog.locator('[data-acw-rule-row]').first();
  await expect(row.locator('[data-acw-rule-time]')).toHaveValue('00:01');
  await expect(row.locator('[data-remove-acw-rule]')).toBeDisabled();
  await row.locator('[data-pick-rule-form]').click();
  const libraryRow = page
    .locator('[data-acw-form-row]')
    .filter({ hasText: 'SYNTHETIC operational version 2' });
  await expect(libraryRow).toBeVisible();
  await libraryRow.locator('[data-acw-form-select]').click();
  await expect(
    row.locator('[data-required-form-field="new_note"]')
  ).toBeVisible();
  await row.locator('[data-required-form-field="feedback"]').check();
  await row.locator('[data-required-form-field="new_note"]').check();
  await expect(
    row.locator('[data-required-form-field="verified"]')
  ).toBeChecked();
  await expect(
    row.locator('[data-required-form-field="verified"]')
  ).toBeDisabled();
  await row.locator('[data-acw-rule-time]').fill('00:02');
  const saved = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(200);
  await expect(dialog).not.toBeVisible();
  const configured = await page.request.get(ownApi + '/acw_policy', {
    headers: target.administrator,
  });
  expect(configured.status()).toBe(200);
  const policy = (await configured.json()).item;
  expect(policy.voice_rules[0].limit_seconds).toBe(120);
  expect(policy.voice_form_bindings[0]).toMatchObject({
    rule_id: target.form_rule_id,
    form_id: target.form_id,
    revision: 2,
    required_fields: ['feedback', 'new_note', 'quantity', 'verified'],
  });
  const ownContext = await page.request.get(
    ownApi +
      `/qualifications/${target.qualification_id}/form_context?reason_code=order`,
    { headers: target.operator }
  );
  expect(ownContext.status()).toBe(200);
  const captured = (await ownContext.json()).item;
  expect(captured.acw_form_context.selected.revision).toBe(1);
  expect(captured.acw_form_context.selected.definition.fields).toHaveLength(3);
  const capturedList = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  expect(capturedList.status()).toBe(200);
  const originalAttendance = (await capturedList.json()).items[0];
  expect(originalAttendance.acw_limit_seconds).toBe(180);
  const classifiedDraft = await page.request.patch(
    ownApi + `/qualifications/${target.qualification_id}/draft`,
    {
      headers: target.operator,
      data: {
        expected_draft_revision: originalAttendance.draft_revision,
        qualification: { reason_code: 'order' },
      },
    }
  );
  expect(classifiedDraft.status()).toBe(200);
  expect((await classifiedDraft.json()).item).toMatchObject({
    completed_at: null,
    acw_limit_seconds: 60,
  });
  const catalogueDenied = await page.request.get(ownApi + '/acw_forms', {
    headers: target.operator,
  });
  expect([401, 403, 404]).toContain(catalogueDenied.status());
  const originalDenied = await page.request.get(
    ownApi +
      `/qualifications/${target.qualification_id}/form_context?reason_code=order`,
    { headers: target.administrator }
  );
  expect(originalDenied.status()).toBe(404);
  await page.reload();
  await page.locator('[data-create]').click();
  dialog = page.getByRole('dialog');
  row = dialog.locator('[data-acw-rule-row]').first();
  await expect(row.locator('[data-acw-rule-time]')).toHaveValue('00:02');
  await row.locator('[data-review-rule-form]').click();
  await expect(
    row.locator('[data-required-form-field="new_note"]')
  ).toBeChecked();
  await expect(
    row.locator('[data-required-form-field="feedback"]')
  ).toBeChecked();
  await row.scrollIntoViewIfNeeded();
  await expectContainedDialog(page);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-operational-form-binding.png`,
    fullPage: true,
  });
});

test('state history native preserves scope, filters, pagination and private event data without writes', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].state_history;
  const endpoint = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center/agent_state_histories`;
  const location = `/app/accounts/${target.account_id}/contact-center/control-desk/pauses`;
  const writes = [];
  page.on('request', request => {
    if (
      new URL(request.url()).pathname.includes('/jrc_contact_center/') &&
      !['GET', 'HEAD'].includes(request.method())
    )
      writes.push(request.method());
  });
  await page.goto(location);
  const opener = page.locator('[data-open-state-history]');
  await expect(opener).toBeVisible();
  await opener.click();
  await expectContainedDialog(page);
  const dialog = page.getByRole('dialog');
  await expect(dialog.locator('[data-history-row]')).toHaveCount(20);
  await expect(dialog).toContainText('Total 27');
  await expect(dialog).not.toContainText('SYNTHETIC_PRIVATE_HISTORY');
  await expect(dialog).toContainText(
    'Sem confirmação do provedor neste evento'
  );
  await dialog.locator('[data-history-next]').click();
  await expect(dialog.locator('[data-history-row]')).toHaveCount(7);
  const filters = dialog.locator('[data-history-filters]');
  await expect(filters).toHaveJSProperty('open', false);
  await filters.locator('summary').click();
  await dialog.locator('[data-history-filter="state"]').selectOption('paused');
  await dialog
    .locator('[data-history-filter="queue_id"]')
    .selectOption(String(target.queue_id));
  await dialog.locator('[data-history-apply]').click();
  await expect(dialog).toContainText('Total 25');
  await expect(dialog.locator('[data-history-row]')).toHaveCount(20);
  await dialog
    .locator('[data-history-filter="q"]')
    .fill('SYNTHETIC no matching agent');
  await dialog.locator('[data-history-apply]').click();
  await expect(dialog.locator('[data-history-empty]')).toBeVisible();
  await dialog.locator('[data-history-clear]').click();
  await expect(dialog).toContainText('Total 27');
  await expect(dialog.locator('[data-history-row]')).toHaveCount(20);
  await expect(page.locator('html')).toHaveClass(
    info.project.name.endsWith('dark') ? /dark/ : /^(?!.*\bdark\b).*$/
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await filters.locator('summary').click();
  await expect(filters).toHaveJSProperty('open', false);
  await dialog.locator('[data-history-row]').first().scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-state-history.png`,
    fullPage: false,
  });
  const direct = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(direct.status()).toBe(200);
  expect(direct.headers()['cache-control']).toContain('no-store');
  expect((await direct.json()).meta.total).toBe(27);
  expect(await direct.text()).not.toContain('SYNTHETIC_PRIVATE_HISTORY');
  const scoped = await page.request.get(endpoint, { headers: target.scoped });
  expect(scoped.status()).toBe(200);
  expect((await scoped.json()).meta.total).toBe(25);
  expect(
    (await scoped.json()).items.every(row =>
      target.history_visible_ids.includes(row.id)
    )
  ).toBe(true);
  const denied = await page.request.get(
    endpoint + `?queue_id=${target.denied_queue_id}`,
    { headers: target.scoped }
  );
  expect(denied.status()).toBe(404);
  const operator = await page.request.get(endpoint, {
    headers: target.operator,
  });
  expect(operator.status()).toBe(401);
  const operatorPage = await page.context().newPage();
  await operatorPage.addInitScript(
    auth => Reflect.set(window, '__SYNTHETIC_AUTH__', auth),
    target.operator
  );
  const metadataResponse = operatorPage.waitForResponse(
    response =>
      response.url().endsWith('/administration') && response.status() === 200
  );
  await operatorPage.goto(location);
  const metadata = await (await metadataResponse).json();
  expect(metadata.capabilities.control).toBe(false);
  await expect(operatorPage.locator('[data-provider-state]')).toBeVisible();
  await expect(operatorPage.locator('[data-open-state-history]')).toHaveCount(
    0
  );
  await expect(operatorPage.locator('[data-history-row]')).toHaveCount(0);
  await operatorPage.close();
  expect(writes).toEqual([]);
});

test('Hoya workspace native restores and persists versioned ACW answers in the actual voice workspace', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].hoya_forms;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + `/qualifications/${target.qualification_id}`;
  const browserApi = endpoint.replace(':5387/', ':5386/');
  const errors = [];
  const external = [];
  const commands = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    if (
      ['http:', 'https:'].includes(url.protocol) &&
      url.hostname !== '127.0.0.1'
    ) {
      external.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    return route.continue();
  });
  page.on('request', request => {
    const url = new URL(request.url());
    if (
      ['http:', 'https:'].includes(url.protocol) &&
      url.hostname !== '127.0.0.1'
    )
      external.push(url.origin + url.pathname);
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        url.pathname
      ) &&
      !['GET', 'HEAD'].includes(request.method())
    )
      commands.push(url.pathname);
  });
  await page.goto(
    `/app/accounts/${target.account_id}/synthetic-hoya-acw/${target.call_session_id}`
  );
  const workspace = page.getByTestId('hoya-inbox-workspace');
  await expect(workspace).toBeVisible();
  const form = workspace.locator('[data-pending-qualification-form]');
  await expect(form).toBeVisible();
  await form
    .locator('[data-qualification-field="reason"]')
    .selectOption('order');
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  const fields = form.locator('[data-acw-form-fields]');
  await expect(fields.locator('[data-acw-answer]')).toHaveCount(3);
  await expect(form.locator('[data-complete-qualification]')).toBeDisabled();
  await fields
    .locator('[data-acw-answer="feedback"]')
    .fill('SYNTHETIC Hoya actual workspace private answer');
  await fields.locator('[data-acw-answer="verified"]').selectOption('false');
  await fields.locator('[data-acw-answer="quantity"]').fill('0');
  const saved = page.waitForResponse(
    response =>
      response.url() === browserApi + '/draft' &&
      response.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  const receipt = await saved;
  expect(receipt.status()).toBe(200);
  expect((await receipt.json()).item.completed_at).toBeNull();
  await page.reload();
  await expect(fields.locator('[data-acw-answer="feedback"]')).toHaveValue(
    'SYNTHETIC Hoya actual workspace private answer'
  );
  await expect(fields.locator('[data-acw-answer="verified"]')).toHaveValue(
    'false'
  );
  await expect(fields.locator('[data-acw-answer="quantity"]')).toHaveValue('0');
  await expect(form.locator('[data-qualification-draft-saved]')).toBeVisible();
  await expect(
    workspace.getByText('Limite aplicado: 01:00', { exact: true })
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await fields.scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-hoya-operational-form.png`,
    fullPage: false,
  });
  const completed = page.waitForResponse(
    response =>
      response.url() === browserApi && response.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  const final = await completed;
  expect(final.status()).toBe(200);
  expect((await final.json()).item.completed_at).not.toBeNull();
  const state = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    {
      headers: target.operator,
    }
  );
  expect(state.status()).toBe(200);
  const original = (await state.json()).items.find(
    row => String(row.id) === String(target.qualification_id)
  );
  expect(original.completed_at).not.toBeNull();
  expect(errors).toEqual([]);
  expect(external).toEqual([]);
  expect(commands).toEqual([]);
});

test('ending reason native catalogue persists revisions and deactivation with filtering paging and authorized rule selection', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].form_bindings;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + '/acw_policy';
  const location = `/app/accounts/${target.account_id}/contact-center/control-desk/closures`;
  const original = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(original.status()).toBe(200);
  const initial = (await original.json()).item;
  expect(initial.voice_reason_catalog).toEqual({ version: 0, entries: [] });
  const seedRows = Array.from({ length: 12 }, (_, i) => ({
    code: `synthetic_seed_${i}`,
    name: `SYNTHETIC ending reason ${i}`,
    category: 'SYNTHETIC native category',
    description: 'SYNTHETIC bounded catalogue seed',
    order: i,
    active: i % 2 === 0,
  }));
  const prepared = await page.request.patch(endpoint, {
    headers: target.administrator,
    data: {
      limits: initial.limits,
      expected_revision: initial.revision,
      voice_reason_catalog: seedRows,
    },
  });
  expect(prepared.status()).toBe(200);
  await page.goto(location);
  await page.locator('[data-manage-ending-reasons]').click();
  await expectContainedDialog(page);
  let catalog = page.locator('[data-ending-reason-catalog]');
  await expect(catalog.locator('[data-ending-entry]')).toHaveCount(10);
  await catalog.locator('[data-ending-next]').click();
  await expect(catalog.locator('[data-ending-entry]')).toHaveCount(2);
  await catalog.locator('[data-ending-search]').fill('reason 11');
  await expect(catalog.locator('[data-ending-entry]')).toHaveCount(1);
  await catalog.locator('[data-ending-status]').selectOption('active');
  await expect(catalog.locator('[data-ending-entry]')).toHaveCount(0);
  await catalog.locator('[data-ending-clear]').click();
  await expect(catalog.locator('[data-ending-entry]')).toHaveCount(10);
  await catalog.locator('[data-ending-add]').click();
  let row = catalog.locator('[data-ending-entry]').last();
  await expect(row.locator('[data-ending-code]')).toHaveValue('');
  await expect(catalog.locator('[data-ending-save]')).toBeDisabled();
  const code = 'synthetic_browser_ending';
  await row.locator('[data-ending-code]').fill(code);
  await row.locator('[data-ending-name]').fill('SYNTHETIC browser ending');
  await row
    .locator('[data-ending-category]')
    .fill('SYNTHETIC browser category');
  await row
    .locator('[data-ending-description]')
    .fill('SYNTHETIC persisted description');
  await row.locator('[data-ending-order]').fill('120');
  await row.locator('[data-ending-active]').check();
  const written = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await catalog.locator('[data-ending-save]').click();
  const saved = await written;
  expect(saved.status()).toBe(200);
  expect((await saved.json()).item.voice_reason_catalog.version).toBe(2);
  await expect(catalog.locator('[data-ending-saved]')).toBeVisible();
  await page.reload();
  await page.locator('[data-manage-ending-reasons]').click();
  catalog = page.locator('[data-ending-reason-catalog]');
  await catalog.locator('[data-ending-search]').fill(code);
  row = catalog.locator('[data-ending-entry]').first();
  await row.locator('summary').click();
  await expect(row.locator('[data-ending-name]')).toHaveValue(
    'SYNTHETIC browser ending'
  );
  await expect(row.locator('[data-ending-category]')).toHaveValue(
    'SYNTHETIC browser category'
  );
  await expect(row.locator('[data-ending-description]')).toHaveValue(
    'SYNTHETIC persisted description'
  );
  await expect(row.locator('[data-ending-code]')).toBeDisabled();
  await expect(row.locator('[data-ending-active]')).toBeChecked();
  await catalog.locator('[data-ending-close]').click();
  await expect(catalog).not.toBeVisible();
  await page.locator('[data-create]').click();
  const rulesDialog = page.getByRole('dialog');
  await rulesDialog.locator('[data-add-acw-rule]').click();
  const rule = rulesDialog.locator('[data-acw-rule-row]').last();
  await rule.locator('[data-acw-rule-reason]').selectOption(code);
  await expect(
    rule.locator('[data-acw-rule-reason] option:checked')
  ).toHaveText('SYNTHETIC browser ending');
  await rule.locator('[data-acw-rule-time]').fill('00:01');
  const configured = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await rulesDialog
    .getByRole('button', { name: 'Salvar', exact: true })
    .click();
  expect((await configured).status()).toBe(200);
  await expect(rulesDialog).not.toBeVisible();
  const current = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(current.status()).toBe(200);
  const state = (await current.json()).item;
  expect(
    state.voice_rules.filter(value => value.id === target.form_rule_id)
  ).toEqual(
    initial.voice_rules.filter(value => value.id === target.form_rule_id)
  );
  expect(
    state.voice_rules.find(value => value.reason_code === code)
  ).toMatchObject({ active: false, limit_seconds: 60 });
  await page.locator('[data-manage-ending-reasons]').click();
  catalog = page.locator('[data-ending-reason-catalog]');
  await catalog.locator('[data-ending-search]').fill(code);
  row = catalog.locator('[data-ending-entry]').first();
  await row.locator('summary').click();
  await row.locator('[data-ending-name]').fill('SYNTHETIC revised ending');
  await row.locator('[data-ending-active]').uncheck();
  const deactivated = page.waitForResponse(
    response =>
      response.url().endsWith('/acw_policy') &&
      response.request().method() === 'PATCH'
  );
  await catalog.locator('[data-ending-save]').click();
  const receipt = await deactivated;
  expect(receipt.status()).toBe(200);
  const final = (await receipt.json()).item;
  expect(final.voice_reason_catalog.version).toBe(3);
  expect(final.voice_reason_catalog.entries).toHaveLength(13);
  expect(
    final.voice_reason_catalog.entries.find(value => value.code === code)
  ).toMatchObject({ active: false, name: 'SYNTHETIC revised ending' });
  expect(final.voice_rules).toEqual(state.voice_rules);
  await expect(catalog.locator('[data-ending-saved]')).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await row.scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ending-reason-catalog.png`,
    fullPage: false,
  });
  const operator = await page.request.get(endpoint, {
    headers: target.operator,
  });
  expect(operator.status()).toBe(200);
  expect((await operator.json()).item).not.toHaveProperty(
    'voice_reason_catalog'
  );
  const denied = await page.request.patch(endpoint, {
    headers: target.operator,
    data: {
      limits: final.limits,
      voice_reason_catalog: [],
      expected_revision: final.revision,
    },
  });
  expect(denied.status()).toBe(401);
  const operatorPage = await page.context().newPage();
  await operatorPage.addInitScript(
    auth => Reflect.set(window, '__SYNTHETIC_AUTH__', auth),
    target.operator
  );
  const metadata = operatorPage.waitForResponse(
    response =>
      response.url().endsWith('/administration') && response.status() === 200
  );
  await operatorPage.goto(location);
  expect(
    (await (await metadata).json()).capabilities.configuration_global
  ).toBe(false);
  await expect(operatorPage.getByRole('alert')).toContainText(
    'Seção indisponível no seu escopo de acesso.'
  );
  await expect(
    operatorPage.locator('[data-administration-section]')
  ).toHaveCount(0);
  await expect(
    operatorPage.locator('[data-manage-ending-reasons]')
  ).toHaveCount(0);
  await operatorPage.close();
});

test('registered ending native preserves the call catalogue while managers revise required queues and operators complete in Hoya', async ({
  page,
}, info) => {
  const target = session.pause_targets[info.project.name].required_endings;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const policyEndpoint = ownApi + '/acw_policy';
  const location = `/app/accounts/${target.account_id}/contact-center/control-desk/closures`;
  await page.goto(location);
  await page.locator('[data-manage-ending-reasons]').click();
  const catalog = page.locator('[data-ending-reason-catalog]');
  await expectContainedDialog(page);
  await expect(catalog.locator('[data-ending-selected-queue]')).toHaveCount(1);
  await catalog.locator('[data-ending-required-queues] summary').click();
  await catalog.locator('[data-ending-selected-queue] button').click();
  const row = catalog.locator('[data-ending-entry]').first();
  await row.locator('summary').click();
  await row.locator('[data-ending-name]').fill('SYNTHETIC future ending');
  await row.locator('[data-ending-active]').uncheck();
  let saved = page.waitForResponse(
    r => r.url().endsWith('/acw_policy') && r.request().method() === 'PATCH'
  );
  await catalog.locator('[data-ending-save]').click();
  expect((await saved).status()).toBe(200);
  await expect(catalog.locator('[data-ending-saved]')).toBeVisible();
  if (!(await row.evaluate(el => el.open)))
    await row.locator('summary').click();
  await row.locator('[data-ending-active]').check();
  await catalog
    .locator('[data-acw-rule-target] select')
    .selectOption(String(target.queue_id));
  await catalog.locator('[data-ending-add-queue]').click();
  await expect(catalog.locator('[data-ending-save]')).toBeDisabled();
  await catalog.locator('[data-ending-queue-confirmation]').check();
  saved = page.waitForResponse(
    r => r.url().endsWith('/acw_policy') && r.request().method() === 'PATCH'
  );
  await catalog.locator('[data-ending-save]').click();
  const current = await saved;
  expect(current.status()).toBe(200);
  const latest = (await current.json()).item;
  expect(latest.voice_reason_catalog.version).toBe(4);
  expect(latest.voice_reason_catalog.required_queue_ids).toEqual([
    String(target.queue_id),
  ]);
  expect(latest.voice_required).toBe(false);
  await catalog
    .locator('[data-ending-required-queues]')
    .scrollIntoViewIfNeeded();
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ending-required-queues.png`,
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));

  const operatorPage = await page.context().newPage();
  const errors = [];
  const external = [];
  const commands = [];
  operatorPage.on('pageerror', error => errors.push(error.message));
  await operatorPage.route('**/*', route => {
    const url = new URL(route.request().url());
    if (
      ['http:', 'https:'].includes(url.protocol) &&
      url.hostname !== '127.0.0.1'
    ) {
      external.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        url.pathname
      ) &&
      !['GET', 'HEAD'].includes(route.request().method())
    )
      commands.push(url.pathname);
    return route.continue();
  });
  await operatorPage.addInitScript(
    ({ auth, dark }) => {
      Reflect.set(window, '__SYNTHETIC_AUTH__', auth);
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', dark)
      );
    },
    { auth: target.operator, dark: info.project.name.endsWith('dark') }
  );
  const legacy = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.legacy_call_session_id}`,
    { headers: target.operator }
  );
  expect(legacy.status()).toBe(200);
  expect((await legacy.json()).items).toEqual([]);
  const denied = await page.request.get(policyEndpoint, {
    headers: target.operator,
  });
  expect(denied.status()).toBe(200);
  expect((await denied.json()).item).not.toHaveProperty('voice_reason_catalog');
  await operatorPage.goto(
    `/app/accounts/${target.account_id}/synthetic-hoya-acw/${target.call_session_id}`
  );
  let form = operatorPage.locator('[data-pending-qualification-form]');
  await expect(form).toBeVisible();
  await expect(form.locator('[data-ending-reason-version]')).toContainText('2');
  const reason = form.locator('[data-qualification-field="reason"]');
  await expect(reason.locator('option')).toHaveCount(2);
  await expect(reason.locator('option').last()).toHaveText(
    'SYNTHETIC original ending'
  );
  await reason.selectOption(target.ending_reason_code);
  await form
    .locator('[data-qualification-field="result"]')
    .selectOption('completed');
  await expect(form.locator('[data-complete-qualification]')).toBeEnabled();
  const draft = operatorPage.waitForResponse(
    r =>
      r.url().endsWith(`/qualifications/${target.qualification_id}/draft`) &&
      r.request().method() === 'PATCH'
  );
  await form.locator('[data-save-qualification-draft]').click();
  expect((await draft).status()).toBe(200);
  await operatorPage.reload();
  form = operatorPage.locator('[data-pending-qualification-form]');
  await expect(form.locator('[data-qualification-field="reason"]')).toHaveValue(
    target.ending_reason_code
  );
  await expect(form.locator('[data-ending-reason-version]')).toContainText('2');
  expect(
    await operatorPage
      .locator('html')
      .evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  expect(
    await operatorPage.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await form.scrollIntoViewIfNeeded();
  await operatorPage.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-ending-frozen-hoya.png`,
  });
  const completed = operatorPage.waitForResponse(
    r =>
      r.url().endsWith(`/qualifications/${target.qualification_id}`) &&
      r.request().method() === 'PATCH'
  );
  await form.locator('[data-complete-qualification]').click();
  const result = await completed;
  expect(result.status()).toBe(200);
  expect((await result.json()).item.completed_at).not.toBeNull();
  const persisted = await page.request.get(
    ownApi + `/qualifications?call_session_id=${target.call_session_id}`,
    { headers: target.operator }
  );
  const record = (await persisted.json()).items.find(
    row => String(row.id) === String(target.qualification_id)
  );
  expect(record.reason_code).toBe(target.ending_reason_code);
  expect(record.completed_at).not.toBeNull();
  expect(errors).toEqual([]);
  expect(external).toEqual([]);
  expect(commands).toEqual([]);
  await operatorPage.close();
});

test('inactive membership native denies enrollment despite a retained grant and safely deactivates an existing link', async ({
  page,
}, info) => {
  const target =
    session.pause_targets[info.project.name].membership_eligibility;
  const ownApi = `http://127.0.0.1:5387/api/v1/accounts/${target.account_id}/jrc_contact_center`;
  const endpoint = ownApi + '/queue_memberships';
  const errors = [];
  const external = [];
  const commands = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    if (
      ['http:', 'https:'].includes(url.protocol) &&
      url.hostname !== '127.0.0.1'
    ) {
      external.push(url.origin + url.pathname);
      return route.abort('blockedbyclient');
    }
    if (
      /\/(commands|sync_calls|telephony_integration)(?:[/?]|$)/.test(
        url.pathname
      ) &&
      !['GET', 'HEAD'].includes(route.request().method())
    )
      commands.push(url.pathname);
    return route.continue();
  });
  const initial = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect(initial.status()).toBe(200);
  const before = (await initial.json()).meta.total;
  await page.goto(
    `/app/accounts/${target.account_id}/contact-center/control-desk/queues?queues_tab=memberships`
  );
  await page.locator('[data-create]').click();
  let dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  const unavailable = dialog.locator(`option[value="${target.operator_id}"]`);
  await expect(unavailable).toBeDisabled();
  await expect(unavailable).toContainText(
    'Indisponível para novas atribuições'
  );
  for (const participates of [true, false]) {
    const denied = await page.request.post(endpoint, {
      headers: target.administrator,
      data: {
        queue_membership: {
          queue_id: target.enrollment_queue_id,
          account_user_id: target.operator_id,
          participates,
          supervises: !participates,
        },
      },
    });
    expect(denied.status()).toBe(422);
    expect((await denied.json()).error).toBe('ineligible_member');
  }
  await dialog.getByRole('button', { name: 'Cancelar', exact: true }).click();
  let row = page.locator(
    `[data-resource-id="${target.inactive_membership_id}"]`
  );
  await row.locator('[data-edit]').click();
  dialog = page.getByRole('dialog');
  await expectContainedDialog(page);
  await expect(
    dialog.locator(`option[value="${target.operator_id}"]`)
  ).toBeEnabled();
  await expect(dialog.getByLabel('Usuário', { exact: true })).toHaveValue(
    String(target.operator_id)
  );
  await dialog.getByLabel('Ativo', { exact: true }).uncheck();
  let saved = page.waitForResponse(
    r =>
      r.url().endsWith(`/queue_memberships/${target.inactive_membership_id}`) &&
      r.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(200);
  await page.reload();
  row = page.locator(`[data-resource-id="${target.inactive_membership_id}"]`);
  await expect(row).toContainText('Inativo');
  await row.locator('[data-edit]').click();
  dialog = page.getByRole('dialog');
  await dialog.getByLabel('Ativo', { exact: true }).check();
  saved = page.waitForResponse(
    r =>
      r.url().endsWith(`/queue_memberships/${target.inactive_membership_id}`) &&
      r.request().method() === 'PATCH'
  );
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  expect((await saved).status()).toBe(422);
  await expect(dialog.getByRole('alert')).toContainText(
    'não está elegível para novas atribuições'
  );
  await expect(dialog.getByLabel('Ativo', { exact: true })).toBeChecked();
  const stored = await page.request.get(
    endpoint + `/${target.inactive_membership_id}`,
    { headers: target.administrator }
  );
  expect(stored.status()).toBe(200);
  expect((await stored.json()).item).toMatchObject({
    active: false,
    account_user_id: target.operator_id,
  });
  const after = await page.request.get(endpoint, {
    headers: target.administrator,
  });
  expect((await after.json()).meta.total).toBe(before);
  const grant = await page.request.get(
    ownApi + `/access_authorizations/users/${target.operator_id}`,
    { headers: target.administrator }
  );
  expect(grant.status()).toBe(200);
  expect((await grant.json()).item.eligible).toBe(true);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  expect(
    await page.locator('html').evaluate(el => el.classList.contains('dark'))
  ).toBe(info.project.name.endsWith('dark'));
  await page.screenshot({
    path: `.codex/call-center-native-e2e/${info.project.name}-inactive-recipient-guard.png`,
  });
  expect(errors).toEqual([]);
  expect(external).toEqual([]);
  expect(commands).toEqual([]);
});
