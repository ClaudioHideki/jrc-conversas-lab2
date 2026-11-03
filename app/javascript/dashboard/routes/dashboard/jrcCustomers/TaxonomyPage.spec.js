import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Groups from './TaxonomyPage.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  economicGroups: vi.fn(),
  getForAccount: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('dashboard/api/labels', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.admin}`),
    canAdmin: computed(() => mocks.state.admin),
    accountScopedRoute: name => ({ name }),
  }),
}));
const response = name => ({
  data: {
    payload: [{ id: 7, name, member_count: 1 }],
    meta: { total: 26, per_page: 25 },
  },
});
const render = () =>
  mount(Groups, {
    global: {
      stubs: {
        RouterLink: { template: '<a><slot /></a>' },
        EconomicGroupDialog: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, admin: true });
  mocks.economicGroups.mockResolvedValue(response('MOCK — Conglomerado'));
  mocks.getForAccount.mockResolvedValue({
    data: { payload: [{ id: 8, title: 'MOCK — VIP' }] },
  });
});

it('keeps native contact labels in a separate tab with an account-bound native API call', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('MOCK — Conglomerado');
  expect(mocks.getForAccount).not.toHaveBeenCalled();
  await wrapper.findAll('nav button')[1].trigger('click');
  await flushPromises();
  expect(mocks.getForAccount).toHaveBeenCalledWith(1, {
    signal: expect.any(AbortSignal),
  });
  expect(wrapper.text()).toContain('MOCK — VIP');
  expect(wrapper.text()).not.toContain('MOCK — Conglomerado');
  wrapper.unmount();
});

it('uses bounded server pages and does not let late requests expose the previous account catalog', async () => {
  let resolveOld;
  mocks.economicGroups.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  mocks.state.account = 2;
  await flushPromises();
  resolveOld(response('PRIVATE_OLD_ACCOUNT'));
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_ACCOUNT');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.economicGroups).toHaveBeenLastCalledWith(
    { q: '', page: 2 },
    expect.objectContaining({ accountId: 2 })
  );
  wrapper.unmount();
});
