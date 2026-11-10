import { flushPromises, shallowMount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Panel from './HandoffPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  portfolio: vi.fn(),
  handoffs: vi.fn(),
  createHandoff: vi.fn(),
  handoffContext: vi.fn(),
  decideHandoff: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks }));
const context = {
  executive_summary: 'Synthetic source context',
  handoff_sources: [
    { type: 'JrcCrm::SalesOrder', id: 2, label: 'Other order' },
    { type: 'JrcCrm::SalesOrder', id: 40, label: 'Exact order' },
  ],
};
const identity = { accountId: '1', assignmentId: 99, userId: 7 };
beforeEach(() => {
  mocks.route = reactive({
    params: { accountId: '1' },
    query: {
      customer_segment_id: '12',
      assignment_id: '99',
      source_type: 'JrcCrm::SalesOrder',
      source_id: '40',
    },
  });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.portfolio.mockImplementation((_, params) =>
    Promise.resolve({
      data: {
        payload: params.assignment_id
          ? [{ id: 99, name: 'Exact customer' }]
          : [{ id: 1, name: 'First page customer' }],
      },
    })
  );
  mocks.handoffs.mockResolvedValue({ data: { payload: [] } });
  mocks.createHandoff.mockResolvedValue({ data: { id: 77 } });
});
describe('Native handoff origin navigation', () => {
  it('retrieves a portfolio outside the first page and prepares only the exact source after explicit submit', async () => {
    const wrapper = shallowMount(Panel, { props: { allowed: true } });
    await flushPromises();
    expect(mocks.portfolio).toHaveBeenCalledWith(
      '1',
      { assignment_id: 99, per_page: 1, customer_segment_id: '12' },
      expect.anything()
    );
    const work = wrapper.getComponent({ name: 'WorkContextPanel' });
    expect(work.props('sourceHint')).toEqual({
      source_type: 'JrcCrm::SalesOrder',
      source_id: 40,
    });
    work.vm.$emit('loaded', context, identity);
    await flushPromises();
    expect(mocks.createHandoff).not.toHaveBeenCalled();
    expect(wrapper.findAll('select')[1].element.value).toBe('1');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.createHandoff).toHaveBeenCalledOnce();
    expect(mocks.createHandoff).toHaveBeenCalledWith('1', {
      assignment_id: 99,
      source_type: 'JrcCrm::SalesOrder',
      source_id: 40,
    });
    expect(mocks.decideHandoff).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('does not retarget to the first customer when the linked portfolio is unavailable', async () => {
    mocks.portfolio.mockImplementation((_, params) =>
      Promise.resolve({
        data: {
          payload: params.assignment_id
            ? []
            : [{ id: 1, name: 'First page customer' }],
        },
      })
    );
    const wrapper = shallowMount(Panel, { props: { allowed: true } });
    await flushPromises();
    expect(wrapper.get('select').element.value).toBe('');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(mocks.createHandoff).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('rejects a mismatching case origin instead of opening another case on the same customer', async () => {
    mocks.route.query.handoff_id = '77';
    mocks.handoffs.mockResolvedValue({
      data: {
        payload: [
          {
            id: 77,
            assignment_id: 99,
            source_type: 'JrcCrm::SalesOrder',
            source_id: 66,
          },
        ],
      },
    });
    const wrapper = shallowMount(Panel, { props: { allowed: true } });
    await flushPromises();
    expect(mocks.handoffContext).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });
  it('ignores source context emitted for a previous portfolio selection', async () => {
    const wrapper = shallowMount(Panel, { props: { allowed: true } });
    await flushPromises();
    await wrapper.get('select').setValue(1);
    wrapper
      .getComponent({ name: 'WorkContextPanel' })
      .vm.$emit('loaded', context, identity);
    await flushPromises();
    expect(wrapper.findAll('select')[1].element.value).toBe('');
    expect(mocks.createHandoff).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('keeps the latest case inspection when responses arrive out of order', async () => {
    mocks.route.query = {};
    mocks.handoffs.mockResolvedValue({
      data: {
        payload: [
          { id: 1, status: 'pending', customer_name: 'First' },
          { id: 2, status: 'accepted', customer_name: 'Latest' },
        ],
      },
    });
    const resolves = [];
    mocks.handoffContext.mockImplementation(
      () =>
        new Promise(done => {
          resolves.push(done);
        })
    );
    const wrapper = shallowMount(Panel, { props: { allowed: true } });
    await flushPromises();
    const buttons = wrapper.findAll('li button');
    await buttons[0].trigger('click');
    await buttons[1].trigger('click');
    resolves[1]({ data: { executive_summary: 'Latest authorized source' } });
    await flushPromises();
    resolves[0]({ data: { executive_summary: 'Stale source' } });
    await flushPromises();
    expect(wrapper.text()).toContain('Latest authorized source');
    expect(wrapper.text()).not.toContain('Stale source');
    wrapper.unmount();
  });
  it('does not request or prepare data without current team capability', async () => {
    const wrapper = shallowMount(Panel, { props: { allowed: false } });
    await flushPromises();
    expect(mocks.portfolio).not.toHaveBeenCalled();
    expect(mocks.handoffs).not.toHaveBeenCalled();
    expect(mocks.createHandoff).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
