import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const session = JSON.parse(
  fs.readFileSync('/tmp/call-center-e2e-session.private', 'utf8')
);
const base = `/app/accounts/${session.account_id}/contact-center/control-desk`;
const api = `http://127.0.0.1:5387/api/v1/accounts/${session.account_id}/jrc_contact_center`;
test.beforeEach(async ({ page }, info) => {
  await page.addInitScript(
    ({ auth, dark }) => {
      window.__SYNTHETIC_AUTH__ = auth;
      document.addEventListener('DOMContentLoaded', () =>
        document.documentElement.classList.toggle('dark', dark)
      );
    },
    { auth: session.administrator, dark: info.project.name.endsWith('dark') }
  );
});

test('fifteen permission-bound cards, actual CSS, honest pending states and no overflow', async ({
  page,
}, info) => {
  await page.goto(base);
  await expect(page.locator('[data-card]')).toHaveCount(15);
  await expect(
    page.getByRole('heading', { name: 'Central Administrativa', exact: true })
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
  for (const key of [
    'numbers',
    'ivr',
    'hours',
    'audio',
    'pauses',
    'distribution',
    'recordings',
  ]) {
    await page.locator(`[data-card="${key}"]`).click();
    await expect(
      page.locator('[data-administration-section] [role="status"]')
    ).toContainText('Funcionalidade pendente');
    await expect(page.locator('[data-create]')).toHaveCount(0);
    await page
      .getByText('Voltar à Central Administrativa', { exact: true })
      .click();
  }
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
    .getByRole('button', { name: 'Limpar filtros', exact: true })
    .click();
  await expect(page.locator('[data-resource-row]')).toHaveCount(20);
});

test('profile change cannot reveal administrative cards, write, or cross Account boundaries', async ({
  page,
}) => {
  await page.addInitScript(auth => {
    window.__SYNTHETIC_AUTH__ = auth;
  }, session.viewer);
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
});
