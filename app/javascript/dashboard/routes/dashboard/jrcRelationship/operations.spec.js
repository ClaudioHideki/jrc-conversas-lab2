import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import OperationsSettingsPanel from './OperationsSettingsPanel.vue';
import ConfigurationPanel from './ConfigurationPanel.vue';
import SlaSummary from './SlaSummary.vue';
import MetricsPanel from './MetricsPanel.vue';
import labels from 'dashboard/i18n/locale/en/relationship.json';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    operationsQueues: vi.fn(),
    operationsPolicies: vi.fn(),
    saveOperationsQueue: vi.fn(),
    saveOperationsPolicy: vi.fn(),
    configuration: vi.fn(),
    saveConfiguration: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const metadata = {
  can_configure_operations: true,
  owners: [[7, 'CS']],
  units: [[10, 'Unidade A']],
  teams: [[11, 'Equipe CS']],
  products: [],
  segments: [],
};
const history = {
  scope_key: 'account',
  version: 2,
  weights: { relationship: 100 },
  rules: { sla_hours: 24 },
  history: [
    {
      version: 1,
      weights: { relationship: 80 },
      rules: { sla_hours: 12 },
      actor_id: 7,
      created_at: '2026-10-05T10:00:00Z',
    },
    {
      version: 2,
      weights: { relationship: 100 },
      rules: { sla_hours: 24 },
      actor_id: 7,
      created_at: '2026-10-05T11:00:00Z',
    },
  ],
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.operationsQueues.mockResolvedValue({ data: [] });
  mocks.api.operationsPolicies.mockResolvedValue({ data: [] });
  mocks.api.saveOperationsQueue.mockResolvedValue({ data: {} });
  mocks.api.saveOperationsPolicy.mockResolvedValue({ data: {} });
  mocks.api.configuration.mockResolvedValue({ data: structuredClone(history) });
  mocks.api.saveConfiguration.mockResolvedValue({ data: {} });
});

describe('Existing operational configuration controls', () => {
  it('does not load operational configuration without its native permission', async () => {
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: false, metadata },
    });
    await flushPromises();
    expect(mocks.api.operationsQueues).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="new-queue"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('creates an account-bound CS queue with its selected unit and team', async () => {
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-queue"]').trigger('click');
    await wrapper.get('[data-testid="queue-name"]').setValue('CS unidade A');
    await wrapper.get('[data-testid="queue-code"]').setValue('CS-A');
    const form = wrapper.get('[data-testid="queue-form"]');
    const selects = form.findAll('select');
    await selects[2].setValue('10');
    await selects[3].setValue('11');
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.api.saveOperationsQueue).toHaveBeenCalledWith(
      '12',
      expect.objectContaining({
        name: 'CS unidade A',
        code: 'CS-A',
        business_unit_id: 10,
        team_id: 11,
        settings: expect.objectContaining({ scopes: ['relationship'] }),
      }),
      undefined
    );
    wrapper.unmount();
  });
  it('saves first-action/resolution, pause and percentage alerts through the existing SLA endpoint', async () => {
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-policy"]').trigger('click');
    await wrapper.get('[data-testid="policy-name"]').setValue('SLA CS');
    await wrapper
      .get('[data-testid="policy-first_action_minutes"]')
      .setValue(240);
    await wrapper.get('[data-testid="policy-total_minutes"]').setValue(1440);
    await wrapper.get('[data-testid="policy-alerts"]').setValue('50, 90, 100');
    await wrapper.get('[data-testid="policy-form"]').trigger('submit');
    await flushPromises();
    expect(mocks.api.saveOperationsPolicy).toHaveBeenCalledWith(
      '12',
      expect.objectContaining({
        first_action_minutes: 240,
        total_minutes: 1440,
        stage_minutes: null,
        pause_statuses: ['waiting_customer'],
        alert_thresholds: [50, 90, 100],
        scope_kind: 'relationship',
      }),
      undefined
    );
    wrapper.unmount();
  });
  it('preserves null deadlines on an existing monitor-only policy', async () => {
    mocks.api.operationsPolicies.mockResolvedValue({
      data: [
        {
          id: 4,
          name: 'Monitor',
          scope_kind: 'backoffice',
          first_action_minutes: null,
          total_minutes: null,
          stage_minutes: null,
          conditions: { monitor_only: true },
          business_hours: {},
          pause_statuses: [],
          alert_thresholds: [],
          escalation: {},
          active: true,
        },
      ],
    });
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.findAll('li button')[0].trigger('click');
    await wrapper.get('[data-testid="policy-form"]').trigger('submit');
    await flushPromises();
    expect(mocks.api.saveOperationsPolicy).toHaveBeenCalledWith(
      '12',
      expect.objectContaining({
        first_action_minutes: null,
        total_minutes: null,
        conditions: expect.objectContaining({ monitor_only: true }),
      }),
      4
    );
    wrapper.unmount();
  });
  it('clears the old account editor and ignores its late load and save responses', async () => {
    let resolveSave;
    mocks.api.saveOperationsQueue.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveSave = resolve;
        })
    );
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-queue"]').trigger('click');
    await wrapper.get('[data-testid="queue-name"]').setValue('Conta anterior');
    await wrapper.get('[data-testid="queue-code"]').setValue('OLD');
    await wrapper.get('[data-testid="queue-form"]').trigger('submit');
    mocks.route.params.accountId = '13';
    await flushPromises();
    await wrapper.get('[data-testid="new-queue"]').trigger('click');
    await wrapper.get('[data-testid="queue-name"]').setValue('Conta atual');
    resolveSave({ data: {} });
    await flushPromises();
    expect(wrapper.get('[data-testid="queue-name"]').element.value).toBe(
      'Conta atual'
    );
    expect(mocks.api.saveOperationsQueue.mock.calls[0][0]).toBe('12');
    expect(mocks.api.operationsQueues.mock.calls.at(-1)[0]).toBe('13');
    wrapper.unmount();
  });
  it('discards a late queue load after switching account', async () => {
    let resolveOld;
    mocks.api.operationsQueues.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    mocks.api.operationsQueues.mockResolvedValue({
      data: [
        {
          id: 3,
          name: 'Current queue',
          code: 'CURRENT',
          assignment_strategy: 'manual',
          active: true,
          settings: {},
        },
      ],
    });
    mocks.route.params.accountId = '13';
    await flushPromises();
    resolveOld({
      data: [
        {
          id: 1,
          name: 'Old queue',
          code: 'OLD',
          assignment_strategy: 'manual',
          active: true,
          settings: {},
        },
      ],
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Current queue');
    expect(wrapper.text()).not.toContain('Old queue');
    wrapper.unmount();
  });
  it('preserves the form and displays a backend validation failure', async () => {
    mocks.api.saveOperationsQueue.mockRejectedValueOnce({
      response: { data: { errors: ['Unidade inválida'] } },
    });
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-queue"]').trigger('click');
    await wrapper.get('[data-testid="queue-name"]').setValue('Preserved');
    await wrapper.get('[data-testid="queue-code"]').setValue('KEEP');
    await wrapper.get('[data-testid="queue-form"]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain('Unidade inválida');
    expect(wrapper.get('[data-testid="queue-name"]').element.value).toBe(
      'Preserved'
    );
    wrapper.unmount();
  });
  it('blocks invalid percentage alert inputs before sending a policy', async () => {
    const wrapper = mount(OperationsSettingsPanel, {
      props: { allowed: true, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="new-policy"]').trigger('click');
    await wrapper.get('[data-testid="policy-name"]').setValue('Invalid policy');
    await wrapper
      .get('[data-testid="policy-alerts"]')
      .setValue('50, invalid, 100');
    await wrapper.get('[data-testid="policy-form"]').trigger('submit');
    await flushPromises();
    expect(mocks.api.saveOperationsPolicy).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });
  it('renders the real versions, actor and historical weights without resending history', async () => {
    const wrapper = mount(ConfigurationPanel, {
      props: { allowed: true, metadata },
      global: { stubs: { OperationsSettingsPanel: true } },
    });
    await flushPromises();
    expect(wrapper.findAll('details')).toHaveLength(2);
    expect(wrapper.findAll('details')[0].text()).toContain('CS');
    expect(wrapper.findAll('details')[0].text()).toContain('80');
    expect(wrapper.findAll('details')[1].text()).toContain('100');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.saveConfiguration.mock.calls[0][1]).not.toHaveProperty(
      'history'
    );
    wrapper.unmount();
  });
  it('clears version history immediately after switching user and permission', async () => {
    const wrapper = mount(ConfigurationPanel, {
      props: { allowed: true, metadata },
      global: { stubs: { OperationsSettingsPanel: true } },
    });
    await flushPromises();
    await wrapper.setProps({ allowed: false });
    mocks.store.getters.getCurrentUserID = 8;
    await flushPromises();
    expect(wrapper.findAll('details')).toHaveLength(0);
    wrapper.unmount();
  });
  it('displays a paused clock separately from overdue and displays completed first action', () => {
    const wrapper = mount(SlaSummary, {
      props: {
        sla: {
          state: 'overdue',
          percent_elapsed: 25,
          first_action_due_at: '2026-10-05T11:00:00Z',
          first_action_at: '2026-10-05T10:00:00Z',
          total_due_at: '2026-10-05T18:00:00Z',
          paused_at: '2026-10-05T12:00:00Z',
        },
      },
    });
    expect(wrapper.text()).toContain(labels.RELATIONSHIP.SLA_STATES.paused);
    expect(wrapper.text()).not.toContain(
      labels.RELATIONSHIP.SLA_STATES.overdue
    );
    wrapper.unmount();
  });
  it('shows waiting-customer actions as their own indicator', () => {
    const wrapper = mount(MetricsPanel, {
      props: { metrics: { waiting_customer_actions: 3, overdue_actions: 0 } },
    });
    const card = wrapper
      .findAll('button')
      .find(row =>
        row
          .text()
          .includes(labels.RELATIONSHIP.METRICS.waiting_customer_actions)
      );
    expect(card.find('strong').text()).toBe('3');
    wrapper.unmount();
  });
});
