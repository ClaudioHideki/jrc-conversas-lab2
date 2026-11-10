import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Directory from './SegmentDirectory.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  taxonomies: vi.fn(),
  getCustomViewsByFilterType: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('dashboard/api/customViews', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.admin}`),
    canAdmin: computed(() => mocks.state.admin),
    accountScopedRoute: name => ({ name }),
  }),
}));
const result = name => ({
  data: {
    payload: [{ id: 1, name, active: true, selection_mode: 'classification' }],
    meta: { page: 1, per_page: 25, total: 26 },
  },
});
const render = () =>
  mount(Directory, {
    global: {
      stubs: {
        RouterLink: { template: '<a><slot /></a>' },
        SegmentDialog: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, admin: true });
  mocks.taxonomies.mockResolvedValue(result('MOCK — Empresas'));
  mocks.getCustomViewsByFilterType.mockResolvedValue({
    data: [{ id: 7, name: 'MOCK — Filtro pessoal' }],
  });
});
it('preserves personal filters and pins both requests to the account with cancellation', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('MOCK — Empresas');
  expect(wrapper.text()).toContain('MOCK — Filtro pessoal');
  expect(mocks.getCustomViewsByFilterType).toHaveBeenCalledWith(
    'contact',
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.taxonomies).toHaveBeenLastCalledWith(
    { kind: 'segment', page: 2 },
    expect.objectContaining({ accountId: 1 })
  );
  wrapper.unmount();
});
it('clears old data and rejects late results after the account changes', async () => {
  let finish;
  mocks.taxonomies.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await flushPromises();
  mocks.state.account = 2;
  await flushPromises();
  finish(result('MOCK — Não mostrar conta anterior'));
  await flushPromises();
  expect(wrapper.text()).not.toContain('Não mostrar conta anterior');
  expect(mocks.taxonomies).toHaveBeenLastCalledWith(
    expect.anything(),
    expect.objectContaining({ accountId: 2 })
  );
  wrapper.unmount();
});
it('removes creation controls after native administrator permission is withdrawn', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Novo segmento');
  mocks.state.admin = false;
  await flushPromises();
  expect(wrapper.text()).not.toContain('Novo segmento');
  wrapper.unmount();
});
