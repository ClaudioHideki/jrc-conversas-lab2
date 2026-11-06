import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from './MetricDrilldownDialog.vue';
import Panel from './MetricDrilldownPanel.vue';
const mocks = vi.hoisted(() => ({ route: null, getters: null, load: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { drilldown: mocks.load },
}));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const response = (page = 1, total = 26) => ({
  data: {
    metric: 'actions_today',
    value: total,
    aggregation: 'count',
    total,
    page,
    per_page: 25,
    payload: total
      ? [
          {
            id: page,
            source_type: 'JrcRelationship::Action',
            source_kind: 'action',
            label: 'Exact native source',
            status: 'open',
            route: {
              name: 'jrc_relationship_actions',
              params: { accountId: 1 },
              query: { action_id: page, mine: 'false' },
            },
          },
        ]
      : [],
  },
});
const render = () =>
  mount(Component, {
    props: {
      metric: 'actions_today',
      filters: { mode: 'mine', customer_segment_id: '4' },
    },
    global: { stubs: { Dialog, RouterLink: RouterLinkStub } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 7,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.load.mockResolvedValue(response());
});

it('reuses the native paginated panel with the same portfolio/segment and exact source navigation', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.load).toHaveBeenCalledWith(
    '1',
    {
      mode: 'mine',
      customer_segment_id: '4',
      metric: 'actions_today',
      page: 1,
    },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual(
    response().data.payload[0].route
  );
  mocks.load.mockResolvedValueOnce(response(2));
  wrapper.findComponent(Panel).vm.$emit('page', 2);
  await flushPromises();
  expect(mocks.load.mock.calls.at(-1)[1].page).toBe(2);
  expect(wrapper.findComponent(Panel).props('data').page).toBe(2);
  wrapper.unmount();
});

it('clears prior sources and invalidates the enclosing scope on a denied read', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.load.mockRejectedValueOnce({
    response: { status: 403, data: { errors: ['Source access revoked'] } },
  });
  wrapper.findComponent(Panel).vm.$emit('page', 2);
  await flushPromises();
  expect(wrapper.text()).not.toContain('Exact native source');
  expect(wrapper.findComponent(Panel).exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Source access revoked'
  );
  expect(wrapper.emitted('invalidated')).toHaveLength(1);
  wrapper.unmount();
});

it('closes, aborts and ignores late data after identity or portfolio scope changes', async () => {
  let finish;
  mocks.load.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  const signal = mocks.load.mock.calls[0][2].signal;
  await wrapper.setProps({
    filters: { mode: undefined, customer_segment_id: '8' },
  });
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(signal.aborted).toBe(true);
  finish(response());
  await flushPromises();
  expect(wrapper.findComponent(Panel).exists()).toBe(false);
  wrapper.unmount();
});

it('recovers once when the last page disappears and never displays unavailable measurement as zero', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.load
    .mockResolvedValueOnce(response(2, 0))
    .mockResolvedValueOnce(response(1, 0));
  wrapper.findComponent(Panel).vm.$emit('page', 2);
  await flushPromises();
  expect(mocks.load).toHaveBeenCalledTimes(3);
  expect(wrapper.findComponent(Panel).props('data')).toMatchObject({
    page: 1,
    total: 0,
    value: 0,
  });
  wrapper.unmount();
  mocks.load.mockResolvedValue({ data: { ...response().data, value: null } });
  const unavailable = render();
  await flushPromises();
  expect(unavailable.findComponent(Panel).exists()).toBe(false);
  expect(unavailable.text()).toContain('RELATIONSHIP.UNAVAILABLE');
  unavailable.unmount();
});
