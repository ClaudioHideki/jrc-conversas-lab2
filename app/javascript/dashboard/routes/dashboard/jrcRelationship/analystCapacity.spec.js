import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from './AnalystCapacityDialog.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  analystCapacity: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const response = (unit = 'points', page = 1) => ({
  data: {
    analyst: { id: 7, name: 'Synthetic authorized analyst', active_user: true },
    payload: [
      {
        scope_key: 'account',
        unit,
        current: 5,
        effective_capacity: 4,
        available_after: -1,
        maximum: 10,
        availability: 0.8,
        dedication: 0.5,
      },
    ],
    meta: { page, per_page: 10, total: 11 },
  },
});
const render = () =>
  mount(Component, { props: { analystId: 7 }, global: { stubs: { Dialog } } });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 3,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.analystCapacity.mockResolvedValue(response());
});
it('shows actual typed overload and pages through native scopes without displaying incoming transfer facts', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.analystCapacity).toHaveBeenCalledWith(
    '1',
    7,
    { page: 1, per_page: 10 },
    expect.anything()
  );
  expect(wrapper.text()).toContain('RELATIONSHIP.CAPACITY.CURRENT_OVERLOAD');
  expect(wrapper.text()).toContain('RELATIONSHIP.CAPACITY.UNITS.points');
  expect(wrapper.text()).not.toContain('RELATIONSHIP.CAPACITY.FACTS.incoming');
  expect(wrapper.text()).not.toContain('RELATIONSHIP.CAPACITY.FACTS.projected');
  mocks.analystCapacity.mockResolvedValue(response('hours', 2));
  await wrapper.get('[data-testid="capacity-next"]').trigger('click');
  await flushPromises();
  expect(mocks.analystCapacity.mock.calls.at(-1)[2]).toEqual({
    page: 2,
    per_page: 10,
  });
  expect(wrapper.text()).toContain('RELATIONSHIP.CAPACITY.UNITS.hours');
  wrapper.unmount();
});
it('does not invent zero workload for a missing native measurement', async () => {
  const missing = response('hours');
  missing.data.payload = [
    {
      scope_key: 'account',
      unit: 'hours',
      blocker: 'capacity_workload_missing',
    },
  ];
  mocks.analystCapacity.mockResolvedValue(missing);
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.CAPACITY.BLOCKERS.capacity_workload_missing'
  );
  expect(wrapper.find('dl').exists()).toBe(false);
  wrapper.unmount();
});
it('aborts identity changes and rejects a late capacity response from the previous account', async () => {
  let complete;
  mocks.analystCapacity.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        complete = resolve;
      })
  );
  const wrapper = render();
  const request = mocks.analystCapacity.mock.calls[0][3];
  mocks.route.params.accountId = '2';
  await flushPromises();
  complete(response());
  await flushPromises();
  expect(request.signal.aborted).toBe(true);
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('Synthetic authorized analyst');
  wrapper.unmount();
});
it('shows access denied without a partial capacity value or an invented successful operation', async () => {
  mocks.analystCapacity.mockRejectedValue({ response: { status: 403 } });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('RELATIONSHIP.CAPACITY.CURRENT_UNAVAILABLE');
  expect(wrapper.text()).not.toContain('Synthetic authorized analyst');
  expect(wrapper.find('dl').exists()).toBe(false);
  expect(wrapper.emitted('save')).toBeUndefined();
  wrapper.unmount();
});
