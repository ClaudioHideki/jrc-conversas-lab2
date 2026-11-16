import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);
const base = `/app/accounts/${session.account_id}/contact-center/control-desk`;
const api = `http://127.0.0.1:5387/api/v1/accounts/${session.account_id}/jrc_contact_center`;
test.beforeEach(async ({ page }, info) => {
  const auth = info.title.startsWith('corporate boundary')
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
    .getByLabel('Unidade operacional', { exact: true })
    .selectOption(String(session.unit_id));
  await dialog.getByRole('button', { name: 'Salvar', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await page.locator('[data-edit]').click();
  await dialog.getByLabel('Nome', { exact: true }).fill(`${name}-revised`);
  await dialog.getByLabel('Status', { exact: true }).selectOption('inactive');
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
  await page.goto(`${base}/queues?queues_tab=memberships`);
  await page.locator('[data-create]').click();
  const dialog = page.getByRole('dialog');
  await dialog
    .getByLabel('Fila', { exact: true })
    .selectOption(String(queue.id));
  await dialog
    .getByLabel('Usuário', { exact: true })
    .selectOption(String(session.viewer_account_user_id));
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
  expect((await read.json()).items[0]).toMatchObject({
    participates: true,
    supervises: true,
    active: false,
  });
  await expect(
    page.getByRole('button', { name: 'Participantes', exact: true })
  ).toHaveAttribute('aria-pressed', 'true');
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
  await page.goto(`${base}/queues?queues_tab=teams`);
  await expect(page.locator('[data-create]')).toHaveCount(0);
});
