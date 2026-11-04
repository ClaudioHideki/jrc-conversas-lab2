import { test, expect } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

const path = '/tests/playwright/fixtures/whatsapp-word/index.html';

const checkViewport = async (page, testInfo, stage) => {
  const geometry = await page.evaluate(() => {
    const width = document.documentElement.clientWidth;
    return {
      width,
      scrollWidth: document.documentElement.scrollWidth,
      visualWidth: visualViewport?.width,
      oversized: [...document.querySelectorAll('body *')]
        .map(element => ({
          tag: element.tagName,
          class: element.className,
          overflow: getComputedStyle(element).overflow,
          position: getComputedStyle(element).position,
          parent: element.parentElement?.className,
          rect: element.getBoundingClientRect().toJSON(),
        }))
        .filter(
          element =>
            element.rect.width > width + 1 || element.rect.right > width + 1
        ),
    };
  });
  await writeFile(
    testInfo.outputPath(`${stage}-viewport.json`),
    JSON.stringify(geometry, null, 2)
  );
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.width + 1);
};

test('busca conexoes autorizadas por nome sem acentos e limpa resultados vazios', async ({
  page,
}, testInfo) => {
  await page.goto(path);
  await page.getByTestId('connection-search').fill('TECNICO');
  await expect(page.getByTestId('connection-card-701')).toBeVisible();
  await expect(page.getByTestId('connection-card-702')).toHaveCount(0);
  await expect(page.getByTestId('connection-search-results')).toContainText(
    '1 de 2'
  );
  await page.getByTestId('connection-search').fill('sem correspondencia');
  await expect(page.getByTestId('connection-search-empty')).toBeVisible();
  await page.getByTestId('clear-connection-search').click();
  await expect(page.getByTestId('connection-card-702')).toBeVisible();
  await expect(page.getByTestId('fixture-create-requests')).toHaveText('0');
  await expect(page.getByTestId('fixture-adopt-requests')).toHaveText('0');
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
  await checkViewport(page, testInfo, 'name-search');
  await page.screenshot({
    path: testInfo.outputPath('busca-conexoes.png'),
    fullPage: true,
  });
});

test('cria caixa em quatro etapas com busca e revisao antes da unica confirmacao', async ({
  page,
}, testInfo) => {
  await page.goto(path);
  await page.getByTestId('new-whatsapp-number').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByTestId('onboarding-step-1')).toBeVisible();
  await expect(dialog.getByTestId('onboarding-name')).toHaveCount(0);
  await page.screenshot({
    path: testInfo.outputPath('cadastro-1-tipo.png'),
    fullPage: true,
  });
  await dialog.getByTestId('setup-type-create').check();
  await dialog.getByTestId('onboarding-next').click();
  await dialog.getByTestId('onboarding-name').fill('Caixa de testes');
  await dialog.getByTestId('onboarding-instance-search').fill('CONEXAO 1');
  await dialog.getByTestId('instance-demo-instance-1').check();
  await expect(dialog.getByTestId('onboarding-agent-search')).toHaveCount(0);
  await checkViewport(page, testInfo, 'wizard-inbox');
  await page.screenshot({
    path: testInfo.outputPath('cadastro-2-caixa.png'),
    fullPage: true,
  });
  await dialog.getByTestId('onboarding-next').click();
  await dialog.getByTestId('onboarding-agent-search').fill('AGATA');
  await dialog.getByTestId('agent-1').check();
  await dialog.getByTestId('onboarding-agent-search').fill('Agente 30');
  await expect(dialog.getByTestId('agent-1')).toHaveCount(0);
  await checkViewport(page, testInfo, 'wizard-agents');
  await page.screenshot({
    path: testInfo.outputPath('cadastro-3-agentes.png'),
    fullPage: true,
  });
  await dialog.getByTestId('onboarding-next').click();
  await expect(dialog.getByTestId('onboarding-review')).toContainText(
    'Ágata Demo'
  );
  await expect(dialog.getByTestId('onboarding-review')).toContainText(
    'Caixa de testes'
  );
  await expect(page.getByTestId('fixture-create-requests')).toHaveText('0');
  await expect(page.getByTestId('fixture-adopt-requests')).toHaveText('0');
  await dialog.getByTestId('onboarding-back').click();
  await dialog.getByTestId('onboarding-back').click();
  await expect(dialog.getByTestId('onboarding-name')).toHaveValue(
    'Caixa de testes'
  );
  await expect(dialog.getByTestId('instance-demo-instance-1')).toBeChecked();
  await dialog.getByTestId('onboarding-next').click();
  await dialog.getByTestId('onboarding-next').click();
  await checkViewport(page, testInfo, 'wizard-review');
  await page.screenshot({
    path: testInfo.outputPath('cadastro-4-revisao.png'),
    fullPage: true,
  });
  await dialog.getByTestId('create').click();
  await expect(page.getByTestId('fixture-create-requests')).toHaveText('1');
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
});

test('vincula uma caixa existente com busca e confirmacao sem repetir o cadastro', async ({
  page,
}, testInfo) => {
  await page.goto(path);
  await page.getByTestId('new-whatsapp-number').click();
  const dialog = page.getByRole('dialog');
  await dialog.getByTestId('setup-type-adopt').check();
  await dialog.getByTestId('onboarding-next').click();
  await dialog.getByTestId('onboarding-inbox-search').fill('TECNICO');
  await dialog.getByTestId('adopt-demo-integration-1').check();
  await expect(dialog.getByTestId('onboarding-name')).toHaveCount(0);
  await dialog.getByTestId('onboarding-next').click();
  await expect(dialog.getByTestId('onboarding-agent-search')).toHaveCount(0);
  await dialog.getByTestId('onboarding-next').click();
  await expect(dialog.getByTestId('onboarding-review')).toContainText(
    'Suporte técnico'
  );
  await expect(page.getByTestId('fixture-adopt-requests')).toHaveText('0');
  await checkViewport(page, testInfo, 'adopt-review');
  await page.screenshot({
    path: testInfo.outputPath('vincular-revisao.png'),
    fullPage: true,
  });
  await dialog.getByTestId('create').click();
  await expect(page.getByTestId('fixture-adopt-requests')).toHaveText('1');
  await expect(page.getByTestId('fixture-create-requests')).toHaveText('0');
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
});

test('apresenta QR sintetico e prazo real sem usar sessao WhatsApp', async ({
  page,
}, testInfo) => {
  await page.goto(`${path}?role=agent&pairing=qr`);
  await page.getByTestId('reconnect-connection-702').click();
  await expect(page.getByRole('dialog').locator('img')).toHaveCount(0);
  await page.getByTestId('pair').click();
  await expect(page.getByRole('dialog').locator('img')).toBeVisible();
  await expect(page.getByRole('dialog').locator('img')).toHaveAttribute(
    'src',
    /^data:image\/png;base64,/
  );
  await expect(page.getByTestId('pairing-countdown')).toBeVisible();
  await page.screenshot({
    path: testInfo.outputPath('qrcode.png'),
    fullPage: true,
  });
});

test('administra conexoes e distribuicao sem iniciar pareamento ao abrir', async ({
  page,
}, testInfo) => {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(path);
  await expect(page.getByTestId('connections-list')).toBeVisible();
  await expect(page.locator('nav button[aria-pressed="true"]')).toHaveCSS(
    'border-bottom-style',
    'solid'
  );
  await expect(page.locator('nav button[aria-pressed="true"]')).toHaveCSS(
    'border-bottom-width',
    '2px'
  );
  await expect(page.getByTestId('connection-card-701')).toContainText(
    'Conectado'
  );
  await expect(page.getByTestId('connection-card-702')).toContainText(
    'Desconectado'
  );
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
  await checkViewport(page, testInfo, 'connections');
  await page.screenshot({
    path: testInfo.outputPath('conexoes.png'),
    fullPage: true,
  });
  await page.getByTestId('configure-distribution-701').click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('tab')).toHaveCount(5);
  await expect(
    dialog.getByRole('tab', { name: 'Distribuição', exact: true })
  ).toHaveAttribute('aria-selected', 'true');
  await dialog.locator('input[type="radio"][value="priority"]').check();
  await checkViewport(page, testInfo, 'distribution');
  await expect(dialog).toHaveClass(/max-h-/);
  await page.screenshot({
    path: testInfo.outputPath('distribuicao-antes-salvar.png'),
    fullPage: true,
  });
  if (testInfo.project.name === 'mobile') {
    const rules = await dialog
      .getByTestId('distribution-rules-fields')
      .boundingBox();
    const save = await dialog
      .getByTestId('distribution-policy-save')
      .boundingBox();
    expect(rules).not.toBeNull();
    expect(save).not.toBeNull();
    expect(save!.y).toBeGreaterThanOrEqual(rules!.y + rules!.height - 1);
  }
  const saveButton = dialog.getByTestId('distribution-policy-save');
  await saveButton.scrollIntoViewIfNeeded();
  await testInfo.attach('save-hit-target.json', {
    contentType: 'application/json',
    body: JSON.stringify(
      await saveButton.evaluate(element => {
        const rect = element.getBoundingClientRect();
        const hit = document.elementFromPoint(
          rect.x + rect.width / 2,
          rect.y + rect.height / 2
        );
        return {
          rect: rect.toJSON(),
          hit: hit?.outerHTML,
          viewport: {
            width: innerWidth,
            height: innerHeight,
            visualOffsetTop: visualViewport?.offsetTop,
          },
        };
      })
    ),
  });
  await saveButton.click();
  await expect(
    dialog.getByText('Distribuição salva.', { exact: false })
  ).toBeVisible();
  await page.screenshot({
    path: testInfo.outputPath('distribuicao.png'),
    fullPage: true,
  });
  await dialog
    .getByRole('tab', { name: 'Regras e horários', exact: true })
    .click();
  await expect(dialog.getByTestId('distribution-schedule')).toBeVisible();
  await expect(dialog.getByTestId('distribution-availability')).toBeChecked();
  await dialog.getByRole('tab', { name: 'Visão geral', exact: true }).click();
  await expect(
    dialog.getByRole('tab', { name: 'Visão geral', exact: true })
  ).toHaveAttribute('aria-selected', 'true');
  await expect(
    dialog.getByRole('tab', { name: 'Visão geral', exact: true })
  ).toHaveCSS('border-bottom-style', 'solid');
  await expect(dialog.getByTestId('connection-insights')).toContainText('12');
  await expect(dialog.getByTestId('connection-insights')).toContainText(
    'Sem dados'
  );
  await page.screenshot({
    path: testInfo.outputPath('detalhes.png'),
    fullPage: true,
  });
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
  expect(errors).toEqual([]);
});

test('reconecta somente por acao explicita e limita a jornada do agente', async ({
  page,
}, testInfo) => {
  await page.goto(`${path}?role=agent`);
  await expect(page.getByTestId('connections-list')).toBeVisible();
  await expect(page.getByTestId('distribution-table')).toHaveCount(0);
  await expect(page.getByTestId('new-whatsapp-number')).toHaveCount(0);
  await page.getByTestId('reconnect-connection-702').click();
  await expect(page.getByTestId('pairing-instructions')).toBeVisible();
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('0');
  await page.getByTestId('pair').click();
  await expect(page.getByRole('dialog').getByText('DEMO-ONLY')).toBeVisible();
  await expect(page.getByTestId('pairing-countdown')).toBeVisible();
  await expect(page.getByTestId('fixture-pair-requests')).toHaveText('1');
  await page.screenshot({
    path: testInfo.outputPath('reconectar.png'),
    fullPage: true,
  });
  await page
    .getByRole('dialog')
    .getByRole('button', { name: 'Fechar', exact: true })
    .click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByText('DEMO-ONLY')).toHaveCount(0);
});
