import { reactive } from 'vue';
import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import ModulePage from './ModulePage.vue';
import MetricsPanel from './MetricsPanel.vue';
import ConfigurationPanel from './ConfigurationPanel.vue';
import RecordEditor from './RecordEditor.vue';
import MetricDrilldownPanel from './MetricDrilldownPanel.vue';
import labels from 'dashboard/i18n/locale/en/relationship.json';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    metadata: vi.fn(),
    dashboard: vi.fn(),
    portfolio: vi.fn(),
    records: vi.fn(),
    configuration: vi.fn(),
    playbooks: vi.fn(),
    savePlaybook: vi.fn(),
    batch: vi.fn(),
  },
  push: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push, replace: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const metadata = {
  can_manage: true,
  can_configure: true,
  can_team: true,
  can_crm: true,
  owners: [[7, 'CS']],
  teams: [],
  units: [],
  products: [],
  segments: [],
  pipelines: [],
  projects: [],
};
const page = screen =>
  shallowMount(ModulePage, {
    props: { screen },
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.metadata.mockResolvedValue({ data: metadata });
  mocks.api.dashboard.mockResolvedValue({
    data: {
      nps: -50,
      csat: 2,
      ces: 8,
      expansion_potential_cents: 100000,
      expansion_won_cents: 200000,
    },
  });
  mocks.api.portfolio.mockResolvedValue({
    data: { payload: [], meta: { page: 1, total: 0, per_page: 25 } },
  });
  mocks.api.records.mockResolvedValue({
    data: { payload: [], meta: { page: 1, total: 0, per_page: 25 } },
  });
  mocks.api.playbooks.mockResolvedValue({ data: { payload: [] } });
  mocks.api.savePlaybook.mockResolvedValue({ data: {} });
  mocks.api.batch.mockResolvedValue({ data: {} });
});
describe('Complementary CS review', () => {
  it.each([
    ['expansion', 2],
    ['surveys', 5],
  ])(
    'uses only the relevant %s KPIs and preserves record drilldown',
    async (mode, count) => {
      const w = mount(MetricsPanel, {
        props: {
          mode,
          inspect: true,
          metrics: {
            nps: -50,
            csat: 2,
            ces: 8,
            nps_promoters: 0,
            nps_detractors: 1,
            expansion_potential_cents: 100000,
            expansion_won_cents: 200000,
            bands: { critical: 1 },
            health_trend: [{ day: '2026-10-06', score: 40 }],
            renewals: { 30: 3 },
          },
        },
      });
      expect(w.findAll('button')).toHaveLength(count);
      expect(w.text()).not.toContain(labels.RELATIONSHIP.HEALTH_TREND);
      await w.findAll('button')[0].trigger('click');
      expect(w.emitted('inspect')[0][0]).toBe(
        mode === 'expansion' ? 'expansion_potential_cents' : 'nps'
      );
      w.unmount();
    }
  );
  it('exposes expansion product/evidence/commercial result and keeps rejected signals unconvertible', async () => {
    mocks.api.records.mockResolvedValue({
      data: {
        payload: [
          {
            id: 31,
            assignment_id: 19,
            customer_name: 'Native customer',
            title: 'Upgrade',
            status: 'converted',
            potential_cents: 200000,
            evidence: 'Observed usage',
            deal_id: 42,
            commercial_context: {
              product_name: 'Native product',
              expansion_kind: 'cross_sell',
              deal: { status: 'won' },
              won_cents: 210000,
            },
          },
          {
            id: 32,
            assignment_id: 19,
            customer_name: 'Native customer',
            title: 'Rejected',
            status: 'rejected',
            potential_cents: 0,
          },
        ],
        meta: { page: 1, total: 2, per_page: 25 },
      },
    });
    const w = page('expansion');
    await flushPromises();
    expect(w.text()).toContain('Native product');
    expect(w.text()).toContain('Observed usage');
    expect(w.text()).toContain(labels.RELATIONSHIP.DEAL_STATES.won);
    expect(w.findAll('thead th')).toHaveLength(11);
    expect(
      w
        .findAll('button')
        .some(b => b.text() === labels.RELATIONSHIP.CREATE_OPPORTUNITY)
    ).toBe(false);
    expect(w.findComponent(MetricsPanel).props('mode')).toBe('expansion');
    w.unmount();
  });
  it('shows actual zero survey score, comment and expiry without send/link actions for expired records', async () => {
    mocks.api.records.mockResolvedValue({
      data: {
        payload: [
          {
            id: 31,
            customer_name: 'Native customer',
            kind: 'nps',
            score: 0,
            comment: 'Needs follow-up',
            responded_at: '2026-10-06T12:00:00Z',
            delivery_status: 'responded',
            expires_at: '2026-11-01T12:00:00Z',
          },
          {
            id: 32,
            customer_name: 'Native customer',
            kind: 'ces',
            delivery_status: 'expired',
            expires_at: '2026-10-01T12:00:00Z',
          },
        ],
        meta: { page: 1, total: 2, per_page: 25 },
      },
    });
    const w = page('surveys');
    await flushPromises();
    const cells = w.findAll('tbody tr')[0].findAll('td');
    expect(cells[2].text()).toBe('0');
    expect(cells[3].text()).toBe('Needs follow-up');
    expect(w.text()).toContain(labels.RELATIONSHIP.STATES.expired);
    expect(
      w
        .findAll('button')
        .some(b =>
          [
            labels.RELATIONSHIP.SEND_SURVEY,
            labels.RELATIONSHIP.SURVEY_LINK,
          ].includes(b.text())
        )
    ).toBe(false);
    expect(w.findComponent(MetricsPanel).props('mode')).toBe('surveys');
    expect(w.text()).toContain(labels.RELATIONSHIP.NATIVE_CSAT_GUIDANCE);
    w.unmount();
  });
  it('keeps NICO priority dates in the account timezone', async () => {
    const w = page('overview');
    await flushPromises();
    expect(
      w.findComponent({ name: 'NicoSummaryPanel' }).props('metadata')
    ).toEqual(metadata);
    w.unmount();
  });
  it('does not load or configure playbooks without configuration permission', async () => {
    const w = mount(ConfigurationPanel, {
      props: { screen: 'playbooks', allowed: false },
    });
    await flushPromises();
    expect(mocks.api.playbooks).not.toHaveBeenCalled();
    expect(w.find('form').exists()).toBe(false);
    w.unmount();
  });
  it('keeps original step identities after removing a previous playbook step', async () => {
    mocks.api.playbooks.mockResolvedValue({
      data: {
        payload: [
          {
            id: 5,
            name: 'Retention',
            trigger_kind: 'health',
            active: true,
            steps: [
              { kind: 'activity', title: 'First', after_days: 0 },
              { kind: 'risk', title: 'Recovery', after_days: 1 },
            ],
          },
        ],
      },
    });
    const w = mount(ConfigurationPanel, {
      props: { screen: 'playbooks', allowed: true, metadata },
    });
    await flushPromises();
    await w
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.EDIT)
      .trigger('click');
    const form = w.get('form');
    await form
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.REMOVE_ITEM)
      .trigger('click');
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.api.savePlaybook).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        steps: [
          expect.objectContaining({
            title: 'Recovery',
            kind: 'risk',
            step_key: '1',
          }),
        ],
      }),
      5
    );
    w.unmount();
  });
  it('does not send duplicate configuration requests during save', async () => {
    let resolve;
    mocks.api.savePlaybook.mockReturnValue(
      new Promise(r => {
        resolve = r;
      })
    );
    mocks.api.playbooks.mockResolvedValue({
      data: {
        payload: [
          {
            id: 5,
            name: 'Retention',
            trigger_kind: 'health',
            active: true,
            steps: [{ kind: 'risk', title: 'Recovery', after_days: 0 }],
          },
        ],
      },
    });
    const w = mount(ConfigurationPanel, {
      props: { screen: 'playbooks', allowed: true, metadata },
    });
    await flushPromises();
    await w
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.EDIT)
      .trigger('click');
    await w.get('form').trigger('submit');
    await w.get('form').trigger('submit');
    expect(mocks.api.savePlaybook).toHaveBeenCalledTimes(1);
    resolve({ data: {} });
    await flushPromises();
    w.unmount();
  });
  it('shows actual native CSAT feedback in drilldown', () => {
    const w = shallowMount(MetricDrilldownPanel, {
      props: {
        data: {
          metric: 'csat',
          value: 2,
          total: 1,
          page: 1,
          per_page: 25,
          aggregation: 'average',
          payload: [
            {
              id: 8,
              source_type: 'CsatSurveyResponse',
              source_kind: 'csat_survey_response',
              label: '8',
              score: 2,
              comment: 'Native customer feedback',
            },
          ],
        },
      },
    });
    expect(w.text()).toContain('Native customer feedback');
    w.unmount();
  });
  it('preserves QBR decision identity after removing a previous commitment', async () => {
    const w = shallowMount(RecordEditor, {
      props: {
        kind: 'qbrs',
        metadata,
        record: {
          id: 5,
          assignment_id: 19,
          title: 'QBR',
          status: 'completed',
          scheduled_at: '2026-10-06T12:00:00Z',
          summary: 'Reviewed',
          decisions: [
            { title: 'A', due_at: '2026-10-10T12:00:00Z' },
            { title: 'B', due_at: '2026-10-11T12:00:00Z' },
          ],
        },
      },
    });
    const buttons = w
      .findAll('button')
      .filter(b => b.text() === labels.RELATIONSHIP.REMOVE_ITEM);
    await buttons[0].trigger('click');
    await w.get('form').trigger('submit');
    expect(w.text()).not.toContain('decision_key');
    expect(w.emitted('save')[0][0].decisions[0]).toEqual(
      expect.objectContaining({ title: 'B', decision_key: '1' })
    );
    w.unmount();
  });
  it('completes a batch without silently overwriting priority or owner', async () => {
    mocks.api.records.mockResolvedValue({
      data: {
        payload: [
          {
            id: 31,
            assignment_id: 19,
            customer_name: 'Native customer',
            reason: 'Follow-up',
            status: 'open',
            priority: 90,
          },
        ],
        meta: { page: 1, total: 1, per_page: 25 },
      },
    });
    const w = page('actions');
    await flushPromises();
    await w.get('tbody input[type="checkbox"]').setValue(true);
    await w
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.BATCH.replace('{count}', '1'))
      .trigger('click');
    await w.get('[data-testid="batch-result"]').setValue('Done');
    await w
      .get('[data-testid="batch-result"]')
      .element.closest('form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();
    expect(mocks.api.batch).toHaveBeenCalledWith(
      '1',
      [31],
      expect.objectContaining({
        status: 'completed',
        result: 'Done',
        priority: undefined,
        owner_id: undefined,
      })
    );
    w.unmount();
  });
  it('assigns and reprioritizes a batch without changing its status', async () => {
    mocks.api.records.mockResolvedValue({
      data: {
        payload: [
          {
            id: 31,
            assignment_id: 19,
            customer_name: 'Native customer',
            reason: 'Follow-up',
            status: 'open',
          },
        ],
        meta: { page: 1, total: 1, per_page: 25 },
      },
    });
    const w = page('actions');
    await flushPromises();
    await w.get('tbody input[type="checkbox"]').setValue(true);
    await w
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.BATCH.replace('{count}', '1'))
      .trigger('click');
    await w.get('[data-testid="batch-status"]').setValue('');
    await w.get('[data-testid="batch-priority"]').setValue('88');
    await w.get('[data-testid="batch-owner"]').setValue('7');
    await w
      .get('[data-testid="batch-status"]')
      .element.closest('form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();
    expect(mocks.api.batch).toHaveBeenCalledWith(
      '1',
      [31],
      expect.objectContaining({ status: undefined, priority: 88, owner_id: 7 })
    );
    w.unmount();
  });
  it('configures product-specific playbooks using native metadata references', async () => {
    mocks.api.playbooks.mockResolvedValue({
      data: {
        payload: [
          {
            id: 5,
            name: 'Product follow-up',
            trigger_kind: 'health',
            active: true,
            conditions: [{ field: 'health_score', operator: 'lt', value: 60 }],
            steps: [{ kind: 'risk', title: 'Recovery', after_days: 0 }],
          },
        ],
      },
    });
    const w = mount(ConfigurationPanel, {
      props: {
        screen: 'playbooks',
        allowed: true,
        metadata: {
          ...metadata,
          products: [[9, 'Native product']],
          segments: [[2, 'Native segment']],
          units: [[3, 'Native unit']],
        },
      },
    });
    await flushPromises();
    await w
      .findAll('button')
      .find(b => b.text() === labels.RELATIONSHIP.EDIT)
      .trigger('click');
    const form = w.get('form');
    await form
      .get(`select[aria-label="${labels.RELATIONSHIP.FIELDS.metric}"]`)
      .setValue('product_id');
    expect(
      form
        .get(`select[aria-label="${labels.RELATIONSHIP.OPERATOR}"]`)
        .findAll('option')
        .map(o => o.attributes('value'))
    ).toEqual(['eq']);
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.api.savePlaybook).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        conditions: [{ field: 'product_id', operator: 'eq', value: 9 }],
      }),
      5
    );
    w.unmount();
  });
  it('offers finance waiting for action edits and batches and routes its own metric', async () => {
    const editor = mount(RecordEditor, {
      props: {
        kind: 'actions',
        metadata,
        record: {
          id: 1,
          assignment_id: 19,
          status: 'open',
          reason: 'Native action',
        },
      },
    });
    const state = editor
      .findAll('select')
      .find(field => field.find('option[value="waiting_finance"]').exists());
    expect(state).toBeTruthy();
    await state.setValue('waiting_finance');
    await editor.get('form').trigger('submit');
    expect(editor.emitted('save')[0][0].status).toBe('waiting_finance');
    editor.unmount();
    const w = page('actions');
    await flushPromises();
    expect(w.find('option[value="waiting_finance"]').exists()).toBe(true);
    w.findComponent(MetricsPanel).vm.$emit('filter', 'waiting_finance_actions');
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'jrc_relationship_actions',
      params: { accountId: '1' },
      query: { status: 'waiting_finance' },
    });
    w.unmount();
    const metrics = mount(MetricsPanel, {
      props: { mode: 'actions', metrics: { waiting_finance_actions: 4 } },
    });
    const card = metrics
      .findAll('button')
      .find(b =>
        b.text().includes(labels.RELATIONSHIP.METRICS.waiting_finance_actions)
      );
    expect(card.get('strong').text()).toBe('4');
    await card.trigger('click');
    expect(metrics.emitted('filter')[0][0]).toBe('waiting_finance_actions');
    metrics.unmount();
  });
});
