import { mount, flushPromises } from '@vue/test-utils';
import BackofficeView from '../backoffice/BackofficeView.vue';

const mocks = vi.hoisted(() => ({
  list: vi.fn(),
  show: vi.fn(),
  summary: vi.fn(),
  advance: vi.fn(),
  catalog: vi.fn(),
  push: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '1', section: 'implement' },
    query: { requestId: '7' },
  }),
  useRouter: () => ({ push: mocks.push, replace: vi.fn() }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentUser: { id: 1 } } }),
}));
vi.mock('dashboard/api/agents', () => ({ default: { get: mocks.catalog } }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeAPI: mocks,
  salesOrdersAPI: { list: mocks.catalog },
  invoicesAPI: { list: mocks.catalog },
  paymentsAPI: {},
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue', () => ({
  default: { template: '<div />' },
}));

it('keeps the selected request in the URL when advancing to another operational area', async () => {
  const row = {
    id: 7,
    request_number: 'BKO-7',
    stage: 'implementation',
    status: 'in_progress',
    priority: 'normal',
    metadata: {
      implementation_checklist: [{ label: 'Activation', done: true }],
    },
    order: { id: 1, order_number: 'PED-1', snapshot: {} },
    owner: { id: 1, name: 'Operator' },
  };
  mocks.list.mockImplementation(async () => ({ data: [{ ...row }] }));
  mocks.show.mockImplementation(async () => ({ data: { ...row } }));
  mocks.catalog.mockResolvedValue({ data: [] });
  mocks.summary.mockResolvedValue({ data: {} });
  mocks.advance.mockImplementation(async () => {
    row.stage = 'provisioning';
    return { data: { ...row } };
  });
  const wrapper = mount(BackofficeView, {
    global: { stubs: { RouterLink: true } },
  });
  await flushPromises();
  const button = wrapper
    .findAll('button')
    .find(item => item.text() === 'Validar dependências e avançar');
  await button.trigger('click');
  await flushPromises();
  expect(mocks.push).toHaveBeenLastCalledWith({
    name: 'crm_backoffice',
    params: { accountId: '1', section: 'provision' },
    query: { requestId: 7 },
  });
  wrapper.unmount();
});
