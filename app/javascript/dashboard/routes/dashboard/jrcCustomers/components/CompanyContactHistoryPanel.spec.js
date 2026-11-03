import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Panel from './CompanyContactHistoryPanel.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  contactCompanyHistory: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value,
  }),
}));
const response = name => ({
  data: {
    payload: [
      {
        id: 1,
        at: '2026-11-03',
        kind: 'customer_contact_linked',
        from: { restricted: true },
        to: { company_name: name, company_role: 'finance' },
      },
    ],
    meta: { page: 1, per_page: 25, total: 26 },
  },
});
const render = () => mount(Panel, { props: { contactId: 42 } });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'agent' });
  mocks.contactCompanyHistory.mockResolvedValue(
    response('MOCK — Empresa permitida')
  );
});

it('does not describe the person as an active company link after unlinking', async () => {
  const data = response('MOCK — Empresa permitida');
  data.data.payload[0].from = {
    company_id: 7,
    company_name: 'MOCK — Empresa permitida',
    company_contact_status: 'active',
  };
  data.data.payload[0].to = {
    company_id: null,
    company_contact_status: 'active',
  };
  mocks.contactCompanyHistory.mockResolvedValue(data);
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Sem empresa vinculada');
  expect(wrapper.text().match(/Ativo/g)).toHaveLength(1);
  wrapper.unmount();
});

it('uses server paging and the canonical contact while displaying only the safe link context', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Empresa fora do seu acesso atual');
  expect(wrapper.text()).toContain('MOCK — Empresa permitida');
  expect(mocks.contactCompanyHistory).toHaveBeenCalledWith(
    42,
    { page: 1 },
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  await wrapper.findAll('button').at(-1).trigger('click');
  await flushPromises();
  expect(mocks.contactCompanyHistory).toHaveBeenLastCalledWith(
    42,
    { page: 2 },
    expect.objectContaining({ accountId: 1 })
  );
  wrapper.unmount();
});

it('clears old results and rejects a late prior-account response after a role or account change', async () => {
  let finish;
  mocks.contactCompanyHistory.mockReturnValueOnce(
    new Promise(resolve => {
      finish = resolve;
    })
  );
  const wrapper = render();
  mocks.state.account = 2;
  await flushPromises();
  finish(response('MOCK — PRIVATE_OLD_COMPANY'));
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_COMPANY');
  expect(mocks.contactCompanyHistory).toHaveBeenLastCalledWith(
    42,
    { page: 1 },
    expect.objectContaining({ accountId: 2 })
  );
  mocks.contactCompanyHistory.mockRejectedValueOnce({
    response: { status: 403 },
  });
  mocks.state.role = 'revoked';
  await flushPromises();
  expect(wrapper.text()).not.toContain('Empresa permitida');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.findAll('article')).toHaveLength(0);
  wrapper.unmount();
});
