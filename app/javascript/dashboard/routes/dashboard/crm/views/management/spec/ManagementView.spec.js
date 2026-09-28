import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import { useRoute } from 'vue-router';
import { managementAPI } from 'dashboard/api/crm';
import ManagementView from '../ManagementView.vue';

vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/api/crm', () => ({ managementAPI: { list: vi.fn() } }));
describe('CRM team management', () => {
  let wrapper;
  let route;
  let store;
  beforeEach(() => {
    route = reactive({ params: { accountId: '1' } });
    useRoute.mockReturnValue(route);
    store = createStore({
      state: { role: 'administrator' },
      getters: { getCurrentRole: state => state.role },
    });
    managementAPI.list.mockResolvedValue({
      data: [
        {
          user: { id: 1, name: 'Ana', email: 'a@example.test' },
          metrics: {
            open_deals_count: 3,
            closed_won_count: 2,
            won_revenue_cents: 10000,
            conversion_rate: 50,
          },
        },
      ],
    });
  });
  afterEach(() => wrapper?.unmount());
  it('loads actual metrics, searches agents and submits explicit date filters', async () => {
    wrapper = mount(ManagementView, { global: { plugins: [store] } });
    await flushPromises();
    expect(wrapper.get('tbody').text()).toContain('Ana');
    expect(wrapper.get('tbody').text()).toContain('50.0%');
    const dates = wrapper.findAll('input[type="date"]');
    await dates[0].setValue('2026-09-01');
    await dates[1].setValue('2026-09-25');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(managementAPI.list).toHaveBeenLastCalledWith({
      start_date: '2026-09-01',
      end_date: '2026-09-25',
    });
    await wrapper.get('input[type="search"]').setValue('ausente');
    expect(wrapper.get('tbody').text()).toContain('Nenhuma métrica');
  });
  it('does not query the administrative API for an agent', async () => {
    store.state.role = 'agent';
    wrapper = mount(ManagementView, { global: { plugins: [store] } });
    await flushPromises();
    expect(managementAPI.list).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('somente para administradores');
  });
  it('shows an error instead of invented zero metrics and allows retry', async () => {
    managementAPI.list.mockRejectedValueOnce(new Error('network'));
    wrapper = mount(ManagementView, { global: { plugins: [store] } });
    await flushPromises();
    expect(wrapper.text()).toContain('Não foi possível');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.get('tbody').text()).toContain('Ana');
  });
  it('ignores a response from the previous account', async () => {
    let oldResponse;
    managementAPI.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          oldResponse = resolve;
        })
    );
    wrapper = mount(ManagementView, { global: { plugins: [store] } });
    route.params.accountId = '2';
    await flushPromises();
    oldResponse({ data: [{ user: { id: 9, name: 'Antiga' }, metrics: {} }] });
    await flushPromises();
    expect(wrapper.get('tbody').text()).not.toContain('Antiga');
  });
});
