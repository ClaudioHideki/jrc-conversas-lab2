import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import History from './ProductHealthHistory.vue';

const mocks = vi.hoisted(() => ({ api: vi.fn(), route: null, store: null }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { productHealthHistory: mocks.api },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => mocks.store }));
const fixture = {
  payload: [
    {
      id: 4,
      calculated_at: '2026-11-04T12:00:00Z',
      health: {
        score: 50,
        band: 'risk',
        config_version: 2,
        factors: [
          {
            factor: 'adoption',
            normalized: 50,
            evidence: 'Synthetic product evidence',
          },
        ],
      },
      change: { delta: -5, configuration_changed: true },
    },
  ],
  meta: { page: 1, per_page: 10, total: 12 },
  product_id: 6,
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: 1 } });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 3,
      getCurrentUser: { accounts: [{ id: 1, role: 'agent' }] },
    },
  });
  mocks.api.mockResolvedValue({ data: fixture });
});
describe('Product health history from native snapshots', () => {
  it('loads only the selected product on demand, exposes evidence and paginates actual rows', async () => {
    const wrapper = mount(History, {
      props: { assignmentId: 2, productId: 6 },
    });
    expect(mocks.api).not.toHaveBeenCalled();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(mocks.api).toHaveBeenCalledWith(1, 2, {
      product_id: 6,
      page: 1,
      per_page: 10,
    });
    expect(wrapper.text()).toContain('Synthetic product evidence');
    expect(wrapper.text()).toContain('50');
    mocks.api.mockResolvedValue({
      data: {
        ...fixture,
        payload: [],
        meta: { page: 2, per_page: 10, total: 12 },
      },
    });
    await wrapper.findAll('nav button').at(-1).trigger('click');
    await flushPromises();
    expect(mocks.api).toHaveBeenLastCalledWith(1, 2, {
      product_id: 6,
      page: 2,
      per_page: 10,
    });
    expect(
      wrapper.findAll('nav button').at(-1).attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });
  it('clears previously authorized evidence if a new page is denied', async () => {
    const wrapper = mount(History, {
      props: { assignmentId: 2, productId: 6 },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    mocks.api.mockRejectedValue({ response: { status: 403 } });
    await wrapper.findAll('nav button').at(-1).trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Synthetic product evidence');
    wrapper.unmount();
  });
  it('preserves a missing score instead of rendering zero', async () => {
    mocks.api.mockResolvedValue({
      data: {
        ...fixture,
        payload: [
          {
            ...fixture.payload[0],
            health: { score: null, band: 'unavailable', config_version: 2 },
          },
        ],
      },
    });
    const wrapper = mount(History, {
      props: { assignmentId: 2, productId: 6 },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Indisponível');
    wrapper.unmount();
  });
  it.each([
    'account',
    'product',
    'assignment',
    'user',
    'permissions',
    'unmount',
  ])('ignores late evidence after %s changes', async change => {
    let resolve;
    mocks.api.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(History, {
      props: { assignmentId: 2, productId: 6 },
    });
    await wrapper.get('button').trigger('click');
    if (change === 'account') mocks.route.params.accountId = 9;
    if (change === 'product') await wrapper.setProps({ productId: 8 });
    if (change === 'assignment') await wrapper.setProps({ assignmentId: 7 });
    if (change === 'user') mocks.store.getters.getCurrentUserID = 10;
    if (change === 'permissions')
      mocks.store.getters.getCurrentUser.accounts = [
        { id: 1, role: 'agent', permissions: [] },
      ];
    if (change === 'unmount') wrapper.unmount();
    await flushPromises();
    resolve({ data: fixture });
    await flushPromises();
    if (change !== 'unmount') {
      expect(wrapper.text()).not.toContain('Synthetic product evidence');
      wrapper.unmount();
    }
  });
});
