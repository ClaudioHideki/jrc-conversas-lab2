import { beforeEach, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcRelationship';
beforeEach(() => {
  global.axios = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
});
it('pages the native book catalog and reads selected history with cancellable requests', () => {
  const signal = new AbortController().signal;
  API.playbooks(12, { params: { page: 5, per_page: 25 }, signal });
  API.playbookHistory(12, 18, { source_version: 1 }, { signal });
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/playbooks',
    { params: { page: 5, per_page: 25 }, signal }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/playbooks/18/history',
    { params: { source_version: 1 }, signal }
  );
});
it('binds every group operation to its explicit account without changing the native customer API', () => {
  const fields = {
    portfolio_group: { name: 'Reviewed' },
    expected_version: 3,
    reason: 'Reviewed change',
  };
  API.savePortfolioGroup(12, fields);
  API.savePortfolioGroup(12, fields, 18);
  API.savePortfolioGroupCustomers(12, 18, {
    assignment_ids: [31],
    active: false,
    expected_version: 3,
  });
  expect(global.axios.post).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups',
    fields
  );
  expect(global.axios.patch).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18',
    fields
  );
  expect(global.axios.patch).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/customers',
    { assignment_ids: [31], active: false, expected_version: 3 }
  );
});
it('preserves cancellation, filters and pagination for group and child reads', () => {
  const signal = new AbortController().signal;
  API.portfolioGroups(
    12,
    { page: 2, q: 'Coverage', status: 'active' },
    { signal }
  );
  API.portfolioGroup(12, 18, { signal });
  API.portfolioGroupWorkload(12, 18, { signal });
  API.portfolioGroupHistory(12, 18, { page: 2, kind: 'updated' }, { signal });
  API.exportPortfolioGroupHistory(12, 18, { from: '2026-11-01' }, { signal });
  API.portfolioGroupCustomers(12, 18, { page: 3 }, { signal });
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups',
    { signal, params: { page: 2, q: 'Coverage', status: 'active' } }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18',
    { signal }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/customers',
    { signal, params: { page: 3 } }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/workload',
    { signal }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/history',
    { signal, params: { page: 2, kind: 'updated' } }
  );
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/export_history',
    { signal, params: { from: '2026-11-01' } }
  );
});
it('rejects malformed account contexts before making any group request', () => {
  expect(() => API.portfolioGroups('12/other', {})).toThrow(
    'Invalid account context'
  );
  expect(() => API.savePortfolioGroup(0, {})).toThrow(
    'Invalid account context'
  );
  expect(() => API.portfolioGroupCustomers(-1, 18, {})).toThrow(
    'Invalid account context'
  );
  expect(global.axios.get).not.toHaveBeenCalled();
  expect(global.axios.post).not.toHaveBeenCalled();
});

it('binds a non-mutating selected-customer re-review to the explicit account and group with cancellation', () => {
  const signal = new AbortController().signal;
  API.portfolioGroupCustomerReview(
    12,
    18,
    { assignment_ids: [31] },
    { signal }
  );
  expect(global.axios.post).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/portfolio_groups/18/customer_review',
    { assignment_ids: [31] },
    { signal }
  );
});

it('binds restoration to the selected account and preserves its exact versioned body', () => {
  const fields = {
    scope_key: 'account',
    version: 3,
    source_version: 1,
    reason: 'Reviewed restore',
  };
  API.restoreConfiguration(12, fields);
  expect(global.axios.post).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/configuration/restore',
    fields,
    undefined
  );
});

it('keeps playbook restoration bound to its native account, ID and immutable source version', () => {
  const fields = {
    version: 3,
    source_version: 1,
    reason: 'Reviewed definition',
  };
  API.restorePlaybook(12, 18, fields);
  expect(global.axios.post).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/playbooks/18/restore',
    fields,
    undefined
  );
});
