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
          rect: element.getBoundingClientRect().toJSON(),
        }))
        .filter(element => element.rect.width > width + 1),
    };
  });
  await writeFile(
    testInfo.outputPath(`${stage}-viewport.json`),
    JSON.stringify(geometry, null, 2)
  );
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.width + 1);
};

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
