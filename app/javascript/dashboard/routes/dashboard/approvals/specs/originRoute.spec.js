import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { expect, it, vi } from 'vitest';
import crm from 'dashboard/routes/dashboard/crm/crm.routes';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import { approvalOriginRoute } from '../originRoute';
import Origin from '../ApprovalOriginLink.vue';
vi.mock('dashboard/store', () => ({
  default: {
    dispatch: vi.fn(),
    getters: {
      getCurrentUser: { accounts: [] },
      getCurrentAccount: {},
      'accounts/isFeatureEnabledonAccount': () => true,
    },
  },
}));
it.each([
  ['JrcCrm::Deal', 'crm_deals', 'dealId'],
  ['JrcCrm::Proposal', 'crm_proposals', 'proposalId'],
  ['JrcCrm::SalesOrder', 'crm_orders', 'orderId'],
  ['JrcCrm::Contract', 'crm_contracts', 'contractId'],
])(
  'uses the real native route for %s and an explicit current account',
  (resource_type, name, query) => {
    const result = approvalOriginRoute(17, {
      resource_type,
      resource_id: 99,
      origin: { url: 'https://untrusted.example/PRIVATE' },
    });
    expect(result).toEqual({
      name,
      params: { accountId: '17' },
      query: { [query]: '99' },
    });
    const collect = rows =>
      rows.flatMap(row => [row.name, ...collect(row.children || [])]);
    expect(collect(crm.routes)).toContain(name);
  }
);
it('uses the native standalone Backoffice route with its request parameter, preserving the current account', () => {
  expect(
    approvalOriginRoute(17, {
      resource_type: 'JrcCrm::BackofficeRequest',
      resource_id: 9,
    })
  ).toEqual({
    name: 'crm_backoffice_request',
    params: { accountId: '17', requestId: '9' },
  });
  expect(
    crm.routes.find(row => row.name === 'crm_backoffice_request').path
  ).toContain('/backoffice/requests/:requestId');
});
it.each([0, -1, '1e2', [], {}, 1.5, 'https://untrusted.example'])(
  'does not turn malformed account %s into a source grant',
  account => {
    expect(
      approvalOriginRoute(account, {
        resource_type: 'JrcCrm::Contract',
        resource_id: 99,
      })
    ).toBeNull();
  }
);
it('rejects foreign-account records, unknown resource types and unbounded or malformed source identifiers', () => {
  expect(
    approvalOriginRoute(17, {
      account_id: 18,
      resource_type: 'JrcCrm::Contract',
      resource_id: 99,
    })
  ).toBeNull();
  expect(
    approvalOriginRoute(17, { resource_type: 'toString', resource_id: 99 })
  ).toBeNull();
  expect(
    approvalOriginRoute(17, {
      resource_type: 'JrcCrm::Contract',
      resource_id: ['99'],
    })
  ).toBeNull();
  expect(
    approvalOriginRoute(17, {
      resource_type: 'JrcCrm::Contract',
      resource_id: '9007199254740992',
    })
  ).toBeNull();
});
it('keeps legal authority navigation in its sealed Central context instead of granting Backoffice browsing', async () => {
  const wrapper = mount(Origin, {
    props: {
      accountId: 17,
      request: {
        resource_type: 'JrcBackoffice::AuthorityProposal',
        resource_id: 9,
        origin: { kind: 'contract_authority' },
      },
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
      ],
    },
  });
  expect(wrapper.find('a').exists()).toBe(false);
  await wrapper.get('button').trigger('click');
  expect(wrapper.emitted('authority')).toHaveLength(1);
  wrapper.unmount();
});
