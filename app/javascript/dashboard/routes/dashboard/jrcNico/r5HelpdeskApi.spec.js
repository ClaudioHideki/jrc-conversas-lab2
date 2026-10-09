import { beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcNicoHelpdesk';
const http = { get: vi.fn(), post: vi.fn() };
beforeEach(() => {
  vi.stubGlobal('axios', http);
});
describe('R5 native authenticated HelpDesk API', () => {
  it('uses scoped native GETs for report history and detail, with no outbound endpoint', () => {
    API.reports(12, 8, 2);
    API.reportHistory(12, 91);
    expect(http.get).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/12/jrc_nico/helpdesk/reports',
      { params: { policy_id: 8, page: 2 } }
    );
    expect(http.get).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/12/jrc_nico/helpdesk/reports/91'
    );
    expect(http.post).not.toHaveBeenCalled();
  });
  it('passes the exact current preview input and digest to native approval preparation', () => {
    const input = {
      event_id: 8,
      group_key: 'D2',
      input: { summary: 'Reviewed native evidence' },
    };
    const prepare = {
      ...input,
      tool: 'add_service_ticket_note',
      arguments: { ticket_id: 21, body: 'Exact preview' },
      preview_digest: 'a'.repeat(64),
    };
    API.groupPreview(12, input);
    API.groupPrepare(12, prepare);
    expect(http.post).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/12/jrc_nico/helpdesk/group_preview',
      input
    );
    expect(http.post).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/12/jrc_nico/helpdesk/group_prepare',
      prepare
    );
    expect(http.get).not.toHaveBeenCalled();
  });

  it('uses native filter arrays and explicit KPI interval without broadening or copying credentials', () => {
    const filters = {
      unit_ids: [3],
      company_ids: [4],
      assignee_account_user_ids: [7],
    };
    API.kpis(12, 8, '2026-10-07T00:00:00Z', {
      until: '2026-10-08T18:00:00Z',
      filters,
    });
    API.report(12, 8, filters);
    expect(http.get).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/12/jrc_nico/helpdesk/kpis',
      {
        params: {
          policy_id: 8,
          from: '2026-10-07T00:00:00Z',
          until: '2026-10-08T18:00:00Z',
          filters,
        },
      }
    );
    expect(http.get).toHaveBeenNthCalledWith(
      2,
      '/api/v1/accounts/12/jrc_nico/helpdesk/report',
      { params: { policy_id: 8, filters } }
    );
    expect(http.post).not.toHaveBeenCalled();
  });
});
