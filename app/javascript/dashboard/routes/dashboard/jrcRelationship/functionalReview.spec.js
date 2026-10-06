import { reactive } from 'vue';
import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import HealthScorePanel from './HealthScorePanel.vue';
import MetricsPanel from './MetricsPanel.vue';
import RenewalPipeline from './RenewalPipeline.vue';
import RecordEditor from './RecordEditor.vue';
import TeamPanel from './TeamPanel.vue';
import ModulePage from './ModulePage.vue';
import MetricDrilldownPanel from './MetricDrilldownPanel.vue';
import WorkContextPanel from './WorkContextPanel.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    metadata: vi.fn(),
    dashboard: vi.fn(),
    team: vi.fn(),
    portfolio: vi.fn(),
    records: vi.fn(),
    drilldown: vi.fn(),
  },
  push: vi.fn(),
  replace: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push, replace: mocks.replace }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));

const metadata = {
  can_manage: true,
  can_team: true,
  owners: [[7, 'CS']],
  units: [],
  teams: [],
  products: [],
  projects: [],
  pipelines: [],
};
const customer = {
  id: 19,
  name: 'Controlled test customer',
  signals: { health: { score: 80, band: 'healthy' } },
};
const stubLinks = {
  RouterLink: { template: '<a><slot /></a>', props: ['to'] },
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.dashboard.mockResolvedValue({
    data: {
      customers: 1,
      health_average: 80,
      renewals: { 30: 1, 60: 1, 90: 1 },
    },
  });
  mocks.api.team.mockResolvedValue({
    data: {
      payload: [{ user: { id: 7, name: 'CS' }, metrics: { customers: 1 } }],
    },
  });
  mocks.api.portfolio.mockResolvedValue({
    data: { payload: [customer], meta: { page: 1, total: 1, per_page: 25 } },
  });
  mocks.api.records.mockResolvedValue({
    data: { payload: [], meta: { page: 1, total: 0, per_page: 25 } },
  });
  mocks.api.drilldown.mockResolvedValue({
    data: {
      metric: 'customers',
      value: 1,
      total: 1,
      page: 1,
      per_page: 25,
      aggregation: 'count',
      payload: [{ id: 19, customer: customer.name }],
    },
  });
});

describe('Relationship functional review', () => {
  it('REL-03 presents dedicated portfolio cards and only 30/60/90 renewal windows', async () => {
    const w = mount(MetricsPanel, {
      props: {
        mode: 'portfolio',
        inspect: true,
        metrics: {
          customers: 1,
          mrr_cents: 100000,
          nrr: 99,
          renewals: { 30: 1, 60: 2, 90: 3 },
        },
      },
    });
    expect(w.findAll('section')[0].findAll('button')).toHaveLength(11);
    await w.findAll('button')[0].trigger('click');
    expect(w.emitted('inspect')[0]).toEqual(['customers']);
    await Promise.all(
      w
        .findAll('button')
        .slice(-3)
        .map(b => b.trigger('click'))
    );
    expect(w.emitted('filter').map(e => e[0])).toEqual(
      [30, 60, 90].map(renewal_days => ({ renewal_days }))
    );
    expect(w.text()).not.toContain('NRR');
    w.unmount();
  });

  it('REL-04 renders an actual health view with explainable trends, rankings and factor filters', async () => {
    const w = mount(HealthScorePanel, {
      props: {
        rows: [customer],
        metrics: {
          health_average: 80,
          bands: { healthy: 1 },
          health_trend: [{ day: '2026-10-06', score: 80 }],
          most_declined: [
            {
              assignment_id: 19,
              customer: customer.name,
              previous: 90,
              current: 80,
              delta: -10,
            },
          ],
          negative_factors: [{ factor: 'finance', customers: 1, average: 40 }],
          positive_factors: [
            { factor: 'relationship', customers: 1, average: 100 },
          ],
        },
      },
    });
    expect(w.find('[data-testid="health-score-view"]').exists()).toBe(true);
    expect(w.find('circle').exists()).toBe(true);
    const buttons = w.findAll('button');
    await buttons.find(b => b.text().includes('90 → 80')).trigger('click');
    expect(w.emitted('open')[0]).toEqual([19]);
    await buttons.find(b => b.text().includes('2026')).trigger('click');
    expect(w.emitted('inspect')[0]).toEqual([
      { metric: 'health_average', day: '2026-10-06' },
    ]);
    await buttons.find(b => b.text().includes('40')).trigger('click');
    expect(w.emitted('filter')[0]).toEqual([
      { factor: 'finance', direction: 'negative' },
    ]);
    w.unmount();
  });

  it('REL-04 keeps absent health data unavailable rather than inventing a trend', () => {
    const w = mount(HealthScorePanel);
    expect(w.find('svg').exists()).toBe(false);
    expect(w.findAll('button')[0].attributes('disabled')).toBeDefined();
    expect(w.text()).toContain('Indisponível');
    w.unmount();
  });

  it('REL-06 exposes severity, MRR, health and origin in the main risk row, with a read-only detail', async () => {
    mocks.api.metadata.mockResolvedValue({
      data: { ...metadata, can_manage: false },
    });
    mocks.api.records.mockResolvedValue({
      data: {
        payload: [
          {
            id: 9,
            customer_name: customer.name,
            severity: 'high',
            reason: 'Invoice overdue',
            mrr_cents: 100000,
            owner_name: 'CS',
            due_at: '2026-10-07',
            status: 'detected',
            health: { score: 45 },
            origin: 'finance',
            updated_at: '2026-10-06',
          },
        ],
        meta: { total: 1, page: 1, per_page: 25 },
      },
    });
    const w = shallowMount(ModulePage, {
      props: { screen: 'risks' },
      global: { stubs: stubLinks },
    });
    await flushPromises();
    expect(w.findAll('thead th')).toHaveLength(11);
    expect(w.text()).toContain('Alta');
    expect(w.text()).toContain('1.000,00');
    expect(w.text()).toContain('45');
    await w
      .findAll('button')
      .find(b => b.text() === 'Invoice overdue')
      .trigger('click');
    expect(w.findComponent(RecordEditor).props('readOnly')).toBe(true);
    w.unmount();
  });

  it('REL-07 saves objectives, milestones, notes and native activity IDs without mutating the original record', async () => {
    const record = {
      id: 5,
      assignment_id: 19,
      title: 'Plan',
      status: 'active',
      goals: [
        {
          metric: 'usage',
          baseline: 1,
          current: 2,
          target: 10,
          activity_id: 77,
        },
      ],
      metadata: {
        notes: 'Evidence',
        milestones: [{ title: 'Review', activity_id: 77 }],
      },
    };
    const w = shallowMount(RecordEditor, {
      props: { kind: 'plans', record, customers: [customer], metadata },
    });
    w.findComponent(WorkContextPanel).vm.$emit('loaded', {
      period: { from: '2026-10-01', to: '2026-10-06' },
      activities: [[77, 'Native activity']],
    });
    await flushPromises();
    expect(w.find('select[required]').attributes('disabled')).toBeDefined();
    await w.find('form').trigger('submit');
    const payload = w.emitted('save')[0][0];
    expect(payload.goals[0]).toMatchObject({
      baseline: 1,
      current: 2,
      target: 10,
      activity_id: 77,
    });
    expect(payload.milestones[0].activity_id).toBe(77);
    expect(payload.notes).toBe('Evidence');
    expect(record.goals[0].due_at).toBeUndefined();
    w.unmount();
  });

  it('REL-08 preserves internal user IDs, external attendees and deadlines for native QBR commitments', async () => {
    const w = shallowMount(RecordEditor, {
      props: {
        kind: 'qbrs',
        metadata,
        record: {
          assignment_id: 19,
          title: 'QBR',
          participants: [
            { participant_type: 'internal', user_id: 7, name: 'CS' },
            { participant_type: 'external', name: 'Customer' },
          ],
          decisions: [
            { title: 'Follow-up', owner_id: 7, due_at: '2026-10-07T12:00:00Z' },
          ],
        },
      },
    });
    await w.find('form').trigger('submit');
    const payload = w.emitted('save')[0][0];
    expect(payload.participants[0]).toMatchObject({
      participant_type: 'internal',
      user_id: 7,
    });
    expect(payload.participants[1].participant_type).toBe('external');
    expect(payload.decisions[0].due_at).toBe('2026-10-07T12:00:00.000Z');
    w.unmount();
  });

  it('never submits changes from a read-only operational detail', async () => {
    const w = shallowMount(RecordEditor, {
      props: { kind: 'risks', readOnly: true, record: { reason: 'Risk' } },
    });
    expect(w.find('fieldset').attributes('disabled')).toBeDefined();
    expect(w.find('button[type="submit"]').exists()).toBe(false);
    await w.find('form').trigger('submit');
    expect(w.emitted('save')).toBeUndefined();
    await w.findAll('button')[0].trigger('click');
    expect(w.emitted('close')).toHaveLength(1);
    w.unmount();
  });

  it('REL-09 exposes exclusive 120/90/60/30/15, overdue and later buckets with toggleable filters', async () => {
    const w = mount(RenewalPipeline, {
      props: { windows: { 120: 2, 15: 1, overdue: 3 }, selected: '15' },
    });
    const buttons = w.findAll('button');
    expect(buttons).toHaveLength(7);
    await buttons[4].trigger('click');
    await buttons[5].trigger('click');
    expect(w.emitted('filter')).toEqual([[''], ['overdue']]);
    expect(buttons[4].attributes('aria-pressed')).toBe('true');
    w.unmount();
  });

  it('REL-09 passes renewal bucket selection to the same authorized records API', async () => {
    const w = shallowMount(ModulePage, {
      props: { screen: 'renewals' },
      global: { stubs: stubLinks },
    });
    await flushPromises();
    w.findComponent(RenewalPipeline).vm.$emit('filter', 'overdue');
    await flushPromises();
    expect(mocks.api.records).toHaveBeenLastCalledWith(
      '1',
      'renewals',
      expect.objectContaining({ renewal_window: 'overdue' }),
      expect.any(Object)
    );
    w.unmount();
  });

  it('REL-10 uses the same agent/date filters for management rows, cards and their record drilldown', async () => {
    const w = shallowMount(TeamPanel, {
      props: { search: 'CS', startDate: '2026-10-01', endDate: '2026-10-06' },
    });
    await flushPromises();
    const query = expect.objectContaining({
      agent_q: 'CS',
      from: '2026-10-01',
      to: '2026-10-06',
    });
    expect(mocks.api.team).toHaveBeenLastCalledWith(
      '1',
      query,
      expect.any(Object)
    );
    expect(mocks.api.dashboard).toHaveBeenLastCalledWith(
      '1',
      query,
      expect.any(Object)
    );
    w.findComponent(MetricsPanel).vm.$emit('inspect', 'customers');
    await flushPromises();
    expect(mocks.api.drilldown).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ agent_q: 'CS', metric: 'customers' }),
      expect.any(Object)
    );
    expect(w.findComponent(MetricDrilldownPanel).props('data').total).toBe(1);
    await w.setProps({ search: 'Another CS' });
    await flushPromises();
    expect(mocks.api.dashboard).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ agent_q: 'Another CS' }),
      expect.any(Object)
    );
    expect(w.findComponent(MetricDrilldownPanel).exists()).toBe(false);
    w.unmount();
  });

  it('REL-10 discards a late drilldown response after switching accounts', async () => {
    let resolve;
    mocks.api.drilldown.mockImplementationOnce(
      () =>
        new Promise(r => {
          resolve = r;
        })
    );
    const w = shallowMount(ModulePage, { props: { screen: 'portfolio' } });
    await flushPromises();
    w.findComponent(MetricsPanel).vm.$emit('inspect', 'customers');
    mocks.route.params.accountId = '2';
    await flushPromises();
    resolve({
      data: {
        metric: 'customers',
        payload: [{ customer: 'Old account private data' }],
      },
    });
    await flushPromises();
    expect(w.findComponent(MetricDrilldownPanel).exists()).toBe(false);
    expect(w.text()).not.toContain('Old account private data');
    w.unmount();
  });

  it('REL-10 shows ratio components and links to the native authorized source', () => {
    const w = mount(MetricDrilldownPanel, {
      props: {
        data: {
          metric: 'nps',
          value: 0,
          aggregation: 'ratio',
          total: 2,
          page: 1,
          per_page: 25,
          calculation: { promoters: 1, detractors: 1, denominator: 2 },
          payload: [
            {
              id: 9,
              label: 'Response',
              source_type: 'JrcRelationship::Survey',
              source_kind: 'survey',
              score: 9,
              route: {
                name: 'jrc_relationship_surveys',
                params: { accountId: '1' },
              },
            },
          ],
        },
      },
      global: { stubs: stubLinks },
    });
    expect(w.text()).toContain('100 × (1 − 1) / 2');
    expect(
      w.findComponent(stubLinks.RouterLink).props('to').params.accountId
    ).toBe('1');
    expect(w.text()).not.toContain('JrcRelationship::Survey');
    w.unmount();
  });
});
