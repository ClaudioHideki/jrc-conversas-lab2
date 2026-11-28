import { test, expect } from '@playwright/test';
const fixture = '/tests/playwright/fixtures/voice-v4/index.html';
test('mantém os painéis estáveis no limite de altura com conversa aberta', async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop');
  await page.goto(fixture);
  await page.locator('[data-fixture-whatsapp]').click();
  await expect(page.locator('[data-whatsapp-fixture]')).toBeVisible();
  const workspace = page.getByTestId('hoya-inbox-workspace');
  for (const height of [800, 690, 600, 800]) {
    // Fix the space supplied by the dashboard shell, as on an idle desktop.
    await workspace.evaluate((el, px) => {
      el.style.flex = 'none';
      el.style.height = `${px}px`;
    }, height);
    const positions = await workspace.evaluate(async el => {
      const list = el.querySelector('[data-testid="inbox-list"]')!;
      const panel = el.querySelector('[data-testid="interaction-workspace"]')!;
      const samples = [];
      for (let frame = 0; frame < 24; frame++) {
        await new Promise(requestAnimationFrame);
        if (frame < 4) continue;
        samples.push(
          [list, panel]
            .map(node => {
              const { x, y, width, height: h } = node.getBoundingClientRect();
              return [x, y, width, h].join(',');
            })
            .join('/')
        );
      }
      return [...new Set(samples)];
    });
    expect(positions, `altura disponível de ${height}px`).toHaveLength(1);
    if (height !== 690) {
      await expect(workspace.locator(':scope > header')).toHaveClass(
        height === 600 ? /min-h-11/ : /min-h-14/
      );
    }
  }
});
test.beforeEach(async ({ page, baseURL }) => {
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
    route.request().url().startsWith(`${baseURL}/`)
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
  await expect(
    page
      .locator('[data-testid=interaction-workspace] header')
      .getByRole('button', { name: 'Encerrar', exact: false })
  ).toHaveCount(0);
  await page.screenshot({
    path: testInfo.outputPath('ligacao-conectada.png'),
    fullPage: true,
  });
  const barHeight = (await bar.boundingBox())?.height;
  await bar.locator('[data-voice-action=KEYPAD]').click();
  await expect(bar.locator('[data-call-keypad] button')).toHaveCount(12);
  expect((await bar.boundingBox())?.height).toBe(barHeight);
  await page.screenshot({
    path: testInfo.outputPath('teclado-dtmf.png'),
    fullPage: true,
  });
  await bar.locator('[data-voice-action=KEYPAD]').click();
  await bar.locator('[data-voice-action=HOLD]').click();
  await expect(bar).toContainText('Em espera');
  await page.screenshot({
    path: testInfo.outputPath('em-espera.png'),
    fullPage: true,
  });
  await bar.locator('[data-voice-action=HOLD]').click();
  await expect(bar).toContainText('Em ligação');
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
test('discador preserva contexto e permite anotar depois da chamada', async ({
  page,
}, testInfo) => {
  await page.goto(`${fixture}?state=idle`);
  const bar = page.locator('[data-global-voice-bar]');
  await expect(bar).toContainText('Nenhuma ligação ativa');
  const idleStatus = await bar.locator('[data-voice-status]').boundingBox();
  const dialpad = await bar.locator('[data-voice-dialpad]').boundingBox();
  const barBounds = await bar.boundingBox();
  expect(idleStatus).not.toBeNull();
  expect(dialpad).not.toBeNull();
  expect(barBounds).not.toBeNull();
  expect(dialpad!.x - (idleStatus!.x + idleStatus!.width)).toBeLessThan(24);
  expect(
    barBounds!.x + barBounds!.width - (dialpad!.x + dialpad!.width)
  ).toBeLessThan(24);
  expect(
    Math.abs(
      idleStatus!.y +
        idleStatus!.height / 2 -
        (dialpad!.y + dialpad!.height / 2)
    )
  ).toBeLessThan(4);
  await page.screenshot({
    path: testInfo.outputPath('vazio.png'),
    fullPage: true,
  });
  await bar.getByRole('button', { name: 'Nova ligação', exact: true }).click();
  await expect(
    page.getByRole('dialog', { name: 'Nova ligação' })
  ).toBeVisible();
  await expect(page.locator('[data-whatsapp-fixture]')).toBeVisible();
  await expect(page.locator('[data-outbound-call]')).toBeDisabled();
  const phone = page.locator('[data-outbound-phone]');
  await phone.fill('2002');
  await expect(phone).toHaveValue('2002');
  await expect(phone).toHaveCSS('color', 'rgb(28, 32, 36)');
  await expect(page.locator('[data-outbound-call]')).toBeEnabled();
  await page.screenshot({
    path: testInfo.outputPath('nova-ligacao.png'),
    fullPage: true,
  });
  await page.locator('[data-outbound-call]').click();
  await expect(bar).toContainText('Chamando');
  await expect(bar).not.toContainText('Em ligação');
  const activeDialer = page.getByRole('dialog', {
    name: 'Controles da ligação ativa',
  });
  await expect(activeDialer.locator('[data-voice-action=MUTE]')).toBeDisabled();
  await expect(
    activeDialer.locator('[data-voice-action=TRANSFER]')
  ).toBeDisabled();
  await page.screenshot({
    path: testInfo.outputPath('chamando.png'),
    fullPage: true,
  });
  await activeDialer
    .getByRole('button', { name: 'Cancelar tentativa' })
    .click();
  await expect(activeDialer).not.toBeVisible();
  await expect(bar).toContainText('Nenhuma ligação ativa');
});
test('mantem a chamada ao sair do Atendimento para outro modulo e voltar', async ({
  page,
}) => {
  await page.goto(fixture);
  const bar = page.locator('[data-global-voice-bar]');
  await expect(bar).toContainText('Em ligação');
  await page.locator('[data-fixture-other-module]').click();
  await expect(page.locator('[data-fixture-module]')).toBeVisible();
  await expect(page.locator('[data-testid=hoya-inbox-workspace]')).toHaveCount(
    0
  );
  await expect(bar).toContainText('Cliente sintético A');
  await bar.locator('[data-voice-action=MUTE]').click();
  await expect(bar.locator('[data-voice-action=MUTE]')).toHaveAttribute(
    'aria-pressed',
    'true'
  );
  await page.locator('[data-fixture-voice]').click();
  await expect(
    page.locator('[data-testid=hoya-inbox-workspace]')
  ).toBeVisible();
  await expect(bar.locator('[data-voice-action=MUTE]')).toHaveAttribute(
    'aria-pressed',
    'true'
  );

  await bar.getByRole('button', { name: 'Controles da ligação ativa' }).click();
  const activeDialer = page.getByRole('dialog', {
    name: 'Controles da ligação ativa',
  });
  const mute = activeDialer.locator('[data-voice-action=MUTE]');
  await expect(mute).toHaveAttribute('aria-pressed', 'true');
  await mute.click();
  await expect(mute).toHaveAttribute('aria-pressed', 'false');
  const hold = activeDialer.locator('[data-voice-action=HOLD]');
  await hold.click();
  await expect(hold).toHaveAttribute('aria-pressed', 'true');
  await hold.click();
  await expect(hold).toHaveAttribute('aria-pressed', 'false');
  await activeDialer.locator('[data-voice-action=TRANSFER]').click();
  const transfer = activeDialer.locator('form');
  await transfer.locator('input').fill('2002');
  await transfer
    .getByRole('button', { name: 'Transferir', exact: true })
    .click();
  await expect(transfer).not.toBeVisible();
  await activeDialer.getByRole('button', { name: 'Encerrar ligação' }).click();
  await expect(activeDialer).not.toBeVisible();
  await expect(bar).toContainText('Nenhuma ligação ativa');
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
