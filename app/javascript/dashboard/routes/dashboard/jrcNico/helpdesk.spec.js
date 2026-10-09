import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import HelpdeskPage from './HelpdeskPage.vue';
import HelpdeskPolicyForm from './HelpdeskPolicyForm.vue';
import { helpdeskGuard } from './routes';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    show: vi.fn(),
    events: vi.fn(),
    approvals: vi.fn(),
    prepare: vi.fn(),
    approve: vi.fn(),
    cancel: vi.fn(),
    kpis: vi.fn(),
    report: vi.fn(),
    reports: vi.fn(),
    reportHistory: vi.fn(),
    groupPreview: vi.fn(),
    groupPrepare: vi.fn(),
    createPolicy: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcNicoHelpdesk', () => ({ default: mocks.api }));

const response = account => ({
  data: {
    account_id: account,
    catalog: [],
    policies: [],
    options: {},
    can_manage: false,
  },
});
const event = (id, evidence) => ({
  id,
  ticket_id: id,
  rule_key: 'R01',
  state: 'detected',
  evidence: { description: evidence },
});
const page = () =>
  mount(HelpdeskPage, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: { template: '<a><slot /></a>' },
        HelpdeskPolicyForm: true,
      },
    },
  });
const button = (wrapper, label) =>
  wrapper
    .findAll('button')
    .find(item => item.text() === `JRC_NICO_HELPDESK.${label}`);

beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = {
    getters: reactive({ getCurrentUserID: 7, getCurrentRole: 'administrator' }),
  };
  mocks.api.show.mockImplementation(account =>
    Promise.resolve(response(account))
  );
  mocks.api.events.mockResolvedValue({ data: { events: [] } });
  mocks.api.approvals.mockResolvedValue({ data: { approvals: [] } });
  mocks.api.reports.mockResolvedValue({
    data: { reports: [], page: 1, next_page: null },
  });
});

describe('NICO HelpDesk permission and native-action review', () => {
  it('requires a deliberate R12 target from the selected Unit and excludes targets after removing that Unit', async () => {
    const rules = Object.fromEntries(
      Array.from({ length: 16 }, (_, index) => [
        `R${String(index + 1).padStart(2, '0')}`,
        { enabled: false, recipients: [], channels: ['nico'] },
      ])
    );
    rules.R12 = { ...rules.R12, critical_company_ids: [4], priority_ids: {} };
    const definition = {
      unit_ids: [3],
      company_ids: [4],
      operator_ids: [7],
      priority_order: {},
      roles: { thiago: [7] },
      hourly_limit: 10,
      approval_ttl_seconds: 600,
      rules,
      daily: {
        enabled: false,
        timezone: 'America/Sao_Paulo',
        recipients: [],
        channels: ['nico'],
      },
    };
    const wrapper = mount(HelpdeskPolicyForm, {
      props: {
        definition,
        options: {
          units: [
            { id: 3, name: 'Granted Unit' },
            { id: 5, name: 'Other Unit' },
          ],
          companies: [{ id: 4, name: 'Pilot company' }],
          operators: [],
          priorities: [
            { id: 80, unit_id: 3, name: 'Chosen high priority' },
            { id: 99, unit_id: 5, name: 'Other Unit priority' },
          ],
        },
      },
      global: { mocks: { $t: key => key } },
    });
    const selector = wrapper.find('[data-priority-unit="3"]');
    expect(selector.find('option[value="99"]').exists()).toBe(false);
    expect(selector.element.value).not.toBe('80');
    await selector.setValue('80');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].rules.R12.priority_ids).toEqual({
      3: 80,
    });
    await wrapper.find('select[multiple]').setValue([]);
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('save')[1][0].rules.R12.priority_ids).toEqual({});
    wrapper.unmount();
  });

  it('requires an authorized response for exactly the requested account before entering', async () => {
    expect(await helpdeskGuard({ params: { accountId: '12' } })).toBe(true);
    mocks.api.show.mockResolvedValueOnce(response(13));
    expect(await helpdeskGuard({ params: { accountId: '12' } })).toEqual({
      name: 'jrc_service_desk_denied',
      params: { accountId: 12 },
    });
    mocks.api.show.mockRejectedValueOnce({ response: { status: 403 } });
    expect(await helpdeskGuard({ params: { accountId: '12' } })).toEqual({
      name: 'jrc_service_desk_denied',
      params: { accountId: 12 },
    });
    expect(await helpdeskGuard({ params: { accountId: 'invalid' } })).toBe(
      false
    );
  });

  it('ignores late evidence from the old account after switching to a new account', async () => {
    let resolveOld;
    mocks.api.events.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = page();
    await flushPromises();
    mocks.api.events.mockResolvedValue({
      data: { events: [event(22, 'Current account evidence')] },
    });
    mocks.route.params.accountId = '13';
    await flushPromises();
    resolveOld({
      data: { events: [event(11, 'Prior account private evidence')] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Current account evidence');
    expect(wrapper.text()).not.toContain('Prior account private evidence');
    expect(mocks.api.events).toHaveBeenLastCalledWith(13);
    wrapper.unmount();
  });

  it('clears evidence immediately when the operator changes in the same account and ignores their late response', async () => {
    mocks.api.events.mockResolvedValueOnce({
      data: { events: [event(1, 'Operator seven evidence')] },
    });
    const wrapper = page();
    await flushPromises();
    expect(wrapper.text()).toContain('Operator seven evidence');
    let resolveRevoked;
    mocks.api.events.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveRevoked = resolve;
        })
    );
    await button(wrapper, 'REFRESH').trigger('click');
    mocks.api.show.mockRejectedValueOnce({ response: { status: 403 } });
    mocks.store.getters.getCurrentUserID = 8;
    await flushPromises();
    expect(wrapper.text()).not.toContain('Operator seven evidence');
    resolveRevoked({
      data: { events: [event(2, 'Revoked operator late evidence')] },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Revoked operator late evidence');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('clears authorized evidence after permissions are revoked and rejects an account-mismatched response', async () => {
    mocks.api.events.mockResolvedValueOnce({
      data: { events: [event(1, 'Authorized evidence')] },
    });
    const wrapper = page();
    await flushPromises();
    mocks.api.show.mockRejectedValueOnce({
      response: { status: 403, data: { error: 'Private server detail' } },
    });
    await button(wrapper, 'REFRESH').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Authorized evidence');
    expect(wrapper.text()).not.toContain('Private server detail');
    mocks.api.show.mockResolvedValueOnce(response(13));
    mocks.api.events.mockResolvedValueOnce({
      data: { events: [event(2, 'Foreign evidence')] },
    });
    await button(wrapper, 'REFRESH').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Foreign evidence');
    wrapper.unmount();
  });

  it('shows exact approval payload, scope and expiry and approves only its digest', async () => {
    const approval = {
      id: 9,
      state: 'pending',
      tool: 'add_service_ticket_note',
      arguments: { ticket_id: 17, body: 'Exact proposed internal note' },
      scope: { unit_id: 3, company_id: 4 },
      expires_at: '2099-10-08T18:00:00Z',
      payload_digest: 'exact-payload-fingerprint',
    };
    mocks.api.approvals.mockResolvedValueOnce({
      data: { approvals: [approval] },
    });
    mocks.api.approve.mockResolvedValue({ data: {} });
    const wrapper = page();
    await flushPromises();
    expect(wrapper.text()).toContain('Exact proposed internal note');
    expect(wrapper.text()).toContain('exact-payload-fingerprint');
    expect(wrapper.text()).toContain('2099');
    await button(wrapper, 'APPROVE').trigger('click');
    await flushPromises();
    expect(mocks.api.approve).toHaveBeenCalledWith(12, approval);
    wrapper.unmount();
  });

  it('prepares the explicit priority preview without executing it or sending a customer message', async () => {
    const argumentsValue = {
      ticket_id: 17,
      expected_lock_version: 3,
      priority_id: 5,
    };
    mocks.api.events.mockResolvedValueOnce({
      data: {
        events: [
          {
            ...event(17, 'Recurrent case'),
            state: 'prepared',
            result: {
              priority_arguments: argumentsValue,
              tools: ['update_service_ticket'],
            },
          },
        ],
      },
    });
    mocks.api.prepare.mockResolvedValue({ data: {} });
    const wrapper = page();
    await flushPromises();
    await button(wrapper, 'PREPARE').trigger('click');
    await flushPromises();
    expect(mocks.api.prepare).toHaveBeenCalledWith(12, {
      event_id: 17,
      tool: 'update_service_ticket',
      arguments: argumentsValue,
    });
    expect(mocks.api.approve).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('renders KPI formulas, windows, observed denominators and no-data evidence', async () => {
    const context = response(12);
    context.data.policies = [{ id: 1, number: 1, state: 'published' }];
    mocks.api.show.mockResolvedValueOnce(context);
    const window = {
      from: '2026-09-08T00:00:00Z',
      until: '2026-10-08T18:00:00Z',
    };
    mocks.api.kpis.mockResolvedValue({
      data: {
        interval: window,
        metrics: [
          {
            key: 'K1',
            numerator: null,
            denominator: 12,
            value: null,
            state: 'sem_dados',
            window,
            reason: 'confirmed_trace_required',
            evidence: { excluded: 'suggestions' },
          },
        ],
      },
    });
    const wrapper = page();
    await flushPromises();
    await button(wrapper, 'KPIS').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.KPI_FORMULAS.K1');
    expect(wrapper.text()).toContain('12');
    expect(wrapper.text()).toContain('confirmed_trace_required');
    expect(wrapper.text()).toContain('suggestions');
    expect(wrapper.text()).toContain('JRC_NICO_HELPDESK.NO_DATA');
    expect(wrapper.text()).not.toContain('0.0%');
    wrapper.unmount();
  });

  it('uses the native history GETs, verifies detail identity and clears current evidence on revocation', async () => {
    const context = response(12);
    context.data.policies = [{ id: 8, number: 1, state: 'published' }];
    mocks.api.show.mockResolvedValue(context);
    const report = {
      id: 91,
      report_date: '2026-10-08',
      timezone: 'UTC',
      cutoff_at: '2026-10-08T18:00:00Z',
      receipts: [],
    };
    mocks.api.reports.mockResolvedValueOnce({
      data: { reports: [report], page: 1, next_page: 2 },
    });
    mocks.api.reportHistory.mockResolvedValueOnce({
      data: {
        ...report,
        payload: { complaints: ['Protected report evidence'] },
      },
    });
    const wrapper = page();
    await flushPromises();
    await button(wrapper, 'REPORT_HISTORY').trigger('click');
    await flushPromises();
    expect(mocks.api.reports).toHaveBeenCalledWith(12, 8, 1);
    await wrapper.find('[data-report-id="91"]').trigger('click');
    await flushPromises();
    expect(mocks.api.reportHistory).toHaveBeenCalledWith(12, 91);
    expect(wrapper.text()).toContain('Protected report evidence');
    mocks.api.reportHistory.mockRejectedValueOnce({
      response: { status: 403, data: { error: 'Private provider detail' } },
    });
    await wrapper.find('[data-report-id="91"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Protected report evidence');
    expect(wrapper.text()).not.toContain('Private provider detail');
    expect(
      wrapper.find('[data-testid="helpdesk-report-history"]').exists()
    ).toBe(false);
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('ignores a late history response after an Account or operator switch', async () => {
    const context = response(12);
    context.data.policies = [{ id: 8, number: 1, state: 'published' }];
    mocks.api.show.mockResolvedValueOnce(context);
    let resolve;
    mocks.api.reports.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = page();
    await flushPromises();
    await button(wrapper, 'REPORT_HISTORY').trigger('click');
    mocks.store.getters.getCurrentUserID = 8;
    await flushPromises();
    resolve({
      data: {
        reports: [
          { id: 9, report_date: 'Revoked history evidence', receipts: [] },
        ],
        page: 1,
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Revoked history evidence');
    expect(
      wrapper.find('[data-testid="helpdesk-report-history"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('rejects another report identity instead of displaying its payload', async () => {
    const context = response(12);
    context.data.policies = [{ id: 8, number: 1, state: 'published' }];
    mocks.api.show.mockResolvedValueOnce(context);
    mocks.api.reports.mockResolvedValueOnce({
      data: { reports: [{ id: 9, receipts: [] }], page: 1 },
    });
    mocks.api.reportHistory.mockResolvedValueOnce({
      data: { id: 10, payload: { complaints: ['Foreign report'] } },
    });
    const wrapper = page();
    await flushPromises();
    await button(wrapper, 'REPORT_HISTORY').trigger('click');
    await flushPromises();
    await wrapper.find('[data-report-id="9"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Foreign report');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('prepares an explicit native project task for R02 without approval or outbound delivery', async () => {
    mocks.api.events.mockResolvedValueOnce({
      data: {
        events: [
          {
            ...event(31, 'Native linked project'),
            ticket_id: 72,
            rule_key: 'R02',
            state: 'prepared',
            result: { tools: ['create_project_task'] },
          },
        ],
      },
    });
    mocks.api.prepare.mockResolvedValueOnce({ data: {} });
    const wrapper = page();
    await flushPromises();
    await wrapper.find('[data-task-event="31"]').trigger('click');
    const form = wrapper.find('[data-task-form="31"]');
    expect(form.find('[name="project_id"]').element.value).toBe('');
    expect(form.find('[name="board_column_id"]').element.value).toBe('');
    await form.find('[name="project_id"]').setValue('45');
    await form.find('[name="board_column_id"]').setValue('56');
    await form.find('[name="title"]').setValue(' Deliberate reviewed task ');
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.api.prepare).toHaveBeenCalledWith(12, {
      event_id: 31,
      tool: 'create_project_task',
      arguments: {
        ticket_id: 72,
        project_id: 45,
        board_column_id: 56,
        title: 'Deliberate reviewed task',
      },
    });
    expect(mocks.api.approve).not.toHaveBeenCalled();
    expect(mocks.api.groupPrepare).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
