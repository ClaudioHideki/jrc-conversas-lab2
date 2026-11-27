import { expect } from '@playwright/test';
import fs from 'node:fs';
import { measureLocatorTextContrast } from './call-center-text-contrast.mjs';

// Existing native lists and timeline, actual customer APIs and owned seeded data.
export async function verifyNativeCustomerRecords(page, info, target, ticket) {
  const account = String(target.account_id);
  const context = target.customer_records_context;
  const contact = String(context.contact_id);
  const base = `/api/v1/accounts/${account}/customers/contacts/${contact}`;
  const screenshots = [];
  const waitFor = (endpoint, kind, number) =>
    page.waitForResponse(response => {
      const url = new URL(response.url());
      return (
        response.request().method() === 'GET' &&
        url.pathname === endpoint &&
        (!kind || url.searchParams.get('kind') === kind) &&
        (!number || url.searchParams.get('page') === String(number))
      );
    });
  const capture = async name => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth
      )
    ).toBe(true);
    const path = `.codex/call-center-native-e2e/${info.project.name}-customer-context-${name}.png`;
    await page.screenshot({ path, fullPage: true });
    screenshots.push(path);
  };
  await page.locator('[data-recording-context-open]').click();
  const host = page.locator('[data-recording-customer-records]');
  await expect(host).toBeVisible();
  const overviewResponse = waitFor(base + '/overview');
  const firstResponse = waitFor(base + '/records', 'deals', 1);
  await host.locator('[data-load-customer-records]').click();
  const overview = await overviewResponse;
  expect(overview.status()).toBe(200);
  const capabilities = (await overview.json()).capabilities;
  expect(capabilities.crm).toBe(true);
  expect(capabilities.service_desk).toBe(true);
  const first = await firstResponse;
  expect(first.status()).toBe(200);
  const page1 = await first.json();
  expect(page1.meta).toMatchObject({ page: 1, per_page: 25, total: 26 });
  expect(page1.payload).toHaveLength(25);
  const native = host.locator('[data-native-customer-records]');
  await expect(native.getByRole('link')).toHaveCount(25);
  await expect(native).not.toContainText(context.private_title);
  const contrast = await measureLocatorTextContrast(host.getByRole('heading'));
  expect(contrast.ratio).toBeGreaterThanOrEqual(4.5);
  const link = native.getByRole('link').first();
  const href = await link.getAttribute('href');
  expect(href).toContain(`/app/accounts/${account}/crm/deals`);
  expect(href).toContain('dealId=');
  await capture('native-crm-page-one');
  const nextResponse = waitFor(base + '/records', 'deals', 2);
  await native.getByRole('button').last().click();
  const next = await nextResponse;
  expect(next.status()).toBe(200);
  const page2 = await next.json();
  expect(page2.meta).toMatchObject({ page: 2, per_page: 25, total: 26 });
  expect(page2.payload).toHaveLength(1);
  await expect(native.getByRole('link')).toHaveCount(1);
  const ids = [...page1.payload, ...page2.payload].map(row => String(row.id));
  expect(ids).toHaveLength(26);
  expect(new Set(ids).size).toBe(26);
  expect([...ids].sort()).toEqual([...context.deal_ids].sort());
  expect(ids).not.toContain(context.private_deal_id);
  const contractResponse = waitFor(base + '/records', 'contracts', 1);
  await host.locator('[data-customer-records-tab="contracts"]').click();
  const contracts = await contractResponse;
  expect(contracts.status()).toBe(200);
  const empty = await contracts.json();
  expect(empty.payload).toEqual([]);
  expect(empty.meta.total).toBe(0);
  await expect(native.getByRole('link')).toHaveCount(0);
  await expect(native.getByRole('alert')).toHaveCount(0);
  await capture('real-empty-native-contracts');
  expect(capabilities.projects).toBe(true);
  const projectsResponse = waitFor(base + '/records', 'projects', 1);
  await host.locator('[data-customer-records-tab="projects"]').click();
  const projects = await projectsResponse;
  expect(projects.status()).toBe(200);
  const projectPage = await projects.json();
  expect(projectPage.payload.map(row => String(row.id))).toEqual([
    context.project_id,
  ]);
  await expect(
    native.getByRole('link').filter({ hasText: context.project_title })
  ).toBeVisible();
  await expect(native).not.toContainText(context.private_project_title);
  expect(projectPage.payload.map(row => String(row.id))).not.toContain(
    context.private_project_id
  );
  await capture('native-authorized-private-project');
  const ticketResponse = waitFor(base + '/records', 'tickets', 1);
  await host.locator('[data-customer-records-tab="tickets"]').click();
  const tickets = await ticketResponse;
  expect(tickets.status()).toBe(200);
  const ticketPage = await tickets.json();
  expect(ticketPage.payload.map(row => String(row.id))).toContain(
    String(ticket.id)
  );
  await expect(
    native.getByRole('link').filter({ hasText: ticket.title })
  ).toBeVisible();
  await capture('persisted-native-service-desk-ticket');
  const historyResponse = waitFor(base + '/timeline');
  await host.locator('[data-customer-records-tab="history"]').click();
  const timeline = await historyResponse;
  expect(timeline.status()).toBe(200);
  const history = await timeline.json();
  expect(
    history.payload.some(
      row =>
        row.source === 'ticket_event' &&
        String(row.ticket_id) === String(ticket.id)
    )
  ).toBe(true);
  await expect(native).toContainText('Chamado criado');
  await capture('native-unified-timeline');
  const denied = await page.request.get(base + '/overview', {
    headers: target.scoped,
  });
  expect(denied.status()).toBe(401);
  expect(await denied.text()).not.toContain(context.private_title);
  const actualDark = await page.evaluate(() =>
    document.documentElement.classList.contains('dark')
  );
  expect(actualDark).toBe(info.project.name.endsWith('dark'));
  fs.writeFileSync(
    `.codex/call-center-native-e2e/${info.project.name}-customer-native-records.json`,
    JSON.stringify(
      {
        sha: process.env.GITHUB_SHA,
        project: info.project.name,
        account_id: account,
        contact_id: contact,
        synthetic: true,
        actual_dark_theme: actualDark,
        actual_native_capabilities: capabilities,
        native_CRM_ids: ids,
        native_private_other_owner_omitted: true,
        actual_first_page: page1.meta,
        actual_second_page: page2.meta,
        real_empty_contracts_total: empty.meta.total,
        native_project_ids: projectPage.payload.map(row => String(row.id)),
        private_project_omitted: true,
        created_native_ticket_id: String(ticket.id),
        native_ticket_ids: ticketPage.payload.map(row => String(row.id)),
        actual_native_timeline: history.payload.map(
          ({ source, id, ticket_id: ticketId }) => ({
            source,
            id,
            ticket_id: ticketId,
          })
        ),
        denied_directory_status: denied.status(),
        native_CRM_link_href: href,
        contrast,
        screenshots,
        no_provider_command: true,
        existing_native_panel_status_labels_and_full_CRM_destination_navigation_still_need_review: true,
        whole_figure_or_Part1_accepted: false,
      },
      null,
      2
    ) + '\n'
  );
  await page.locator('[data-recording-actions-open]').click();
  await expect(
    page
      .locator('[data-recording-linked-tickets]')
      .getByRole('link')
      .filter({ hasText: ticket.title })
  ).toBeVisible();
}
