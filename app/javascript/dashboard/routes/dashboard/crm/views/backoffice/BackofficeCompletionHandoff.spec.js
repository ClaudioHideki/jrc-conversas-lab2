import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Handoff from './BackofficeCompletionHandoff.vue';
const mocks = vi.hoisted(() => ({ api: vi.fn(), route: null }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeAPI: { completionHandoff: mocks.api },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
const render = () =>
  mount(Handoff, {
    props: { record: { id: 5, status: 'completed' } },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
beforeEach(() => {
  mocks.route = reactive({
    params: { accountId: '1' },
    query: { customer_segment_id: '12' },
  });
  mocks.api.mockResolvedValue({
    data: {
      available: true,
      assignment_id: 99,
      source_type: 'JrcCrm::SalesOrder',
      source_id: 40,
      handoff_id: 77,
    },
  });
});
it('checks the server before exposing the exact native route and preserves the active segment', async () => {
  const wrapper = render();
  expect(mocks.api).not.toHaveBeenCalled();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(mocks.api).toHaveBeenCalledWith('1', 5);
  expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
    name: 'jrc_relationship_handoffs',
    params: { accountId: '1' },
    query: {
      assignment_id: 99,
      source_type: 'JrcCrm::SalesOrder',
      source_id: 40,
      handoff_id: 77,
      customer_segment_id: '12',
    },
  });
  wrapper.unmount();
});
it('does not manufacture a target for a customer without an authorized portfolio', async () => {
  mocks.api.mockResolvedValue({
    data: { available: false, code: 'HANDOFF_CONTEXT_UNAVAILABLE' },
  });
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
  expect(wrapper.find('[role="status"]').exists()).toBe(true);
  wrapper.unmount();
});
it('clears an old target on a denied refresh and never shows a successful link', async () => {
  const wrapper = render();
  await wrapper.get('button').trigger('click');
  await flushPromises();
  mocks.api.mockRejectedValue({ response: { status: 403 } });
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
it.each(['account', 'request', 'reopen', 'unmount'])(
  'ignores late authorization after %s changes',
  async change => {
    let resolve;
    mocks.api.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = render();
    await wrapper.get('button').trigger('click');
    if (change === 'account') mocks.route.params.accountId = '2';
    if (change === 'request')
      await wrapper.setProps({ record: { id: 6, status: 'completed' } });
    if (change === 'reopen')
      await wrapper.setProps({ record: { id: 5, status: 'in_progress' } });
    if (change === 'unmount') wrapper.unmount();
    await flushPromises();
    resolve({
      data: {
        available: true,
        assignment_id: 99,
        source_type: 'JrcCrm::SalesOrder',
        source_id: 40,
      },
    });
    await flushPromises();
    if (change !== 'unmount') {
      expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
      wrapper.unmount();
    }
  }
);
