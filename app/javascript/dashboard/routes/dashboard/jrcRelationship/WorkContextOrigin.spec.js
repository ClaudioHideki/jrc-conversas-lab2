import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Panel from './WorkContextPanel.vue';
const mocks = vi.hoisted(() => ({ api: vi.fn(), route: null, store: null }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { workContext: mocks.api },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
const data = {
  executive_summary: 'Synthetic exact source',
  period: { from: '2026-10-01', to: '2026-11-01' },
  health: {},
  risks: [],
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.mockResolvedValue({ data });
});
it('binds the optional origin to the explicit account and portfolio and emits the request identity', async () => {
  const wrapper = mount(Panel, {
    props: {
      assignmentId: 99,
      sourceHint: { source_type: 'JrcCrm::SalesOrder', source_id: 40 },
    },
  });
  await flushPromises();
  expect(mocks.api).toHaveBeenCalledWith(
    '1',
    99,
    { source_type: 'JrcCrm::SalesOrder', source_id: 40 },
    expect.anything()
  );
  expect(wrapper.emitted('loaded').at(-1)).toEqual([
    data,
    { accountId: '1', assignmentId: 99, userId: 7 },
  ]);
  wrapper.unmount();
});
it('preserves normal context calls without an origin or a changed payload contract', async () => {
  const wrapper = mount(Panel, { props: { assignmentId: 99 } });
  await flushPromises();
  expect(mocks.api).toHaveBeenCalledWith('1', 99, {}, expect.anything());
  expect(wrapper.emitted('loaded').at(-1)[0]).toEqual(data);
  wrapper.unmount();
});
it('aborts old requests and ignores their context after source navigation changes', async () => {
  const resolves = [];
  mocks.api.mockImplementation(
    () =>
      new Promise(done => {
        resolves.push(done);
      })
  );
  const wrapper = mount(Panel, {
    props: {
      assignmentId: 99,
      sourceHint: { source_type: 'JrcCrm::SalesOrder', source_id: 40 },
    },
  });
  await wrapper.setProps({
    sourceHint: { source_type: 'JrcCrm::SalesOrder', source_id: 41 },
  });
  expect(mocks.api.mock.calls[0][3].signal.aborted).toBe(true);
  resolves[1]({ data });
  await flushPromises();
  resolves[0]({ data: { ...data, executive_summary: 'Stale source' } });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Stale source');
  expect(
    wrapper.emitted('loaded').filter(([value]) => value !== null)
  ).toHaveLength(1);
  wrapper.unmount();
});
