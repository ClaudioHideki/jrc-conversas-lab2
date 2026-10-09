import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import HelpdeskKpis from './HelpdeskKpis.vue';
import HelpdeskDailyReport from './HelpdeskDailyReport.vue';
import HelpdeskReportHistory from './HelpdeskReportHistory.vue';
import HelpdeskGroupPreview from './HelpdeskGroupPreview.vue';
import HelpdeskPolicyForm from './HelpdeskPolicyForm.vue';
import HelpdeskReportFilters from './HelpdeskReportFilters.vue';
import API from 'dashboard/api/jrcNicoHelpdesk';
import {
  helpdeskGroupDefaults,
  helpdeskMetricValue,
  helpdeskRows,
  helpdeskGroupInput,
} from './helpdeskPresentation';

const mocks = vi.hoisted(() => ({
  api: { groupPreview: vi.fn(), groupPrepare: vi.fn() },
}));
vi.mock('dashboard/api/jrcNicoHelpdesk', () => ({ default: mocks.api }));
const translate = (key, params) =>
  `${key}${params ? ` ${Object.values(params).join(' ')}` : ''}`;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: translate }) }));
const globals = {
  mocks: { $t: translate },
  stubs: { HelpdeskGroupFields: true },
};
const window = { from: '2026-10-08T00:00:00Z', until: '2026-10-08T18:00:00Z' };
const metric = (key, evidence = {}) => ({
  key,
  state: 'available',
  numerator: 1,
  denominator: 2,
  value: 50,
  unit: 'percent',
  formula: 'native numerator / exact cohort',
  window,
  target: '<10%',
  evidence,
});
const group = (overrides = {}) => ({
  contract_version: 1,
  event_id: 8,
  group_key: 'D2',
  phase: 1,
  enabled: true,
  executable: true,
  preview: true,
  persisted: false,
  automatic_execution: false,
  preview_digest: 'a'.repeat(64),
  source: { ticket_id: 21, unit_id: 3, company_id: 4, rule_key: 'R11' },
  evidence: [{ kind: 'Ticket', id: 21 }],
  missing: [],
  required_fields: [],
  attempts: { recorded: 0, limit: 2, handoff_required: false },
  actions: [
    {
      tool: 'add_service_ticket_note',
      arguments: { ticket_id: 21, body: 'Exact server-reviewed internal note' },
      can_prepare: true,
    },
  ],
  ...overrides,
});
const groupPage = () =>
  mount(HelpdeskGroupPreview, {
    props: {
      accountId: 12,
      contextKey: '12:7:admin',
      event: { id: 8, ticket_id: 21, rule_key: 'R11' },
      catalog: [{ key: 'D2', name: 'Human triage' }],
    },
    global: globals,
  });

beforeEach(() => {
  mocks.api.groupPreview.mockResolvedValue({ data: group() });
  mocks.api.groupPrepare.mockResolvedValue({ data: { id: 9 } });
});

describe('R5 native HelpDesk evidence and presentation', () => {
  it('retains raw zeros, false and unavailable measurements without inventing percentage values', () => {
    expect(
      helpdeskRows(
        { covered: 0, delivered: false, unavailable: null },
        'NO_DATA'
      )
    ).toEqual([
      { field: 'covered', value: '0' },
      { field: 'delivered', value: 'false' },
      { field: 'unavailable', value: 'NO_DATA' },
    ]);
    expect(
      helpdeskMetricValue(
        { state: 'sem_dados', value: 0, unit: 'percent' },
        'NO_DATA'
      )
    ).toBe('NO_DATA');
    expect(
      helpdeskMetricValue(
        { state: 'available', value: 0, unit: 'percent' },
        'NO_DATA'
      )
    ).toBe('0.0%');
    expect(
      helpdeskMetricValue(
        { state: 'available', value: null, unit: 'percent' },
        'NO_DATA'
      )
    ).toBe('NO_DATA');
  });

  it('shows K1 human and unknown coverage while autonomous evidence remains unavailable', () => {
    const wrapper = mount(HelpdeskKpis, {
      props: {
        report: {
          interval: window,
          metrics: [
            {
              ...metric('K1', {
                coverage: {
                  observed: 12,
                  covered_human: 5,
                  human_approved_nico: 2,
                  unknown: 5,
                  autonomous_supported: 0,
                },
                closure_ids: [15, 16],
              }),
              state: 'sem_dados',
              numerator: null,
              value: null,
            },
          ],
        },
      },
      global: globals,
    });
    const result = wrapper.find('[data-testid="helpdesk-kpi-K1"]');
    expect(result.text()).toContain('JRC_NICO_HELPDESK.COVERAGE.covered_human');
    expect(result.text()).toContain('JRC_NICO_HELPDESK.COVERAGE.unknown');
    expect(result.text()).toContain('JRC_NICO_HELPDESK.NO_DATA');
    expect(result.text()).not.toContain('0.0%');
    expect(result.text()).toContain(window.from);
    expect(result.text()).toContain(window.until);
    wrapper.unmount();
  });

  it('renders both C10 observations with their own denominators and elapsed seconds rather than silently choosing one', () => {
    const evidence = {
      source_conflict: { code: 'C10', resolved: false },
      observations: [
        {
          key: 'resolution_sla_overrun_72h',
          basis: 'calendar',
          numerator: 1,
          denominator: 2,
          value: 50,
          unknown: 1,
        },
        {
          key: 'age_at_close_72h',
          basis: 'calendar',
          numerator: 2,
          denominator: 4,
          value: 50,
          unknown: 0,
        },
      ],
    };
    const wrapper = mount(HelpdeskKpis, {
      props: {
        report: {
          interval: window,
          metrics: [
            metric('K3', evidence),
            metric('K5', {
              maximum_seconds: 1200,
              elapsed_seconds: [480, 900],
              elapsed_minutes: [8, 15],
              median_seconds: 690,
              p95_seconds: 900,
              coverage: { missing_delivery: 1 },
            }),
          ],
        },
      },
      global: globals,
    });
    expect(wrapper.text()).toContain('C10');
    expect(
      wrapper.find('[data-observation="resolution_sla_overrun_72h"]').text()
    ).toContain('JRC_NICO_HELPDESK.DENOMINATOR 2');
    expect(
      wrapper.find('[data-observation="age_at_close_72h"]').text()
    ).toContain('JRC_NICO_HELPDESK.DENOMINATOR 4');
    expect(wrapper.text()).toContain('480, 900');
    expect(wrapper.text()).toContain('8, 15');
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.MEDIAN_SECONDS');
    expect(wrapper.text()).toContain('690');
    expect(wrapper.text()).toContain(
      'JRC_NICO_HELPDESK.COVERAGE.missing_delivery'
    );
    wrapper.unmount();
  });

  it('separates the local-day events from prior backlog and renders actual KPI evidence in the daily preview', () => {
    const wrapper = mount(HelpdeskDailyReport, {
      props: {
        report: {
          window: { ...window, basis: 'local_day' },
          cutoff_at: window.until,
          timezone: 'UTC',
          new_overdue_today: [21],
          previous_backlog: [13],
          new_event_ids: [34],
          previous_event_ids: [22],
          overdue: [],
          complaints: [],
          recurrent: [],
          legal_risk_internal_only: [],
          kpis: {
            interval: window,
            metrics: [
              metric('K7', {
                eligible_decisions: 3,
                responded: 2,
                scheduled: 1,
                sent: 1,
                expired: 0,
                survey_ids: [91],
              }),
            ],
          },
          evidence_resources: [{ type: 'ClosureCycle', id: 35 }],
        },
      },
      global: globals,
    });
    expect(wrapper.text()).toContain('local_day');
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.NEW_EVENTS 34');
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.PREVIOUS_EVENTS 22');
    expect(wrapper.find('[data-testid="helpdesk-kpi-K7"]').text()).toContain(
      'eligible_decisions'
    );
    expect(wrapper.text()).toContain('ClosureCycle');
    expect(wrapper.findAll('button')).toHaveLength(0);
    wrapper.unmount();
  });

  it('distinguishes dispatch in progress, provider acceptance and delivery evidence in existing history', () => {
    const wrapper = mount(HelpdeskReportHistory, {
      props: {
        history: {
          reports: [
            {
              id: 91,
              report_date: '2026-10-08',
              timezone: 'UTC',
              cutoff_at: window.until,
              receipts: [
                {
                  id: 1,
                  channel: 'email',
                  state: 'dispatching',
                  sent_at: null,
                  delivered_at: null,
                  attempt_number: 1,
                },
                {
                  id: 2,
                  channel: 'nico',
                  state: 'sent',
                  sent_at: window.until,
                  delivered_at: null,
                  attempt_number: 1,
                },
                {
                  id: 3,
                  channel: 'nico',
                  state: 'delivered',
                  sent_at: window.until,
                  delivered_at: window.until,
                  attempt_number: 1,
                },
              ],
            },
          ],
          next_page: 2,
        },
      },
      global: globals,
    });
    expect(wrapper.text()).toContain(
      'JRC_NICO_HELPDESK.RECEIPT_STATES.dispatching'
    );
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.RECEIPT_STATES.sent');
    expect(wrapper.text()).toContain(
      'JRC_NICO_HELPDESK.RECEIPT_STATES.delivered'
    );
    expect(wrapper.text()).toContain(
      'JRC_NICO_HELPDESK.RECEIPT_DELIVERED JRC_NICO_HELPDESK.NO_DATA'
    );
    expect(wrapper.findAll('button').map(item => item.text())).toEqual(
      expect.arrayContaining(['JRC_NICO_HELPDESK.NEXT_PAGE'])
    );
    expect(wrapper.text()).not.toContain('SEND');
    wrapper.unmount();
  });

  it('uses OFF group defaults for every legacy policy and keeps enabled choices exact', () => {
    expect(Object.keys(helpdeskGroupDefaults())).toHaveLength(11);
    expect(
      Object.values(helpdeskGroupDefaults()).every(
        item => item.enabled === false
      )
    ).toBe(true);
    expect(
      helpdeskGroupDefaults({ D1: { enabled: true }, E: { enabled: 'true' } })
        .D1.enabled
    ).toBe(true);
    expect(helpdeskGroupDefaults({ E: { enabled: 'true' } }).E.enabled).toBe(
      false
    );
  });

  it('narrows report choices to the selected policy without choosing a first Unit or company and validates the interval', async () => {
    const wrapper = mount(HelpdeskReportFilters, {
      props: {
        policy: {
          id: 8,
          definition: { unit_ids: [3], company_ids: [4], operator_ids: [7] },
        },
        options: {
          units: [
            { id: 3, name: 'Allowed Unit' },
            { id: 9, name: 'Other Unit' },
          ],
          companies: [
            { id: 4, name: 'Policy company' },
            { id: 10, name: 'Other company' },
          ],
          operators: [
            { id: 7, name: 'Allowed operator' },
            { id: 11, name: 'Other operator' },
          ],
        },
      },
      global: globals,
    });
    expect(wrapper.findAll('option').map(item => item.text())).toEqual([
      'Allowed Unit',
      'Policy company',
      'Allowed operator',
    ]);
    expect(wrapper.emitted('change')[0][0].filters).toEqual({});
    await wrapper.find('[data-testid="helpdesk-filter-units"]').setValue(['3']);
    await wrapper
      .find('[data-testid="helpdesk-filter-companies"]')
      .setValue(['4']);
    await wrapper
      .find('[data-testid="helpdesk-filter-operators"]')
      .setValue(['7']);
    expect(wrapper.emitted('change').at(-1)[0].filters).toEqual({
      unit_ids: [3],
      company_ids: [4],
      assignee_account_user_ids: [7],
    });
    await wrapper
      .find('[data-testid="helpdesk-kpi-from"]')
      .setValue('2026-10-08T12:00');
    await wrapper
      .find('[data-testid="helpdesk-kpi-until"]')
      .setValue('2026-10-08T11:00');
    expect(wrapper.emitted('change').at(-1)[0].valid).toBe(false);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('adds OFF group switches to a legacy policy without mutating it and saves only deliberate choices in the new draft', async () => {
    const rules = Object.fromEntries(
      Array.from({ length: 16 }, (_, index) => [
        `R${String(index + 1).padStart(2, '0')}`,
        { enabled: false, recipients: [], channels: ['nico'] },
      ])
    );
    rules.R12.priority_ids = {};
    const definition = {
      unit_ids: [],
      company_ids: [],
      operator_ids: [],
      priority_order: {},
      roles: { thiago: [] },
      hourly_limit: 10,
      approval_ttl_seconds: 600,
      rules,
      daily: {
        enabled: false,
        timezone: 'UTC',
        recipients: [],
        channels: ['nico'],
      },
    };
    const wrapper = mount(HelpdeskPolicyForm, {
      props: {
        definition,
        options: { units: [], companies: [], operators: [], priorities: [] },
      },
      global: globals,
    });
    expect(wrapper.findAll('[data-group-policy]')).toHaveLength(11);
    expect(
      wrapper
        .findAll('[data-group-policy]')
        .every(item => item.element.checked === false)
    ).toBe(true);
    await wrapper.find('[data-group-policy="D1"]').setValue(true);
    await wrapper.find('form').trigger('submit');
    const saved = wrapper.emitted('save')[0][0];
    expect(saved.groups.D1.enabled).toBe(true);
    expect(saved.groups.A1.enabled).toBe(false);
    expect(definition.groups).toBeUndefined();
    expect(saved.rules).toEqual(definition.rules);
    wrapper.unmount();
  });

  it('associates the conditional group labels with their controls and clears choices without an automatic API call', async () => {
    const wrapper = groupPage();
    await wrapper.setProps({
      catalog: ['E', 'C2', 'D2'].map(key => ({ key, name: key })),
    });
    const label = key =>
      wrapper.find(`[data-testid="helpdesk-group-${key}-label"]`);
    await wrapper.find('select').setValue('E');
    expect(label('query').element.control).toBe(
      label('query').find('input').element
    );
    expect(label('summary').element.control).toBe(
      label('summary').find('textarea').element
    );
    expect(label('binding').exists()).toBe(false);
    expect(label('conversation').exists()).toBe(false);
    await label('query').find('input').setValue('Exact customer query');
    await label('summary').find('textarea').setValue('Reviewed query');
    expect(API.groupPreview).not.toHaveBeenCalled();
    expect(API.groupPrepare).not.toHaveBeenCalled();

    await wrapper.find('select').setValue('C2');
    expect(label('query').exists()).toBe(false);
    expect(label('summary').find('textarea').element.value).toBe('');
    ['binding', 'conversation'].forEach(key => {
      const field = label(key).find('input');
      expect(label(key).element.control).toBe(field.element);
      expect(field.attributes('type')).toBe('number');
      expect(field.attributes('min')).toBe('1');
      expect(field.element.value).toBe('');
    });
    await label('binding').find('input').setValue('4');
    await label('conversation').find('input').setValue('91');
    await label('summary')
      .find('textarea')
      .setValue('Reviewed broker identity');
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: group({ group_key: 'C2' }),
    });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(API.groupPreview).toHaveBeenCalledWith(12, {
      event_id: 8,
      group_key: 'C2',
      input: {
        binding_id: 4,
        conversation_id: 91,
        summary: 'Reviewed broker identity',
      },
    });
    expect(API.groupPrepare).not.toHaveBeenCalled();

    await wrapper.find('select').setValue('D2');
    expect(label('binding').exists()).toBe(false);
    expect(label('conversation').exists()).toBe(false);
    expect(label('summary').element.control).toBe(
      label('summary').find('textarea').element
    );
    expect(label('summary').find('textarea').element.value).toBe('');
    expect(API.groupPreview).toHaveBeenCalledTimes(1);
    expect(API.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('previews and prepares the exact reviewed native action digest through existing approvals, never executes it', async () => {
    const wrapper = groupPage();
    expect(wrapper.find('select').element.value).toBe('');
    await wrapper.find('select').setValue('D2');
    await wrapper
      .find('[data-testid="helpdesk-group-summary"]')
      .setValue('Operator reviewed evidence');
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(API.groupPreview).toHaveBeenCalledWith(12, {
      event_id: 8,
      group_key: 'D2',
      input: { summary: 'Operator reviewed evidence' },
    });
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    await flushPromises();
    expect(API.groupPrepare).toHaveBeenCalledWith(12, {
      event_id: 8,
      group_key: 'D2',
      input: { summary: 'Operator reviewed evidence' },
      tool: 'add_service_ticket_note',
      arguments: group().actions[0].arguments,
      preview_digest: 'a'.repeat(64),
    });
    expect(wrapper.emitted('prepared')).toHaveLength(1);
    wrapper.unmount();
  });

  it('requires a new preview after input changes and cannot prepare an OFF group', async () => {
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: group({ enabled: false, executable: false }),
    });
    const wrapper = groupPage();
    await wrapper.find('select').setValue('D2');
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').element.disabled
    ).toBe(true);
    mocks.api.groupPreview.mockResolvedValueOnce({ data: group() });
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    await wrapper
      .find('[data-testid="helpdesk-group-summary"]')
      .setValue('Changed action context');
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').element.disabled
    ).toBe(true);
    await wrapper
      .find('[data-testid="helpdesk-group-prepare"]')
      .trigger('click');
    expect(API.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('rejects a preview from another native ticket and clears a late operator response', async () => {
    mocks.api.groupPreview.mockResolvedValueOnce({
      data: group({ source: { ...group().source, ticket_id: 22 } }),
    });
    const wrapper = groupPage();
    await wrapper.find('select').setValue('D2');
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').exists()
    ).toBe(false);
    let resolve;
    mocks.api.groupPreview.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await wrapper
      .find('[data-testid="helpdesk-group-run-preview"]')
      .trigger('click');
    await wrapper.setProps({ contextKey: '12:8:agent' });
    resolve({ data: group() });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="helpdesk-group-prepare"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('keeps explicit canonical choices, omits blank values and never chooses a broker conversation', () => {
    expect(
      helpdeskGroupInput({
        query: '',
        summary: ' Reviewed ',
        binding_id: '',
        conversation_id: '',
        classification: {
          category_id: '',
          ticket_type_id: '3',
          service_fields: { priority_reason: 'reviewed' },
        },
        handoff: { queue_id: '', assignee_account_user_id: '5' },
      })
    ).toEqual({
      summary: 'Reviewed',
      classification: {
        ticket_type_id: 3,
        service_fields: { priority_reason: 'reviewed' },
      },
      handoff: { assignee_account_user_id: 5 },
    });
  });
});
