import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import {
  collection,
  contextPayload,
  deferred,
  ticket,
} from '../../__tests__/fixtures';

const mocks = vi.hoisted(() => ({
  route: null,
  user: null,
  context: vi.fn(),
  list: vi.fn(),
  dashboard: vi.fn(),
  report: vi.fn(),
  push: vi.fn(),
  replace: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push, replace: mocks.replace }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      get getCurrentUserID() {
        return mocks.user.id;
      },
      'accounts/isFeatureEnabledonAccount': () => true,
    },
  }),
}));
vi.mock('dashboard/api/serviceDesk', () => ({
  default: {
    context: (...args) => mocks.context(...args),
    list: (...args) => mocks.list(...args),
  },
}));
vi.mock('dashboard/api/serviceDeskOperations', () => ({
  default: { dashboard: (...args) => mocks.dashboard(...args) },
}));
vi.mock('dashboard/api/serviceDeskOperationsV2', () => ({
  default: { report: (...args) => mocks.report(...args) },
}));
import { provideServiceDesk } from '../../composables/useServiceDesk';
import OverviewView from '../../views/OverviewView.vue';
import LiveKpis from '../LiveKpis.vue';
import KpiCard from '../KpiCard.vue';
import State from '../ServiceDeskState.vue';

let wrapper;
let session;
const keys = messages.JRC_SERVICE_DESK;
const authorizedContext = (account = '1') => {
  const value = contextPayload({
    account_id: account,
    user_id: mocks.user.id,
    effective_permissions: [
      'jrc_service_desk_tickets_view_all',
      'jrc_service_desk_sla_view',
    ],
  });
  value.capabilities.reports = { index: true };
  value.units.forEach(unit => {
    unit.account_id = account;
    unit.operator_company.account_id = account;
  });
  return value;
};
const recentPayload = (account = '1', query = {}, title = null) =>
  collection(
    [
      ticket({
        account_id: account,
        title: title || `Recent Account ${account} ${query.q || ''}`,
      }),
    ],
    {
      account_id: account,
      meta: { page: query.page || 1, per_page: query.per_page || 5, total: 1 },
    }
  );
const dashboardPayload = (account = '1', query = {}, open = 20) => ({
  contract_version: 1,
  account_id: account,
  dashboard: {
    total: open + 7,
    active: open,
    phases: { open, waiting: 0, resolved: 7, closed: 0, cancelled: 0 },
    generated_at: '2026-10-26T12:00:00Z',
    filters: Object.fromEntries(
      Object.entries(query).filter(
        ([key]) => !['page', 'per_page', 'sort'].includes(key)
      )
    ),
    by_status: [
      { id: '1', name: 'Open fixture', phase: 'open', count: open },
      { id: '2', name: 'Resolved fixture', phase: 'resolved', count: 7 },
    ],
    supervision: {
      timezone: 'UTC',
      sla: null,
      by_agent: [],
      capacity: [],
      evolution: [],
      top_categories: [],
      tasks: null,
      approvals: null,
    },
  },
});
const render = (component = OverviewView, props = {}) => {
  const Root = defineComponent({
    setup() {
      session = provideServiceDesk();
      return () => h(component, props);
    },
  });
  wrapper = mount(Root, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Icon: true,
        Spinner: true,
        Button: {
          props: ['label', 'disabled'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
        TicketFilters: { template: '<div />' },
        Panel: {
          props: ['title'],
          template:
            '<section><h3>{{ title }}</h3><slot name="actions" /><slot /></section>',
        },
        OverviewOperations: {
          props: ['data', 'section'],
          template: '<div data-testid="supervision">{{ section }}</div>',
        },
        OverviewSignals: { template: '<div />' },
        TicketTable: {
          props: ['items'],
          template:
            '<div data-testid="recent-tickets"><span v-for="row in items" :key="row.id">{{ row.title }}</span></div>',
        },
      },
    },
  });
  return wrapper;
};
const openCard = () =>
  wrapper
    .findAllComponents(KpiCard)
    .find(card => card.props('label') === keys.OPS.KPI.open);
beforeEach(() => {
  wrapper = null;
  mocks.user = reactive({ id: '7' });
  mocks.route = reactive({
    name: 'jrc_service_desk_overview',
    params: { accountId: '1' },
    query: {},
  });
  mocks.context.mockImplementation(async account => authorizedContext(account));
  mocks.list.mockImplementation(async (account, _resource, query) =>
    recentPayload(account, query)
  );
  mocks.dashboard.mockImplementation(async (account, query) =>
    dashboardPayload(account, query)
  );
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.clearAllMocks();
});

describe('Overview request sharing and independent loading', () => {
  it('uses one dashboard for KPIs and supervision and keeps recent tickets in a separate bounded request', async () => {
    render();
    await flushPromises();
    expect(wrapper.findComponent(LiveKpis).exists()).toBe(true);
    expect(mocks.dashboard).toHaveBeenCalledExactlyOnceWith(
      '1',
      { page: 1, per_page: 20 },
      expect.any(AbortSignal)
    );
    expect(mocks.list).toHaveBeenCalledExactlyOnceWith(
      '1',
      'tickets',
      { page: 1, per_page: 5, sort: 'updated_at_desc' },
      expect.any(AbortSignal)
    );
    expect(mocks.report).not.toHaveBeenCalled();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    expect(wrapper.findAll('[data-testid="supervision"]')).toHaveLength(2);
  });

  it('shows recent tickets while the shared dashboard is still loading without a second KPI request', async () => {
    const response = deferred();
    mocks.dashboard.mockReturnValueOnce(response.promise);
    render();
    await flushPromises();
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    expect(openCard().find('strong').text()).toBe(keys.COMMON.no_value);
    expect(
      wrapper.findComponent(LiveKpis).props('dashboardSource').status
    ).toBe('loading');
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
    expect(mocks.report).not.toHaveBeenCalled();
    response.resolve(dashboardPayload());
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
  });

  it('shows dashboard KPIs while the recent-ticket request is still loading', async () => {
    const response = deferred();
    mocks.list.mockReturnValueOnce(response.promise);
    render();
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.find('[data-testid="recent-tickets"]').exists()).toBe(false);
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
    response.resolve(recentPayload());
    await flushPromises();
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
  });

  it('retries a failed shared dashboard through the parent without reloading recent tickets or reports', async () => {
    mocks.dashboard.mockRejectedValueOnce({ response: { status: 500 } });
    render();
    await flushPromises();
    const kpis = wrapper.findComponent(LiveKpis);
    expect(kpis.props('dashboardSource').status).toBe('error');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    mocks.dashboard.mockResolvedValueOnce(dashboardPayload('1', {}, 31));
    await kpis.findComponent(State).get('button').trigger('click');
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('31');
    expect(mocks.dashboard).toHaveBeenCalledTimes(2);
    expect(mocks.list).toHaveBeenCalledTimes(1);
    expect(mocks.report).not.toHaveBeenCalled();
    expect(session.state.status).toBe('ready');
  });

  it('isolates an invalid optional supervision projection from independently valid KPIs and tickets', async () => {
    const payload = dashboardPayload();
    payload.dashboard.supervision.timezone = 'invalid';
    mocks.dashboard.mockResolvedValueOnce(payload);
    render();
    await flushPromises();
    expect(session.state.status).toBe('ready');
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    expect(wrapper.findAll('[data-testid="supervision"]')).toHaveLength(0);
    const failure = wrapper
      .findAllComponents(State)
      .find(state => state.props('status') === 'invalid_contract');
    expect(failure).toBeDefined();
    await failure.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-testid="supervision"]')).toHaveLength(2);
    expect(mocks.dashboard).toHaveBeenCalledTimes(2);
    expect(mocks.list).toHaveBeenCalledTimes(1);
    expect(mocks.report).not.toHaveBeenCalled();
  });

  it('keeps dashboard-only users functional without fetching or displaying a supervision report', async () => {
    const context = authorizedContext();
    context.capabilities.reports = { index: false };
    context.effective_permissions = [];
    mocks.context.mockResolvedValue(context);
    render();
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    expect(wrapper.findAll('[data-testid="supervision"]')).toHaveLength(0);
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
    expect(mocks.report).not.toHaveBeenCalled();
  });

  it('refreshes each request once and preserves independent recent pagination and sort when filters change', async () => {
    render();
    await flushPromises();
    session.operations.state.revision += 1;
    await flushPromises();
    expect(mocks.dashboard).toHaveBeenCalledTimes(2);
    expect(mocks.list).toHaveBeenCalledTimes(2);
    mocks.route.query = {
      q: 'new',
      page: '9',
      per_page: '50',
      sort: 'created_at_asc',
    };
    await flushPromises();
    expect(mocks.dashboard).toHaveBeenCalledTimes(3);
    expect(mocks.dashboard).toHaveBeenLastCalledWith(
      '1',
      { q: 'new', page: 9, per_page: 50, sort: 'created_at_asc' },
      expect.any(AbortSignal)
    );
    expect(mocks.list).toHaveBeenLastCalledWith(
      '1',
      'tickets',
      { q: 'new', page: 1, per_page: 5, sort: 'updated_at_desc' },
      expect.any(AbortSignal)
    );
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'new'
    );
    expect(mocks.report).not.toHaveBeenCalled();
  });

  it('does not restore late dashboard counts or tickets from an older query', async () => {
    const oldDashboard = deferred();
    const oldTickets = deferred();
    mocks.dashboard.mockReturnValueOnce(oldDashboard.promise);
    mocks.list.mockReturnValueOnce(oldTickets.promise);
    render();
    await flushPromises();
    mocks.route.query = { q: 'new' };
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'new'
    );
    expect(mocks.dashboard.mock.calls[0][2].aborted).toBe(true);
    expect(mocks.list.mock.calls[0][3].aborted).toBe(true);
    oldDashboard.resolve(dashboardPayload('1', {}, 99));
    oldTickets.resolve(recentPayload('1', {}, 'OLD QUERY TICKET'));
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.text()).not.toContain('OLD QUERY TICKET');
    expect(mocks.dashboard).toHaveBeenCalledTimes(2);
    expect(mocks.list).toHaveBeenCalledTimes(2);
  });

  it('clears old Account records and ignores their delayed responses after the context changes', async () => {
    render();
    await flushPromises();
    const oldDashboard = deferred();
    const oldTickets = deferred();
    mocks.dashboard.mockReturnValueOnce(oldDashboard.promise);
    mocks.list.mockReturnValueOnce(oldTickets.promise);
    session.operations.state.revision += 1;
    await flushPromises();
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(session.state.context.account_id).toBe('2');
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 2'
    );
    expect(wrapper.text()).not.toContain('Recent Account 1');
    oldDashboard.resolve(dashboardPayload('1', {}, 99));
    oldTickets.resolve(recentPayload('1', {}, 'OLD ACCOUNT TICKET'));
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(wrapper.text()).not.toContain('OLD ACCOUNT TICKET');
    expect(mocks.dashboard).toHaveBeenCalledTimes(3);
    expect(mocks.list).toHaveBeenCalledTimes(3);
    expect(mocks.report).not.toHaveBeenCalled();
  });

  it('removes previously displayed recent tickets when the shared dashboard denies authorization', async () => {
    const response = deferred();
    mocks.dashboard.mockReturnValueOnce(response.promise);
    render();
    await flushPromises();
    expect(wrapper.get('[data-testid="recent-tickets"]').text()).toContain(
      'Recent Account 1'
    );
    response.reject({ response: { status: 403 } });
    await flushPromises();
    expect(session.state.status).toBe('denied');
    expect(session.state.context).toBeNull();
    expect(wrapper.text()).not.toContain('Recent Account 1');
    expect(wrapper.findComponent(KpiCard).exists()).toBe(false);
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
    expect(mocks.report).not.toHaveBeenCalled();
  });

  it('retains standalone LiveKpis transport, refresh and retry behavior outside Overview', async () => {
    const props = reactive({ query: {} });
    render(LiveKpis, props);
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(mocks.dashboard).toHaveBeenCalledTimes(1);
    expect(mocks.list).not.toHaveBeenCalled();
    mocks.dashboard.mockRejectedValueOnce({ response: { status: 500 } });
    props.query = { q: 'standalone' };
    await flushPromises();
    expect(wrapper.findComponent(LiveKpis).props('dashboardSource')).toBeNull();
    expect(openCard().find('strong').text()).toBe(keys.COMMON.no_value);
    await wrapper.findComponent(State).get('button').trigger('click');
    await flushPromises();
    expect(openCard().find('strong').text()).toBe('20');
    expect(mocks.dashboard).toHaveBeenCalledTimes(3);
    expect(mocks.dashboard).toHaveBeenLastCalledWith(
      '1',
      { q: 'standalone', page: 1, per_page: 20 },
      expect.any(AbortSignal)
    );
    expect(mocks.report).not.toHaveBeenCalled();
  });
});
