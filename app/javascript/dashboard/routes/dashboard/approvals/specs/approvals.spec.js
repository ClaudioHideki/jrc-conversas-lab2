import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import { approvalClient } from 'dashboard/api/approvals';
import { useApprovals } from '../useApprovals';
import { useApprovalAccess } from 'dashboard/composables/useApprovalAccess';
import { routes } from '../routes';
import {
  STATES,
  OPERATORS,
  emptyDefinition,
  emptyStep,
  moneyCents,
  parseValue,
  capability,
  decisionChoices,
  intent,
  auditPresentation,
  scopeLabel,
} from '../model';
import TypedValue from '../TypedValue.vue';
import StepEditor from '../StepEditor.vue';
import { validateLoggedInRoutes } from 'dashboard/helper/routeHelpers';
import ConditionEditor from '../ConditionEditor.vue';
import PolicyEditor from '../PolicyEditor.vue';
import RequestDetail from '../RequestDetail.vue';
import SimulatorView from '../SimulatorView.vue';
import ApprovalGateBadge from '../ApprovalGateBadge.vue';
import DelegationView from '../DelegationView.vue';
import ApprovalsPage from '../ApprovalsPage.vue';

const context = {
  account_id: 17,
  member_id: 42,
  scopes: [
    {
      issuer_company_id: 101,
      business_unit_id: 202,
      company_name: 'Synthetic issuer',
      unit_name: 'Synthetic unit',
      capabilities: ['policy_manage', 'request_create', 'decide', 'view_audit'],
    },
  ],
};
const fields = {
  price_status: 'string',
  below_minimum_count: 'integer',
  context_digest: 'string',
  signature_evidence: 'string',
  total_cents: 'integer',
  currency: 'string',
  item_count: 'integer',
  order_origin: 'string',
  customer_relationship: 'string',
};
const catalog = [
  {
    key: 'crm.proposal_send',
    version: 1,
    fields,
    resource_type: 'JrcCrm::Proposal',
    policy_only: false,
  },
];
const definition = {
  ...emptyDefinition(),
  condition: { field: 'below_minimum_count', op: 'gt', value: 0 },
  selection: { mode: 'exclusive', priority: 10 },
  execution: 'sequential',
  expires_in_seconds: 3600,
  steps: [
    {
      ...emptyStep(),
      code: 'review',
      mode: 'any',
      quorum: 1,
      assignees: [{ type: 'account_user', id: 43 }],
      authority: { const: true },
      on_reject: 'rejected',
    },
  ],
};
const policy = {
  id: 301,
  code: 'synthetic',
  name: 'Synthetic policy',
  state: 'draft',
  enabled: false,
  lock_version: 0,
  issuer_company_id: 101,
  business_unit_id: 202,
  module_key: 'crm',
  event_key: 'proposal_send',
  current_version_id: null,
  current_version: null,
  draft_definition: definition,
  author_name: 'Synthetic manager',
};
const request = {
  id: 501,
  resource_type: 'JrcCrm::Proposal',
  resource_id: 601,
  requester_id: 42,
  requester_name: 'Synthetic requester',
  state: 'pending',
  lock_version: 0,
  cycle: 1,
  policy_version_id: 401,
  policy_version: 1,
  policy_name: 'Synthetic policy',
  issuer_company_id: 101,
  business_unit_id: 202,
  module_key: 'crm',
  event_key: 'proposal_send',
  expires_at: '2026-10-12T21:00:00Z',
  stages: [{ code: 'review', quorum: 1, approved_count: 0 }],
  decisions: [],
  allowed_decisions: [
    {
      step_code: 'review',
      choices: [{ delegation_id: null, actions: ['approved', 'returned'] }],
    },
  ],
};
const response = data => ({
  data,
  headers: { 'x-total-count': '1', 'x-page': '1', 'x-per-page': '25' },
});
let axios;
const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en: locale } });
const buttonStub = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const options = extra => ({
  global: {
    plugins: [i18n()],
    stubs: { Button: buttonStub, RouterLink: true },
  },
  ...extra,
});
beforeEach(() => {
  axios = {
    get: vi.fn().mockImplementation(url => {
      if (url.endsWith('/context')) return Promise.resolve(response(context));
      if (url.endsWith('/catalogs')) return Promise.resolve(response(catalog));
      if (url.endsWith('/options'))
        return Promise.resolve(
          response({
            account_users: [{ id: 43, name: 'Synthetic approver' }],
            teams: [],
            custom_roles: [],
          })
        );
      if (url.endsWith('/resources'))
        return Promise.resolve(
          response([
            {
              id: 601,
              label: 'Synthetic proposal',
              issuer_company_id: 101,
              business_unit_id: 202,
            },
          ])
        );
      return Promise.resolve(response([]));
    }),
    post: vi.fn(),
    patch: vi.fn(),
    delete: vi.fn(),
  };
  vi.stubGlobal('axios', axios);
});
afterEach(() => vi.unstubAllGlobals());

describe('E4 explicit account API and typed policy contract', () => {
  it.each([0, -1, 'bad', NaN, 1.5, 9007199254740992])(
    'rejects invalid account %s',
    id => expect(() => approvalClient(id)).toThrow()
  );
  it('pins every API operation to its explicit account, not the current page or a global store', async () => {
    const api = approvalClient(17);
    await api.get('policies', { page: 2 });
    api.post('requests', { approval_request: {} });
    api.patch('policies/301', {});
    api.revoke(7);
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/approvals/policies',
      { params: { page: 2 } }
    );
    expect(axios.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/17/approvals/delegations/7'
    );
  });
  it.each([
    ['0.01', 1],
    ['10.29', 1029],
    ['-0.15', -15],
    ['123456789.01', 12345678901],
  ])('converts %s to exact cents', (text, cents) =>
    expect(moneyCents(text)).toBe(cents)
  );
  it.each(['1.001', '1e3', 'NaN', '9007199254740992', '1,20'])(
    'rejects invalid/unsafe monetary input %s',
    text => expect(() => moneyCents(text)).toThrow()
  );
  it('requires explicit money currency without conversion', () => {
    expect(parseValue('money', '1.29', 'BRL')).toEqual({
      amount_cents: 129,
      currency: 'BRL',
    });
    expect(() => parseValue('money', '1', '')).toThrow();
  });
  it.each([
    ['integer', '1', 1],
    ['decimal', '1.010', '1.010'],
    ['boolean', 'false', false],
    ['datetime', '2026-10-12T08:00:00-03:00', '2026-10-12T08:00:00-03:00'],
  ])('preserves typed %s', (type, text, value) =>
    expect(parseValue(type, text)).toBe(value)
  );
  it.each([
    ['integer', '1.2'],
    ['decimal', '1e5'],
    ['boolean', 'yes'],
    ['datetime', '2026-10-12T08:00:00'],
  ])('rejects invalid %s', (type, text) =>
    expect(() => parseValue(type, text)).toThrow()
  );
  it('has no assumed quorum, selection, deadline or execution and preserves exact schema keys', () => {
    expect(emptyDefinition().selection).toEqual({ mode: '', priority: null });
    expect(emptyStep().quorum).toBeNull();
    expect(emptyDefinition().steps).toEqual([]);
    expect(OPERATORS.string).not.toContain('regex');
    expect(STATES).not.toContain('evaluated');
  });
  it('reuses a secure intention only for identical payload and changes key for a different content/version', () => {
    const key = intent();
    const a = key({ reason: 'A', expected_version: 0 });
    expect(key({ reason: 'A', expected_version: 0 }).idempotency_key).toBe(
      a.idempotency_key
    );
    expect(key({ reason: 'B', expected_version: 0 }).idempotency_key).not.toBe(
      a.idempotency_key
    );
    expect(key({ reason: 'B', expected_version: 1 }).idempotency_key).not.toBe(
      a.idempotency_key
    );
  });
  it('never infers decisions from admin, price status, state or internal roster', () => {
    expect(
      decisionChoices({
        state: 'approved',
        snapshot: { values: { price_status: 'evaluated' } },
        stage_plan: [{ principal_ids: [42] }],
      })
    ).toEqual([]);
    expect(decisionChoices(request).map(row => row.decision)).toEqual([
      'approved',
      'returned',
    ]);
  });
  it('matches capabilities against the exact native scope', () => {
    expect(capability(context, 'decide', 101, 202)).toBe(true);
    expect(capability(context, 'decide', 101, 999)).toBe(false);
  });
  it('renders native authorized scope names without borrowing names from another unit', () => {
    expect(
      scopeLabel(context, { issuer_company_id: 101, business_unit_id: 202 })
    ).toBe('Synthetic issuer / Synthetic unit');
    expect(
      scopeLabel(context, { issuer_company_id: 101, business_unit_id: 999 })
    ).toBe('101 / 999');
    expect(
      scopeLabel(null, { issuer_company_id: null, business_unit_id: null })
    ).toBe('');
  });
  it('projects a bounded audit presentation instead of arbitrary event payload', () => {
    expect(
      auditPresentation({
        id: 1,
        data: { reason: 'A', token: 'secret', snapshot: 'internal' },
        event_type: 'decided',
      })
    ).not.toHaveProperty('token');
  });
});

describe('E4 account switch, stale responses and error contracts', () => {
  it('ignores late rows and context from the previous tenant', async () => {
    let finish;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const vm = useApprovals();
    vm.reset(17);
    const pending = vm.loadContext();
    vm.reset(18);
    finish(response(context));
    await pending;
    expect(vm.state.context).toBeNull();
    expect(vm.state.rows).toEqual([]);
    expect(vm.state.accountId).toBe(18);
  });
  it.each([401, 404, 409, 422])(
    'preserves server status/code %s and does not retry automatically',
    async status => {
      axios.get.mockRejectedValue({
        response: { status, data: { error: 'VERSION_CONFLICT' } },
      });
      const vm = useApprovals();
      vm.reset(17);
      await vm.list('requests', {});
      expect(vm.state.error).toEqual({
        status,
        code: 'VERSION_CONFLICT',
        details: undefined,
      });
      expect(axios.get).toHaveBeenCalledTimes(1);
    }
  );
  it('reads pagination headers and scopes list filters to the explicit account', async () => {
    axios.get.mockResolvedValue({
      data: [policy],
      headers: { 'x-total-count': '35', 'x-page': '2', 'x-per-page': '25' },
    });
    const vm = useApprovals();
    vm.reset(17);
    await vm.list('policies', { page: 2, state: 'draft' });
    expect(vm.state.page).toEqual({ total: 35, page: 2, limit: 25 });
  });
  it('hides navigation when the feature is off or there are no capabilities', async () => {
    const account = ref(17);
    const user = ref(2);
    const enabled = ref(false);
    let access;
    const wrapper = mount({
      setup() {
        access = useApprovalAccess(account, user, enabled);
        return {};
      },
      template: '<div />',
    });
    expect(axios.get).not.toHaveBeenCalled();
    enabled.value = true;
    await flushPromises();
    expect(access.visible.value).toBe(true);
    axios.get.mockResolvedValue(response({ ...context, scopes: [] }));
    account.value = 18;
    await flushPromises();
    expect(access.visible.value).toBe(false);
    wrapper.unmount();
  });
  it('registers the Central inside the native account route with feature guard metadata', () => {
    expect(routes[0].path).toContain(':accountId');
    expect(routes[0].meta.featureFlag).toBe('jrc_approvals');
  });
});

describe('E4 components using bounded real DTO contracts', () => {
  it('renders only allowed decision buttons, requires a reason and emits expected version/delegation', async () => {
    const wrapper = mount(RequestDetail, options({ props: { request } }));
    expect(wrapper.findAll('button').map(b => b.text())).toEqual([
      'review: approved',
      'review: returned',
    ]);
    expect(wrapper.find('button').attributes('disabled')).toBeDefined();
    await wrapper.find('textarea').setValue('Reviewed synthetic evidence');
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('decide')[0][0]).toEqual({
      step_code: 'review',
      decision: 'approved',
      delegation_id: null,
      reason: 'Reviewed synthetic evidence',
      expected_version: 0,
    });
  });
  it('renders no votes when allowed_decisions is empty and never renders injected sensitive fields', () => {
    const wrapper = mount(
      RequestDetail,
      options({
        props: {
          request: {
            ...request,
            allowed_decisions: [],
            snapshot: 'INTERNAL_SECRET',
            stage_plan: 'ROSTER_SECRET',
            financials: 'PRIVATE_CENTS',
            evidence_digest: 'EVIDENCE_SECRET',
            token: 'TOKEN_SECRET',
          },
        },
      })
    );
    expect(wrapper.findAll('button')).toHaveLength(0);
    expect(wrapper.text()).not.toMatch(
      /INTERNAL_SECRET|ROSTER_SECRET|PRIVATE_CENTS|EVIDENCE_SECRET|TOKEN_SECRET/
    );
  });
  it('renders delegation choice from the server and no unauthorized audit action', () => {
    const wrapper = mount(
      RequestDetail,
      options({
        props: {
          request: {
            ...request,
            allowed_decisions: [
              {
                step_code: 'review',
                choices: [{ delegation_id: 99, actions: ['approved'] }],
              },
            ],
          },
        },
      })
    );
    expect(wrapper.find('button').text()).toBe('review: approved (#99)');
    expect(wrapper.text()).not.toContain('History / Audit');
  });
  it('edits a detached draft without mutating the response and keeps identity immutable', async () => {
    const original = JSON.stringify(policy);
    const wrapper = mount(
      PolicyEditor,
      options({ props: { policy, context } })
    );
    await flushPromises();
    const name = wrapper.findAll('input')[0];
    await name.setValue('New name');
    const save = wrapper
      .findAll('button')
      .find(button => button.text() === 'Save draft');
    await save.trigger('click');
    expect(wrapper.emitted('save')[0][0].name).toBe('New name');
    expect(JSON.stringify(policy)).toBe(original);
    expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('code');
  });
  it('creates a draft with an explicitly chosen scope and does not invent a description field', async () => {
    const wrapper = mount(PolicyEditor, options({ props: { context } }));
    expect(wrapper.text()).not.toContain('Description');
    expect(wrapper.findAll('select')[0].element.value).toBe('');
    await wrapper.findAll('select')[0].setValue('0');
    await flushPromises();
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/approvals/options',
      { params: { issuer_company_id: 101, business_unit_id: 202 } }
    );
  });
  it('requires human confirmation before publish and labels historic versions read only', async () => {
    const show = vi.fn();
    HTMLDialogElement.prototype.showModal = show;
    HTMLDialogElement.prototype.close = vi.fn();
    const wrapper = mount(
      PolicyEditor,
      options({ props: { policy: { ...policy, state: 'validated' }, context } })
    );
    await flushPromises();
    const publish = wrapper
      .findAll('button')
      .find(button => button.text() === 'Publish version');
    await publish.trigger('click');
    expect(show).toHaveBeenCalled();
    expect(wrapper.emitted('operation')).toBeUndefined();
  });
  it('does not offer arbitrary expressions and limits tree depth and children', () => {
    const wrapper = mount(
      ConditionEditor,
      options({
        props: { modelValue: { const: false }, fields, depth: 4, budget: 32 },
      })
    );
    expect(
      wrapper
        .find('select')
        .findAll('option')
        .map(row => row.attributes('value'))
    ).toEqual(['simple', 'const']);
    expect(wrapper.text()).not.toMatch(/SQL|regex|eval/);
  });
  it('simulator labels effects empty without rendering internal snapshot or evidence', () => {
    const wrapper = mount(
      SimulatorView,
      options({
        props: {
          context,
          catalogs: catalog,
          result: {
            predicted_state: 'pending',
            effects: [],
            versions: [
              {
                id: 1,
                priority: 10,
                selection_mode: 'exclusive',
                plan: [{ code: 'review', quorum: 1, principal_ids: [43] }],
              },
            ],
            snapshot: 'SECRET',
            evidence_digest: 'SECRET',
          },
        },
      })
    );
    expect(wrapper.text()).toContain(
      'Simulation does not execute effects in CRM.'
    );
    expect(wrapper.text()).toContain('effects=[]');
    expect(wrapper.text()).not.toContain('SECRET');
  });
  it('lists revoked delegation with retained history and no delete label', async () => {
    const wrapper = mount(
      DelegationView,
      options({
        props: {
          context,
          rows: [
            {
              id: 7,
              principal_name: 'A',
              delegate_name: 'B',
              step_code: 'review',
              actions: ['approved'],
              reason: 'Synthetic reason',
              revoked_at: '2026-10-12T00:00:00Z',
            },
          ],
        },
      })
    );
    await flushPromises();
    expect(wrapper.text()).toContain('Revoked — history preserved');
    expect(wrapper.text()).not.toContain('Delete');
  });
  it('paginates the published policy selector and uses the immutable published definition', async () => {
    const published = {
      ...policy,
      enabled: true,
      current_version_id: 401,
      published_definition: { ...definition, delegation_allowed: true },
      draft_definition: { ...definition, delegation_allowed: false },
    };
    axios.get.mockResolvedValueOnce({
      data: [published],
      headers: {
        'x-total-count': '101',
        'x-page': '1',
        'x-per-page': '100',
      },
    });
    const wrapper = mount(
      DelegationView,
      options({ props: { context, rows: [] } })
    );
    await flushPromises();
    await wrapper.findAll('select')[0].setValue(String(published.id));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Delegation is not enabled');
    axios.get.mockResolvedValueOnce({
      data: [{ ...published, id: 302 }],
      headers: {
        'x-total-count': '101',
        'x-page': '2',
        'x-per-page': '100',
      },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Next')
      .trigger('click');
    await flushPromises();
    expect(axios.get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/17/approvals/policies',
      { params: { enabled: true, per_page: 100, page: 2 } }
    );
    expect(wrapper.findAll('select')[0].element.value).toBe('');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Next')
        .attributes('disabled')
    ).toBeDefined();
  });
  it('shows delegation scope and validity state without implying permission to vote', async () => {
    const wrapper = mount(
      DelegationView,
      options({
        props: {
          context,
          rows: [
            {
              id: 8,
              issuer_company_id: 101,
              business_unit_id: 202,
              principal_name: 'A',
              delegate_name: 'B',
              step_code: 'review',
              actions: ['approved'],
              reason: 'Synthetic',
              starts_at: '2026-10-12T08:00:00Z',
              ends_at: '2026-10-12T09:00:00Z',
              window_state: 'expired',
            },
          ],
        },
      })
    );
    await flushPromises();
    expect(wrapper.text()).toContain('Synthetic issuer / Synthetic unit');
    expect(wrapper.text()).toContain('Expired — history preserved');
    expect(wrapper.emitted('decide')).toBeUndefined();
  });
  it('shows shadow as observation and only links readable requests', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/accounts/:accountId',
          name: 'fixture',
          component: { template: '<div />' },
        },
        ...routes,
      ],
    });
    await router.push('/accounts/17');
    const store = createStore({
      getters: { 'accounts/isFeatureEnabledonAccount': () => () => true },
    });
    axios.get.mockImplementation(url =>
      Promise.resolve(
        response(
          url.endsWith('/context')
            ? context
            : {
                mode: 'shadow',
                status: 'ready',
                required: true,
                requests: [
                  { id: 501, state: 'approved', readable: true },
                  { id: 999, state: 'pending', readable: false },
                ],
              }
        )
      )
    );
    const wrapper = mount(ApprovalGateBadge, {
      props: { resourceKey: 'crm.proposal_send', resourceId: 601 },
      global: {
        plugins: [i18n(), router, store],
        stubs: {
          Button: buttonStub,
          RouterLink: { props: ['to'], template: '<a>{{ to.params.id }}</a>' },
        },
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Shadow / observation');
    expect(wrapper.text()).toContain('does not block');
    expect(wrapper.text()).not.toContain('999');
    expect(wrapper.text()).not.toContain('Approved');
  });
  it('does not query or display gates when the feature is disabled', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/accounts/:accountId', component: { template: '<div />' } },
      ],
    });
    await router.push('/accounts/17');
    const store = createStore({
      getters: { 'accounts/isFeatureEnabledonAccount': () => () => false },
    });
    const wrapper = mount(ApprovalGateBadge, {
      props: { resourceKey: 'crm.proposal_send', resourceId: 601 },
      global: { plugins: [i18n(), router, store] },
    });
    await flushPromises();
    expect(axios.get).not.toHaveBeenCalled();
    expect(wrapper.text()).toBe('');
  });
  it('loads a Central list with endpoint filters and total headers', async () => {
    const router = createRouter({ history: createMemoryHistory(), routes });
    await router.push({
      name: 'jrc_approvals',
      params: { accountId: 17, screen: 'policies' },
      query: { page: 2 },
    });
    axios.get.mockImplementation(url =>
      Promise.resolve(
        response(
          { context, policies: [policy], catalogs: catalog }[
            url.split('/').at(-1)
          ] || []
        )
      )
    );
    const wrapper = mount(ApprovalsPage, {
      global: { plugins: [i18n(), router], stubs: { Button: buttonStub } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Synthetic policy');
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/approvals/policies',
      { params: { page: 2, per_page: 25 } }
    );
  });
});

describe('E4 directed gaps found during real review', () => {
  it('uses different decision intentions for different requests/accounts even with identical bodies', () => {
    const generate = intent();
    const body = {
      step_code: 'review',
      decision: 'approved',
      reason: 'A',
      expected_version: 0,
    };
    const a = generate(body, '17:request:501');
    expect(generate(body, '17:request:501').idempotency_key).toBe(
      a.idempotency_key
    );
    expect(generate(body, '17:request:502').idempotency_key).not.toBe(
      a.idempotency_key
    );
    expect(generate(body, '18:request:502').idempotency_key).not.toBe(
      a.idempotency_key
    );
  });
  it('preserves monetary input when currency is supplied after the amount, without substituting zero', async () => {
    const wrapper = mount(
      {
        components: { TypedValue },
        setup() {
          const value = ref('');
          return { value };
        },
        template: '<TypedValue v-model="value" type="money" label="Amount" />',
      },
      options()
    );
    const inputs = wrapper.findAll('input');
    await inputs[0].setValue('123.45');
    await inputs[0].trigger('change');
    expect(wrapper.vm.value).toBe('123.45');
    expect(inputs[0].element.value).toBe('123.45');
    await inputs[1].setValue('BRL');
    await inputs[1].trigger('change');
    expect(wrapper.vm.value).toEqual({ amount_cents: 12345, currency: 'BRL' });
  });
  it('preserves currency supplied before amount and associates an invalid field with its error', async () => {
    const wrapper = mount(
      {
        components: { TypedValue },
        setup() {
          const value = ref('');
          return { value };
        },
        template: '<TypedValue v-model="value" type="money" label="Amount" />',
      },
      options()
    );
    const inputs = wrapper.findAll('input');
    await inputs[1].setValue('BRL');
    await inputs[1].trigger('change');
    expect(inputs[0].element.value).toBe('');
    await inputs[0].setValue('1.001');
    await inputs[0].trigger('change');
    expect(inputs[0].attributes('aria-invalid')).toBe('true');
    expect(inputs[0].attributes('aria-describedby')).toBe(
      wrapper.find('[role="alert"]').attributes('id')
    );
    await inputs[0].setValue('1.29');
    await inputs[0].trigger('change');
    expect(wrapper.vm.value).toEqual({ amount_cents: 129, currency: 'BRL' });
  });
  it('changes quorum/assignee explicitly without changing the input definition or assuming majority', async () => {
    const step = definition.steps[0];
    const before = JSON.stringify(step);
    const wrapper = mount(
      StepEditor,
      options({
        props: {
          modelValue: step,
          fields,
          options: { account_users: [{ id: 43, name: 'Synthetic' }] },
        },
      })
    );
    await wrapper.find('input[type="number"]').setValue('2');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].quorum).toBe(2);
    expect(JSON.stringify(step)).toBe(before);
  });
  it.each([
    ['jrc_approvals_policy_manage', 'policies'],
    ['jrc_approvals_decide', 'inbox'],
    ['jrc_approvals_view_audit', 'history'],
  ])(
    'lands a granular %s role on its Central page instead of an inaccessible dashboard loop',
    (permission, screen) => {
      const user = {
        accounts: [
          {
            id: 17,
            status: 'active',
            permissions: [permission, 'custom_role'],
          },
        ],
      };
      const route = {
        name: 'home',
        params: { accountId: 17 },
        matched: [{ meta: { permissions: ['administrator', 'agent'] } }],
        meta: { permissions: ['administrator', 'agent'] },
      };
      expect(validateLoggedInRoutes(route, user)).toBe(
        `accounts/17/approvals/${screen}`
      );
    }
  );
});
