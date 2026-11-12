import { describe, expect, it, vi } from 'vitest';
import { resolveMasterCustomer, applyMasterCustomer } from './masterCustomer';
import { createServiceDeskClient } from 'dashboard/api/serviceDeskClient';
const scope = { accountId: '1', userId: '7', unitId: '10', allowed: true };
const person = {
  id: 33,
  company_id: 80,
  name: 'Synthetic',
  requester_eligible: true,
};
it('resolves the canonical native requester with explicit account and chosen unit', async () => {
  const http = {
    get: vi.fn().mockResolvedValue({
      data: { contract_version: 1, account_id: '1', person },
    }),
  };
  const api = createServiceDeskClient(http);
  const signal = new AbortController().signal;
  const resolved = await resolveMasterCustomer(
    api,
    scope,
    { companyId: 80, contactId: 33 },
    signal
  );
  expect(http.get).toHaveBeenCalledWith(
    '/api/v1/accounts/1/jrc_service_desk/requester_people/33',
    { params: { unit_id: '10', company_id: '80' }, signal, timeout: 15000 }
  );
  expect(resolved).toMatchObject({
    account_id: '1',
    user_id: '7',
    unit_id: '10',
    company_id: '80',
    requester: { id: '33' },
  });
});
it('validates a company without silently choosing or linking a requester', async () => {
  const http = {
    get: vi.fn().mockResolvedValue({
      data: {
        contract_version: 1,
        account_id: '1',
        company: { id: 80 },
        items: [person],
      },
    }),
  };
  const value = await resolveMasterCustomer(
    createServiceDeskClient(http),
    scope,
    { companyId: 80 }
  );
  expect(value.requester).toBeNull();
  expect(http.get.mock.calls[0][1].params).toEqual({
    unit_id: '10',
    company_id: '80',
    per_page: 1,
  });
});
describe.each([
  { account_id: '2', person },
  { account_id: '1', person: { ...person, id: 34 } },
  { account_id: '1', person: { ...person, company_id: 81 } },
  { account_id: '1', person: { ...person, requester_eligible: false } },
])('untrusted result %j', result => {
  it('rejects foreign, mismatched or ineligible identities', async () => {
    await expect(
      resolveMasterCustomer(
        { requesterContext: async () => ({ contract_version: 1, ...result }) },
        scope,
        { companyId: 80, contactId: 33 }
      )
    ).rejects.toThrow();
  });
});
it('rejects malformed pointer parameters before any network call', async () => {
  const api = { requesterContext: vi.fn() };
  await expect(
    resolveMasterCustomer(api, scope, { companyId: ['80', '81'] })
  ).rejects.toThrow();
  expect(api.requesterContext).not.toHaveBeenCalled();
});
it.each([{ allowed: false }, { accountId: '2' }, { userId: '8' }])(
  'clears previous context and rejects stale scope %j',
  mismatch => {
    const value = {
      account_id: '1',
      user_id: '7',
      unit_id: '10',
      company_id: '80',
      requester: { id: '33' },
    };
    const draft = {
      unit_id: '10',
      company_id: '80',
      requester_id: '33',
      title: 'Keep manual title',
    };
    expect(
      applyMasterCustomer(draft, value, value, { ...scope, ...mismatch })
        .applied
    ).toBe(false);
    expect(draft).toEqual({
      unit_id: '10',
      company_id: null,
      requester_id: '',
      title: 'Keep manual title',
    });
  }
);
it('never applies a context verified for another unit or erases a manual replacement', () => {
  const value = {
    account_id: '1',
    user_id: '7',
    unit_id: '10',
    company_id: '80',
    requester: { id: '33' },
  };
  const draft = { unit_id: '11', company_id: '81', requester_id: '34' };
  expect(applyMasterCustomer(draft, value, value, scope).applied).toBe(false);
  expect(draft).toEqual({
    unit_id: '11',
    company_id: '81',
    requester_id: '34',
  });
});
