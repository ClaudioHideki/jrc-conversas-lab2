import { beforeEach, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcRelationship';
beforeEach(() => {
  global.axios = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
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
