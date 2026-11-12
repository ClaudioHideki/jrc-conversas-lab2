import { computed, reactive } from 'vue';
import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import Panel from './BackofficeContextPanel.vue';

const mocks = vi.hoisted(() => ({ state: null, backoffice: vi.fn() }));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.accountId),
    identity: computed(() => `${mocks.state.accountId}:${mocks.state.viewer}`),
    date: value => value || '—',
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId: mocks.state.accountId, ...params },
      query,
    }),
  }),
}));
const row = {
  id: 42,
  request_number: 'BKO-MOCK-42',
  title: 'MOCK — Solicitação autorizada',
  stage: 'contract',
  status: 'in_progress',
  owner: { id: 3, name: 'MOCK — Analista' },
  order: { order_number: 'PED-MOCK' },
  updated_at: '2026-11-02T12:00:00Z',
};
const payload = {
  company_id: 9,
  data: [row],
  meta: { page: 1, pages: 2, total: 21 },
  summary: { total: 21, active: 21, overdue: 0, completed: 0 },
};
const render = () =>
  mount(Panel, {
    props: { companyId: 9 },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
const button = (wrapper, name) =>
  wrapper.findAll('button').find(item => item.text() === name);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ accountId: '1', viewer: 'agent:1' });
  mocks.backoffice.mockResolvedValue({ data: structuredClone(payload) });
});

it('loads only the selected company context and opens the exact native source tab', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.backoffice).toHaveBeenCalledWith(
    9,
    expect.objectContaining({ view: 'requests', page: 1, per_page: 20 }),
    expect.objectContaining({ accountId: '1' })
  );
  await button(wrapper, 'Documentação').trigger('click');
  await flushPromises();
  expect(mocks.backoffice.mock.calls.at(-1)[1].view).toBe('documents');
  expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
    name: 'crm_backoffice_request',
    params: { accountId: '1', requestId: 42 },
    query: { tab: 'documents' },
  });
  wrapper.unmount();
});

it('uses server pagination and resets its page when changing to safe historical facts', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.backoffice.mockResolvedValue({
    data: {
      ...structuredClone(payload),
      data: [{ ...row, id: 43 }],
      meta: { page: 2, pages: 2 },
    },
  });
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(mocks.backoffice.mock.calls.at(-1)[1].page).toBe(2);
  mocks.backoffice.mockResolvedValue({
    data: {
      company_id: 9,
      data: [
        {
          id: 901,
          request_id: 42,
          event_type: 'PRIVATE_UNKNOWN_EVENT',
          metadata: 'PRIVATE_CANARY',
        },
      ],
      meta: { page: 1, pages: 1, total: 1 },
    },
  });
  await button(wrapper, 'Histórico').trigger('click');
  await flushPromises();
  expect(mocks.backoffice.mock.calls.at(-1)[1]).toMatchObject({
    page: 1,
    view: 'history',
  });
  expect(wrapper.text()).toContain('Evento registrado');
  expect(wrapper.text()).not.toContain('PRIVATE');
  expect(
    wrapper.findComponent(RouterLinkStub).props('to').params.requestId
  ).toBe(42);
  expect(wrapper.findComponent(RouterLinkStub).props('to').query.tab).toBe(
    'history'
  );
  wrapper.unmount();
});

it('clears contextual rows and counts on denial rather than displaying an empty success', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.backoffice.mockRejectedValue({ response: { status: 403 } });
  mocks.state.viewer = 'revoked';
  await flushPromises();
  expect(wrapper.text()).not.toContain(row.request_number);
  expect(wrapper.find('[role="alert"]').text()).toContain(
    'Seu acesso ao Backoffice desta empresa não está disponível.'
  );
  expect(wrapper.text()).not.toContain(
    'Nenhum registro autorizado nesta visão.'
  );
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
  wrapper.unmount();
});

it('discards a late old-account response after context changes', async () => {
  let resolveOld;
  mocks.backoffice.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  mocks.backoffice.mockResolvedValue({
    data: { company_id: 9, data: [], meta: { page: 1, pages: 1, total: 0 } },
  });
  mocks.state.accountId = '2';
  await flushPromises();
  resolveOld({ data: structuredClone(payload) });
  await flushPromises();
  expect(wrapper.text()).not.toContain(row.request_number);
  expect(mocks.backoffice.mock.calls.at(-1)[2].accountId).toBe('2');
  expect(mocks.backoffice.mock.calls[0][2].signal.aborted).toBe(true);
  wrapper.unmount();
});
