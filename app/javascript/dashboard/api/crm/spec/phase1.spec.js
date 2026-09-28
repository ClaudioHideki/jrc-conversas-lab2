import leadsAPI from '../leads';
import managementAPI from '../management';

describe('Phase 1 CRM API contracts', () => {
  const originalAxios = window.axios;
  beforeEach(() => {
    window.axios = { get: vi.fn(), post: vi.fn() };
    window.history.replaceState({}, '', '/app/accounts/17/contacts');
  });
  afterEach(() => {
    window.axios = originalAxios;
    window.history.replaceState({}, '', '/');
  });
  it('looks up and creates a lead for the selected contact in the current account', () => {
    leadsAPI.forContact(42);
    leadsAPI.fromContact(42);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/crm/leads/for_contact',
      { params: { contact_id: 42 } }
    );
    expect(window.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/17/crm/leads/from_contact',
      { contact_id: 42 }
    );
  });
  it('passes the metrics date filters to the existing account-scoped resource', () => {
    managementAPI.list({ start_date: '2026-09-01' });
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/crm/management',
      { params: { start_date: '2026-09-01' } }
    );
  });
});
