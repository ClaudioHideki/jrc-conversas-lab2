import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import leads from 'dashboard/store/crm/modules/leads';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { leadsAPI, pipelinesAPI, productsAPI } from 'dashboard/api/crm';
import LeadsIndex from '../LeadsIndex.vue';

const navigation = vi.hoisted(() => ({
  route: null,
  router: { replace: vi.fn(), push: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => navigation.router,
}));
vi.mock('dashboard/api/crm', () => ({
  leadsAPI: { list: vi.fn(), show: vi.fn(), update: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
  stagesAPI: { list: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/layout/useQuickActionTarget', () => ({
  useQuickActionTarget: vi.fn(),
}));

let wrapper;
let authority;
const selected = () => wrapper.findComponent({ name: 'LeadDetailModal' });
const create = (cachedLead = null) => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => 7,
      getCurrentRole: () => 'agent',
      getCurrentUser: () => ({
        id: 7,
        accounts: [
          {
            id: authority.account,
            role: 'agent',
            permissions: ['agent', 'jrc_crm'],
          },
        ],
      }),
    },
    modules: {
      jrcCrm: {
        namespaced: true,
        modules: {
          leads: {
            ...leads,
            state: { ...leads.state, currentLead: cachedLead },
          },
        },
      },
    },
  });
  if (cachedLead) {
    store.state.jrcCrm.leads.detailScope = authorityScope(store.getters);
    expect(store.getters['jrcCrm/leads/currentLead']).toEqual(cachedLead);
  }
  wrapper = mount(LeadsIndex, {
    global: {
      plugins: [store],
      stubs: {
        Teleport: true,
        LeadCreateModal: true,
        LeadDetailModal: true,
        LeadConversionModal: true,
        CrmStatusBadge: true,
      },
    },
  });
  return store;
};

beforeEach(() => {
  vi.clearAllMocks();
  authority = reactive({ account: 1 });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { leadId: '91' },
  });
  leadsAPI.list.mockResolvedValue({
    data: [{ id: 1, name: 'SYNTHETIC listed', status: 'new' }],
  });
  leadsAPI.show.mockResolvedValue({
    data: { id: 91, name: 'SYNTHETIC older lead', status: 'new' },
  });
  pipelinesAPI.list.mockResolvedValue({ data: [] });
  productsAPI.list.mockResolvedValue({ data: [] });
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

// Uses the real existing authority-bound Vuex detail action; HTTP is mocked.
// This suite is not native authorization or Chrome acceptance.
describe('Control Desk history navigation to an existing native Lead', () => {
  it('opens an older authorized Lead by its native show endpoint without changing the loaded list or filters', async () => {
    navigation.route.query.customer_segment_id = '17';
    create();
    await flushPromises();
    expect(leadsAPI.show).toHaveBeenCalledWith('91');
    expect(selected().props('lead').id).toBe(91);
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(navigation.route.query.customer_segment_id).toBe('17');
    expect(navigation.router.replace).not.toHaveBeenCalled();
  });

  it('invalidates a cached same-account detail before rendering and requires a fresh authorized response', async () => {
    let finish;
    leadsAPI.show.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    create({ id: 91, name: 'SYNTHETIC cached old detail', status: 'new' });
    expect(selected().exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC cached old detail');
    await flushPromises();
    expect(leadsAPI.show).toHaveBeenCalledWith('91');
    expect(selected().exists()).toBe(false);
    finish({
      data: {
        id: 91,
        name: 'SYNTHETIC freshly authorized detail',
        status: 'new',
      },
    });
    await flushPromises();
    expect(selected().props('lead').name).toBe(
      'SYNTHETIC freshly authorized detail'
    );
  });

  it('does not issue an extra detail request when the selected Lead is already in the authorized list', async () => {
    navigation.route.query.leadId = '1';
    create();
    await flushPromises();
    expect(selected().props('lead').id).toBe(1);
    expect(leadsAPI.show).not.toHaveBeenCalled();
  });

  it('shows a bounded error instead of another Lead when the native detail request is denied', async () => {
    leadsAPI.show.mockRejectedValue({ response: { status: 403 } });
    create();
    await flushPromises();
    expect(selected().exists()).toBe(false);
    expect(wrapper.find('[data-lead-detail-unavailable]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('SYNTHETIC older lead');
  });

  it('ignores an older response after the user opens a different native Lead', async () => {
    let finishFirst;
    leadsAPI.show.mockImplementation(id =>
      id === '91'
        ? new Promise(resolve => {
            finishFirst = resolve;
          })
        : Promise.resolve({
            data: { id: 92, name: 'SYNTHETIC second selection', status: 'new' },
          })
    );
    create();
    await flushPromises();
    navigation.route.query.leadId = '92';
    await flushPromises();
    expect(selected().props('lead').id).toBe(92);
    finishFirst({
      data: { id: 91, name: 'SYNTHETIC stale selection', status: 'new' },
    });
    await flushPromises();
    expect(selected().props('lead').id).toBe(92);
    expect(wrapper.text()).not.toContain('SYNTHETIC stale selection');
  });

  it('invalidates an in-flight detail when the user closes it', async () => {
    let finish;
    leadsAPI.show.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    create();
    await flushPromises();
    navigation.route.query = {};
    await flushPromises();
    finish({
      data: { id: 91, name: 'SYNTHETIC closed detail', status: 'new' },
    });
    await flushPromises();
    expect(selected().exists()).toBe(false);
    expect(wrapper.find('[data-lead-detail-unavailable]').exists()).toBe(false);
  });

  it('invalidates the native detail request when leaving the screen before its response arrives', async () => {
    let finish;
    leadsAPI.show.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const store = create();
    await flushPromises();
    wrapper.unmount();
    wrapper = null;
    finish({
      data: { id: 91, name: 'SYNTHETIC departed screen', status: 'new' },
    });
    await flushPromises();
    expect(store.getters['jrcCrm/leads/currentLead']).toBeNull();
    expect(store.state.jrcCrm.leads.currentLead).toBeNull();
  });

  it('hides the old account detail immediately and rechecks it under the current native identity', async () => {
    create();
    await flushPromises();
    expect(selected().props('lead').id).toBe(91);
    leadsAPI.list.mockResolvedValue({ data: [] });
    leadsAPI.show.mockRejectedValue({ response: { status: 404 } });
    authority.account = 2;
    navigation.route.params.accountId = '2';
    await flushPromises();
    expect(selected().exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC older lead');
    expect(wrapper.find('[data-lead-detail-unavailable]').exists()).toBe(true);
  });

  it('keeps native status updates functional for an off-list selected Lead', async () => {
    create();
    await flushPromises();
    leadsAPI.update.mockResolvedValue({
      data: { id: 91, name: 'SYNTHETIC older lead', status: 'qualified' },
    });
    selected().vm.$emit('statusChange', selected().props('lead'), 'qualified');
    await flushPromises();
    expect(leadsAPI.update).toHaveBeenCalledWith(91, {
      lead: { status: 'qualified' },
    });
    expect(selected().props('lead').status).toBe('qualified');
    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
  });
});
