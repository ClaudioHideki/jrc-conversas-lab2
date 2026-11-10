import { flushPromises, shallowMount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from '../DistributionApprovalOrigin.vue';
import Comparison from '../../jrcRelationship/DistributionComparison.vue';
const mocks = vi.hoisted(() => ({ get: vi.fn(), route: null, getters: null }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { distributionApprovalOrigin: mocks.get },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
const render = () =>
  shallowMount(Component, {
    props: {
      request: {
        id: 1,
        origin: { kind: 'portfolio_distribution', review_id: 20 },
      },
    },
  });
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '3' } });
  mocks.getters = reactive({
    getCurrentUserID: 8,
    getCurrentRole: 'agent',
    getCurrentUser: { accounts: [] },
  });
  mocks.get.mockResolvedValue({
    data: {
      justification: 'Synthetic transfer',
      distribution: [{ assignment_id: 4, label: 'Existing customer' }],
    },
  });
});
it('loads the exact native reviewed origin with the explicit current account and renders server facts', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.get).toHaveBeenCalledWith(
    '3',
    20,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(wrapper.getComponent(Comparison).props('rows')).toEqual([
    { assignment_id: 4, label: 'Existing customer' },
  ]);
  expect(wrapper.text()).toContain('Synthetic transfer');
  wrapper.unmount();
});
it('clears prior source data on membership revocation and never keeps old customer facts', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.get.mockRejectedValue({ response: { status: 403 } });
  mocks.getters.getCurrentUser.accounts = [{ id: 3, permissions: [] }];
  await flushPromises();
  expect(wrapper.findComponent(Comparison).exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
it('aborts the old account request and discards a late source response after switching accounts', async () => {
  let finish;
  mocks.get.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  const signal = mocks.get.mock.calls[0][2].signal;
  mocks.route.params.accountId = '5';
  mocks.get.mockRejectedValue({ response: { status: 403 } });
  await flushPromises();
  finish({ data: { justification: 'Old account facts', distribution: [] } });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.text()).not.toContain('Old account facts');
  wrapper.unmount();
});
it('discards a pending origin after unmount without performing a mutation', async () => {
  let finish;
  mocks.get.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  const signal = mocks.get.mock.calls[0][2].signal;
  wrapper.unmount();
  finish({ data: { distribution: [] } });
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.emitted('decide')).toBeUndefined();
});
