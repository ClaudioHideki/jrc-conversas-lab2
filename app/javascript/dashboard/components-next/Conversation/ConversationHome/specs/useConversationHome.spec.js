import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { useConversationHome } from '../useConversationHome';
import { homeMetrics } from '../presentation';
import api from 'dashboard/api/jrcAi';

const state = vi.hoisted(() => ({
  route: null,
  store: null,
  flags: null,
  serviceDesk: null,
  denied: null,
}));
vi.mock('vuex', () => ({ useStore: () => state.store }));
vi.mock('vue-router', () => ({
  useRoute: () => state.route,
  useRouter: () => ({
    hasRoute: name =>
      [
        'contacts_dashboard_index',
        'ramal_index',
        'crm_leads',
        'crm_deals',
        'crm_activities',
        'jrc_service_desk_new',
      ].includes(name),
    resolve: to => ({
      meta: {
        permissions: [to.name],
        featureFlag: to.name.startsWith('crm_') ? 'jrc_crm' : undefined,
      },
    }),
  }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    isFeatureFlagEnabled: flag => state.flags[flag] === true,
    shouldShow: (_flag, permissions) => !state.denied.includes(permissions[0]),
  }),
}));
vi.mock('dashboard/composables/useServiceDeskNavigation', () => ({
  useServiceDeskNavigation: () => state.serviceDesk,
}));
vi.mock('dashboard/api/jrcAi', () => ({ default: { cockpit: vi.fn() } }));

describe('conversation home uses existing authorized projections', () => {
  let home;
  let wrapper;
  beforeEach(() => {
    state.route = reactive({ params: { accountId: '1' } });
    state.store = reactive({
      getters: {
        getCurrentUserID: 7,
        getCurrentUser: {
          name: 'Teste',
          accounts: [
            { id: 1, permissions: ['jrc_crm'] },
            { id: 2, permissions: [] },
          ],
        },
      },
    });
    state.flags = reactive({ jrc_crm: true, jrc_service_desk: true });
    state.denied = reactive([]);
    state.serviceDesk = reactive({
      visible: true,
      context: {
        available: true,
        capabilities: { module: { index: true } },
        units: [{ id: 4, permissions: { create_ticket: true } }],
      },
    });
    api.cockpit.mockResolvedValue({
      data: {
        summary: { conversations_waiting: 3, missed_calls: null },
        generated_at: '2026-09-30T12:00:00Z',
      },
    });
  });
  afterEach(() => wrapper?.unmount());
  const start = () => {
    wrapper = mount({
      setup() {
        home = useConversationHome();
        return {};
      },
      template: '<div />',
    });
  };
  it('offers real destinations and existing new=1 flows scoped to the active account', async () => {
    start();
    await flushPromises();
    expect(home.actions.value.map(item => item.key)).toEqual([
      'CONTACT',
      'CALL',
      'LEAD',
      'DEAL',
      'ACTIVITY',
      'TICKET',
      'NICO',
    ]);
    expect(home.actions.value.find(item => item.key === 'LEAD').to).toEqual({
      name: 'crm_leads',
      params: { accountId: 1 },
      query: { new: '1' },
    });
    expect(home.actions.value.find(item => item.key === 'TICKET').to.name).toBe(
      'jrc_service_desk_new'
    );
    expect(api.cockpit).toHaveBeenCalledWith('today');
    expect(home.summary.value.missed_calls).toBeNull();
  });
  it('removes CRM when its flag or user grant is missing', async () => {
    start();
    await flushPromises();
    state.flags.jrc_crm = false;
    expect(home.actions.value.some(item => item.key === 'LEAD')).toBe(false);
    state.flags.jrc_crm = true;
    state.store.getters.getCurrentUser.accounts[0].permissions = [];
    expect(
      home.actions.value.some(item =>
        ['LEAD', 'DEAL', 'ACTIVITY'].includes(item.key)
      )
    ).toBe(false);
  });
  it('reuses route policy denials and requires an affirmative R2 create permission', () => {
    start();
    state.denied.push('contacts_dashboard_index', 'ramal_index');
    state.serviceDesk.context.units[0].permissions.create_ticket = false;
    expect(
      home.actions.value.some(item =>
        ['CONTACT', 'CALL', 'TICKET'].includes(item.key)
      )
    ).toBe(false);
    state.serviceDesk.context.units = [];
    expect(home.actions.value.some(item => item.key === 'TICKET')).toBe(false);
  });
  it('clears previous-account metrics immediately and ignores a late response', async () => {
    let finishOld;
    api.cockpit.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finishOld = resolve;
        })
    );
    start();
    state.serviceDesk.visible = false;
    state.route.params.accountId = '2';
    expect(home.summary.value).toEqual({});
    expect(home.actions.value.some(item => item.key === 'LEAD')).toBe(false);
    await flushPromises();
    finishOld({ data: { summary: { conversations_waiting: 999 } } });
    await flushPromises();
    expect(home.summary.value.conversations_waiting).toBe(3);
    expect(
      home.actions.value.find(item => item.key === 'CALL').to.params.accountId
    ).toBe(2);
  });
  it('represents failed reads as unavailable instead of fabricated zeros', async () => {
    api.cockpit.mockRejectedValueOnce(new Error('offline'));
    start();
    await flushPromises();
    expect(home.failed.value).toBe(true);
    expect(
      homeMetrics(home.summary.value, true).every(card => card.value === null)
    ).toBe(true);
  });
  it('preserves real zero values and semantic risk colors without changing counts', () => {
    const summary = {
      conversations_waiting: 0,
      missed_calls: null,
      sla_risk_count: 2,
      pending_tasks: 5,
    };
    expect(homeMetrics(summary, true).map(card => card.value)).toEqual([
      0,
      null,
      2,
      5,
    ]);
    expect(homeMetrics(summary, true)[2].tone).toBe('amber');
    expect(homeMetrics(summary, false)).toHaveLength(3);
    expect(summary).toEqual({
      conversations_waiting: 0,
      missed_calls: null,
      sla_risk_count: 2,
      pending_tasks: 5,
    });
  });
});
