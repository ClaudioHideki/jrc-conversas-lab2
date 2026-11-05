import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, reactive } from 'vue';
import Panel from './WithdrawalReadinessDialog.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  request: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { withdrawalReadiness: mocks.request },
}));
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
});
const render = () =>
  mount(Panel, { props: { analystId: 7 }, global: { stubs: { Dialog } } });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.getters = reactive({
    getCurrentUser: { id: 3 },
    getCurrentRole: 'administrator',
  });
  mocks.request.mockResolvedValue({
    data: {
      state: 'pending_responsibilities',
      counts: { allocations: 0, actions: 1 },
      final_removal_available: false,
    },
  });
});

it('shows actual pending counts without offering a removal or automatic mutation action', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.request).toHaveBeenCalledWith(1, 7, expect.any(Object));
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.WITHDRAWAL.pending_responsibilities'
  );
  expect(wrapper.text()).toContain('RELATIONSHIP.WITHDRAWAL.FINAL_REVIEW');
  expect(wrapper.findAll('button')).toHaveLength(0);
  expect(wrapper.findAll('dd').map(node => node.text())).toEqual(['0', '1']);
  wrapper.unmount();
});

it('reports missing visibility as unavailable without rendering fabricated zero counts', async () => {
  mocks.request.mockRejectedValue({ response: { status: 403 } });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'RELATIONSHIP.WITHDRAWAL.UNAVAILABLE'
  );
  expect(wrapper.findAll('dd')).toHaveLength(0);
  wrapper.unmount();
});

it('clears old account data and ignores a late response after an identity change', async () => {
  let finish;
  mocks.request.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  mocks.route.params.accountId = 2;
  await flushPromises();
  finish({
    data: { state: 'ready_for_final_review', counts: { allocations: 999 } },
  });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('999');
  wrapper.unmount();
});
