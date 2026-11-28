import { expect } from '@playwright/test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Extends the existing four native nonroot scenarios; no provider mock or command.
export async function verifyNativePabxReadiness(page, info, session) {
  const route = `/app/accounts/${session.account_id}/contact-center/pabx`;
  const api = `/api/v1/accounts/${session.account_id}/jrc_contact_center`;
  const writes = [];
  const onRequest = request => {
    if (!['GET', 'HEAD'].includes(request.method()))
      writes.push({
        method: request.method(),
        pathname: new URL(request.url()).pathname,
      });
  };
  page.on('request', onRequest);
  await page.goto(
    `/app/accounts/${session.account_id}/contact-center/control-desk/pabx?native_navigation=1&preserved=native-proof`
  );
  const sourceLink = page.locator('[data-native-pabx-observations-link]');
  await expect(sourceLink).toBeVisible();
  await expect(sourceLink).toHaveAttribute(
    'href',
    new RegExp(route + '(?:\\?|$)')
  );
  const observed = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === api + '/integrations/health' &&
      response.request().method() === 'GET'
  );
  const configured = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === api + '/administration' &&
      response.request().method() === 'GET'
  );
  await sourceLink.click();
  const [healthResponse, adminResponse] = await Promise.all([
    observed,
    configured,
  ]);
  expect(healthResponse.status()).toBe(200);
  expect(adminResponse.status()).toBe(200);
  const healthBytes = await healthResponse.body();
  const health = JSON.parse(healthBytes.toString());
  const admin = await adminResponse.json();
  expect(health.account_id).toBe(String(session.account_id));
  expect(health.contract_version).toBe(1);
  const root = page.locator('[data-native-pabx-page]');
  await expect(root).toBeVisible();
  await expect(
    root.getByRole('heading', {
      name: 'Configurações do PABX JRC',
      exact: true,
    })
  ).toBeVisible();
  await expect(root.locator('[data-native-pabx-configured]')).toHaveText(
    'Conexão PABX não configurada nesta conta.'
  );
  expect(admin.provider.configured).toBe(false);
  expect(admin.native_links.pabx_settings).toBe(false);
  await expect(
    root.locator('[data-native-pabx-protected-settings]')
  ).toHaveCount(0);
  const counts = {
    queues: health.queues.active,
    memberships: health.queues.memberships,
    events: Object.values(health.events.statuses).reduce(
      (sum, count) => sum + count,
      0
    ),
    commands: Object.values(health.commands.statuses).reduce(
      (sum, count) => sum + count,
      0
    ),
  };
  await Promise.all(
    Object.entries(counts).map(([key, value]) =>
      expect(root.locator(`[data-native-pabx-count="${key}"] dd`)).toHaveText(
        String(value)
      )
    )
  );
  await expect(root.locator('[data-native-pabx-observed-at]')).toHaveAttribute(
    'datetime',
    new Date(health.observed_at).toISOString()
  );
  const resourceKeys = (
    await root
      .locator('[data-native-pabx-resource]')
      .evaluateAll(nodes =>
        nodes.map(node => node.getAttribute('data-native-pabx-resource'))
      )
  ).sort();
  expect(resourceKeys).toEqual(
    ['extensions', 'queues', 'ivr', 'recordings']
      .filter(key => admin.cards.some(card => card.key === key))
      .sort()
  );
  const theme = await page.evaluate(() =>
    document.documentElement.classList.contains('dark')
  );
  expect(theme).toBe(info.project.name.endsWith('dark'));
  const measured = await measureLocatorTextContrast(
    root.getByRole('heading', {
      name: 'Configurações do PABX JRC',
      exact: true,
    })
  );
  expect(measured.ratio).toBeGreaterThanOrEqual(4.5);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  const initialActor = await page.evaluate(() =>
    Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
  );
  const captures = [];
  const capture = async stage => {
    const path = `.codex/call-center-native-e2e/${info.project.name}-pabx-native-${stage}.png`;
    await page.screenshot({ path, fullPage: true });
    captures.push({
      path,
      sha256: createHash('sha256').update(fs.readFileSync(path)).digest('hex'),
    });
  };
  await capture('general');
  const nav = root.getByRole('navigation', {
    name: 'Seções do PABX',
    exact: true,
  });
  await nav.getByRole('button', { name: 'Sincronização', exact: true }).click();
  await expect(page).toHaveURL(/preserved=native-proof.*pabx_tab=sync/);
  await expect(root).toContainText('Esta tela consulta registros existentes.');
  if (admin.provider.last_sync_at)
    await expect(root.locator('[data-native-pabx-last-sync]')).toHaveText(
      new Date(admin.provider.last_sync_at).toISOString()
    );
  else await expect(root).toContainText('Não registrada');
  await capture('sync');
  await nav.getByRole('button', { name: 'Diagnóstico', exact: true }).click();
  await expect(root.locator('[data-native-pabx-unverified]')).toContainText(
    `Eventos sem assinatura verificada: ${health.events.unverified}.`
  );
  await expect(root.locator('[data-native-pabx-boundary]')).toContainText(
    'A homologação externa permanece pendente.'
  );
  await expect(
    root.getByRole('button', {
      name: /Testar conexão|Sincronizar|Executar diagnóstico/,
    })
  ).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth
    )
  ).toBe(true);
  await capture('diagnostic');
  await root.locator('[data-native-pabx-resource="queues"]').click();
  await expect(page.locator('[data-administration-section] h2')).toHaveText(
    'Filas'
  );
  expect(new URL(page.url()).searchParams.get('preserved')).toBe(
    'native-proof'
  );
  await page.goBack();
  await expect(
    root.locator('[data-native-pabx-observations] [role="alert"]')
  ).toHaveCount(0);
  await expect(root.locator('[data-native-pabx-unverified]')).toBeVisible();
  await page.reload();
  await expect(root.locator('[data-native-pabx-unverified]')).toBeVisible();
  await page.evaluate(
    auth =>
      Object.assign(Reflect.get(window, 'axios').defaults.headers.common, auth),
    session.restricted
  );
  const unitSource = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === api + '/integrations/health' &&
      response.request().method() === 'GET'
  );
  const unitActor = await page.evaluate(() =>
    Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
  );
  expect(unitActor.user_id).not.toBe(initialActor.user_id);
  const unitResponse = await unitSource;
  expect(unitResponse.status()).toBe(200);
  const unitBytes = await unitResponse.body();
  const unitHealth = JSON.parse(unitBytes.toString());
  expect(unitHealth.account_id).toBe(String(session.account_id));
  const unitCounts = {
    queues: unitHealth.queues.active,
    memberships: unitHealth.queues.memberships,
    events: Object.values(unitHealth.events.statuses).reduce(
      (sum, count) => sum + count,
      0
    ),
    commands: Object.values(unitHealth.commands.statuses).reduce(
      (sum, count) => sum + count,
      0
    ),
  };
  expect(unitCounts.queues).toBeLessThan(counts.queues);
  await Promise.all(
    Object.entries(unitCounts).map(([key, value]) =>
      expect(root.locator(`[data-native-pabx-count="${key}"] dd`)).toHaveText(
        String(value)
      )
    )
  );
  await capture('unit-scope');
  await page.evaluate(
    auth =>
      Object.assign(Reflect.get(window, 'axios').defaults.headers.common, auth),
    session.viewer
  );
  const deniedSource = page.waitForResponse(
    response =>
      new URL(response.url()).pathname === api + '/integrations/health' &&
      response.request().method() === 'GET'
  );
  const changedActor = await page.evaluate(() =>
    Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
  );
  expect(changedActor.user_id).not.toBe(initialActor.user_id);
  const profileDenied = await deniedSource;
  expect(profileDenied.status()).toBe(401);
  await expect(root.locator('[data-native-pabx-count]')).toHaveCount(0);
  await expect(root.locator('[data-native-pabx-resource]')).toHaveCount(0);
  await expect(
    root.locator('[data-native-pabx-observations] [role="alert"]')
  ).toHaveText('Seu acesso atual não permite consultar esta fonte.');
  const nativeNavigation = page.locator('[data-contact-center-navigation]');
  await Promise.all(
    ['pabx', 'supervisor', 'configuracoes'].map(suffix =>
      expect(
        nativeNavigation.locator(`a[href$="/contact-center/${suffix}"]`)
      ).toHaveCount(0)
    )
  );
  if (info.project.name.startsWith('mobile')) {
    const toggle = page.locator(
      '[data-native-contact-center-layout] > header button[aria-expanded]'
    );
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    await expect(nativeNavigation).toBeVisible();
    await expect(
      nativeNavigation.locator('a[href$="/contact-center/pabx"]')
    ).toHaveCount(0);
  }
  await capture('profile-denied');
  await page.evaluate(
    auth =>
      Object.assign(Reflect.get(window, 'axios').defaults.headers.common, auth),
    session.administrator
  );
  const restoredActor = await page.evaluate(() =>
    Reflect.get(window, '__REFRESH_CC_NATIVE_ACTOR__')()
  );
  expect(restoredActor.user_id).toBe(initialActor.user_id);
  await expect(root.locator('[data-native-pabx-count]')).toHaveCount(4);
  await expect(
    nativeNavigation.locator('a[href$="/contact-center/pabx"]')
  ).toHaveCount(1);
  const healthUrl = 'http://127.0.0.1:5387' + api + '/integrations/health';
  const denied = await page.request.get(healthUrl, { headers: session.viewer });
  expect(denied.status()).toBe(401);
  const foreign = await page.request.get(
    healthUrl.replace(
      `/accounts/${session.account_id}/`,
      `/accounts/${session.other_account_id}/`
    ),
    { headers: session.administrator }
  );
  expect(foreign.status()).toBe(401);
  expect(writes).toEqual([]);
  page.off('request', onRequest);
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-pabx-native-readiness.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        synthetic: true,
        account_id: String(session.account_id),
        native_health_sha256: createHash('sha256')
          .update(healthBytes)
          .digest('hex'),
        counts,
        observed_at: new Date(health.observed_at).toISOString(),
        native_provider_configured: admin.provider.configured,
        resources: resourceKeys,
        stored_sync_at: admin.provider.last_sync_at,
        unverified: health.events.unverified,
        actual_dark_theme: theme,
        contrast: measured,
        horizontal_overflow: false,
        native_queue_navigation: true,
        query_and_reload_preserved: true,
        denied_status: denied.status(),
        foreign_status: foreign.status(),
        protected_settings_absent: true,
        unit_scope_revalidated_against_native_API: true,
        unit_scoped_counts: unitCounts,
        unit_scoped_health_sha256: createHash('sha256')
          .update(unitBytes)
          .digest('hex'),
        profile_changed_through_real_native_API: true,
        old_authorized_counts_cleared: true,
        profile_denied_http: profileDenied.status(),
        native_actor_restored: true,
        native_navigation_reauthorized_after_profile_change: true,
        native_navigation_restored_from_current_API: true,
        mobile_native_menu_checked_after_profile_denial:
          info.project.name.startsWith('mobile'),
        browser_writes: writes,
        screenshots: captures,
        provider_operation_or_external_homologation: false,
        whole_figure_or_Part1_accepted: false,
      },
      null,
      2
    ) + '\n'
  );
}
