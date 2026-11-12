import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import OperationalContactsPage from './OperationalContactsPage.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  operationalContacts: vi.fn(),
  taxonomies: vi.fn(),
  taxonomy: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value || '—',
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId: mocks.state.account, ...params },
      query,
    }),
  }),
}));
const person = {
  id: 101,
  name: 'MOCK Operational person',
  company_id: 201,
  company_name: 'MOCK Company',
  operational_status: 'in_service',
  last_interaction_at: null,
  context: {
    kind: 'conversation',
    record_id: 301,
    display_id: 45,
    channel_name: 'MOCK WhatsApp',
    responsible: { id: 1, name: 'MOCK owner' },
  },
  next_action: {
    kind: 'activity',
    record_id: 401,
    title: 'MOCK next action',
    due_at: '2026-11-03',
    responsible: { id: 1, name: 'MOCK owner' },
  },
};
const response = (rows = [person]) => ({
  data: { payload: rows, meta: { page: 1, per_page: 25, total: 51, days: 30 } },
});
let router;
const render = async (query = {}) => {
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        name: 'jrc_customer_operational_contacts',
        path: '/app/accounts/:accountId/customers/active-contacts',
        component: OperationalContactsPage,
      },
      {
        name: 'inbox_conversation',
        path: '/app/accounts/:accountId/conversations/:conversation_id',
        component: { template: '<div />' },
      },
      {
        name: 'crm_activities',
        path: '/app/accounts/:accountId/crm/activities',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push({
    name: 'jrc_customer_operational_contacts',
    params: { accountId: '1' },
    query,
  });
  return mount(OperationalContactsPage, {
    global: {
      plugins: [router],
      stubs: {
        ContactDetailsDialog: true,
        CompanyDetailsDialog: true,
        OperationalContactActions: true,
        SegmentFilterPicker: true,
      },
    },
  });
};
const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'admin:1' });
  mocks.operationalContacts.mockResolvedValue(response());
});

it('presents canonical popups, authorized source links and a truthful missing interaction without duplicating the registry', async () => {
  const wrapper = await render();
  await flushPromises();
  expect(wrapper.text()).toContain(
    'Sem interação registrada nas fontes autorizadas'
  );
  expect(
    wrapper.find('a[href="/app/accounts/1/conversations/45"]').exists()
  ).toBe(true);
  expect(
    wrapper
      .find('a[href="/app/accounts/1/crm/activities?activityId=401"]')
      .exists()
  ).toBe(true);
  await button(wrapper, person.name).trigger('click');
  expect(
    wrapper.findComponent({ name: 'ContactDetailsDialog' }).props('contactId')
  ).toBe(101);
  await button(wrapper, person.company_name).trigger('click');
  expect(
    wrapper.findComponent({ name: 'CompanyDetailsDialog' }).props('companyId')
  ).toBe(201);
  wrapper.findComponent({ name: 'ContactDetailsDialog' }).vm.$emit('updated');
  await flushPromises();
  expect(mocks.operationalContacts).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});

it('applies configurable window, source and status through the URL, retaining unrelated origin parameters', async () => {
  const wrapper = await render({ page: '2', source: 'customer360' });
  await flushPromises();
  await wrapper.find('input[type="number"]').setValue('60');
  await wrapper.findAll('select')[0].setValue('waiting');
  await wrapper.findAll('select')[1].setValue('ticket');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(router.currentRoute.value.query).toMatchObject({
    page: '1',
    source: 'customer360',
    days: '60',
    status: 'waiting',
    kind: 'ticket',
  });
  expect(mocks.operationalContacts).toHaveBeenLastCalledWith(
    expect.objectContaining({
      page: 1,
      days: '60',
      status: 'waiting',
      kind: 'ticket',
    }),
    expect.objectContaining({ accountId: 1 })
  );
  wrapper.unmount();
});

it('uses real server totals for next/previous and restores the first page when filters change', async () => {
  const wrapper = await render();
  await flushPromises();
  expect(button(wrapper, 'Anterior').attributes('disabled')).toBeDefined();
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.query.page).toBe('2');
  expect(mocks.operationalContacts).toHaveBeenLastCalledWith(
    expect.objectContaining({ page: 2 }),
    expect.any(Object)
  );
  await button(wrapper, 'Anterior').trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.query.page).toBe('1');
  wrapper.unmount();
});

it('aborts previous-account requests, ignores late data and closes current popups on a permission change', async () => {
  let finish;
  mocks.operationalContacts.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = await render();
  await flushPromises();
  const oldSignal = mocks.operationalContacts.mock.calls[0][1].signal;
  mocks.state.account = 2;
  mocks.operationalContacts.mockResolvedValue(
    response([{ ...person, id: 102, name: 'MOCK Account 2 person' }])
  );
  await flushPromises();
  finish(response());
  await flushPromises();
  expect(oldSignal.aborted).toBe(true);
  expect(wrapper.text()).toContain('MOCK Account 2 person');
  expect(wrapper.text()).not.toContain('MOCK Operational person');
  await button(wrapper, 'MOCK Account 2 person').trigger('click');
  mocks.state.role = 'restricted';
  mocks.operationalContacts.mockRejectedValue({
    response: { status: 401, data: { error: 'Denied' } },
  });
  await flushPromises();
  expect(wrapper.findComponent({ name: 'ContactDetailsDialog' }).exists()).toBe(
    false
  );
  expect(wrapper.findAll('article')).toHaveLength(0);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});

it('clears stale rows and shows a genuine empty result without an invented active state', async () => {
  mocks.operationalContacts.mockResolvedValue({
    data: { payload: [], meta: { total: 0, per_page: 25, days: 30 } },
  });
  const wrapper = await render();
  await flushPromises();
  expect(wrapper.text()).toContain('Nenhum contato em movimento');
  expect(button(wrapper, 'Próxima').attributes('disabled')).toBeDefined();
  expect(wrapper.findAll('article')).toHaveLength(0);
  wrapper.unmount();
});
