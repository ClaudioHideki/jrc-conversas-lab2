import { test, expect } from '@playwright/test';
const fixture = '/tests/playwright/fixtures/voice-v4/index.html';
test.beforeEach(async ({ page }) => {
  let errors = 0;
  page.on('pageerror', error => {
    if (errors++ < 3)
      console.log(
        `Fixture error: ${error.stack?.slice(0, 1200) || error.message}`
      );
  });
  page.on('console', message => {
    if (message.type() === 'error' && errors++ < 3)
      console.log(`Fixture console: ${message.text().slice(0, 600)}`);
  });
  await page.route('**/*', route =>
    route.request().url().startsWith('http://127.0.0.1:5226/')
      ? route.continue()
      : route.abort()
  );
});
test('mantem chamada A e controles ao abrir WhatsApp B sem overflow da pagina', async ({
  page,
}, testInfo) => {
  await page.goto(fixture);
  const bar = page.locator('[data-global-voice-bar]');
  await expect(bar).toContainText('Em ligação');
  await expect(page.locator('[data-voice-script]')).toBeVisible();
  await expect(page.locator('body')).not.toContainText('JRC_CONTACT_CENTER.');
  await page.screenshot({
    path: testInfo.outputPath('ligacao-conectada.png'),
    fullPage: true,
  });
  await bar.locator('[data-voice-action=KEYPAD]').click();
  await expect(bar.locator('[data-call-keypad] button')).toHaveCount(12);
  await page.screenshot({
    path: testInfo.outputPath('teclado-dtmf.png'),
    fullPage: true,
  });
  await bar.locator('[data-voice-action=KEYPAD]').click();
  await page.locator('[data-fixture-whatsapp]').click();
  await expect(page.locator('[data-whatsapp-fixture]')).toBeVisible();
  await expect(
    page.locator('[data-testid=interaction-workspace] header')
  ).toContainText('Cliente sintético B');
  await expect(bar).toContainText('Cliente sintético A');
  await bar.locator('[data-voice-action=MUTE]').click();
  await expect(bar.locator('[data-voice-action=MUTE]')).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await bar.locator('[data-voice-action=HOLD]').click();
  await expect(bar).toContainText('Em espera');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth + 1
    )
  ).toBe(true);
  await page.screenshot({
    path: testInfo.outputPath('voz-com-whatsapp.png'),
    fullPage: true,
  });
});
test('popup de saida preserva contexto e exige motivo antes de chamar', async ({
  page,
}, testInfo) => {
  await page.goto(`${fixture}?state=idle`);
  const bar = page.locator('[data-global-voice-bar]');
  await expect(bar).toContainText('Nenhuma ligação ativa');
  await bar.getByRole('button', { name: 'Nova ligação', exact: true }).click();
  await expect(
    page.getByRole('dialog', { name: 'Nova ligação' })
  ).toBeVisible();
  await expect(page.locator('[data-whatsapp-fixture]')).toBeVisible();
  await expect(page.locator('[data-outbound-call]')).toBeDisabled();
  await page.locator('[data-outbound-phone]').fill('2002');
  await page
    .locator('[data-outbound-reason]')
    .fill('Retorno solicitado no cenário sintético');
  await expect(page.locator('[data-outbound-call]')).toBeEnabled();
  await page.screenshot({
    path: testInfo.outputPath('nova-ligacao.png'),
    fullPage: true,
  });
  await page.locator('[data-outbound-call]').click();
  await expect(bar).toContainText('Chamando');
  await expect(bar).not.toContainText('Em ligação');
  await page.screenshot({
    path: testInfo.outputPath('chamando.png'),
    fullPage: true,
  });
});
test('recebendo sem cronometro e pos-atendimento sem telefonia ativa', async ({
  page,
}, testInfo) => {
  await page.goto(`${fixture}?state=incoming`);
  const bar = page.locator('[data-global-voice-bar]');
  await expect(bar).toContainText('Recebendo ligação');
  await expect(bar).not.toContainText('03:00');
  await page.screenshot({
    path: testInfo.outputPath('recebendo.png'),
    fullPage: true,
  });
  await page.goto(`${fixture}?state=ended`);
  await expect(bar).toContainText('Nenhuma ligação ativa');
  await expect(
    page.getByText('Pós-atendimento (ACW)', { exact: true }).first()
  ).toBeVisible();
  await page.screenshot({
    path: testInfo.outputPath('pos-atendimento.png'),
    fullPage: true,
  });
});
