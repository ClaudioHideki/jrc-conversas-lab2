import { describe, it, expect, vi, beforeEach } from 'vitest';
import { reactive } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import ModulePage from './ModulePage.vue';
import PortfolioTable from './PortfolioTable.vue';
import CustomerPanel from './CustomerPanel.vue';
import ManagementView from '../crm/views/management/ManagementView.vue';
import TeamPanel from './TeamPanel.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    metadata: vi.fn(),
    dashboard: vi.fn(),
    portfolio: vi.fn(),
    customer: vi.fn(),
    channels: vi.fn(),
  },
  commercial: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => mocks.store,
}));
vi.mock(
  'dashboard/components-next/NewConversation/ComposeConversation.vue',
  () => ({
    default: {
      name: 'ComposeConversation',
      props: ['contactId'],
      template: '<div />',
    },
  })
);
vi.mock('dashboard/components-next/Contacts/VoiceCallButton.vue', () => ({
  default: {
    name: 'VoiceCallButton',
    props: ['contactId', 'phone', 'label'],
    template: '<div />',
  },
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
vi.mock('dashboard/api/crm', () => ({
  managementAPI: { list: mocks.commercial },
}));

const metadata = {
  can_manage: true,
  can_team: true,
  can_configure: true,
  owners: [[7, 'CS']],
  teams: [],
  units: [],
  pipelines: [],
};
const customer = {
  id: 19,
  name: 'Thiago',
  owner: { id: 7, name: 'CS' },
  signals: {
    health: { score: 80, band: 'healthy', factors: [] },
    mrr_cents: 100_000,
  },
  health_history: [],
};
const mountPortfolio = () =>
  shallowMount(ModulePage, {
    props: { screen: 'portfolio' },
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });

describe('Relationship interface integration', () => {
  beforeEach(() => {
    mocks.store = {
      getters: reactive({
        getCurrentUserID: 7,
        getCurrentRole: 'administrator',
        'accounts/isFeatureEnabledonAccount': () => true,
      }),
    };
    mocks.route = reactive({
      params: { accountId: '1' },
      query: {},
      name: 'jrc_relationship_portfolio',
    });
    mocks.api.metadata.mockResolvedValue({ data: metadata });
    mocks.api.dashboard.mockResolvedValue({ data: { customers: 1 } });
    mocks.api.portfolio.mockResolvedValue({
      data: { payload: [customer], meta: { page: 1, total: 1, per_page: 25 } },
    });
    mocks.api.customer.mockResolvedValue({ data: customer });
    mocks.api.channels.mockResolvedValue({
      data: {
        contacts: [
          {
            id: 31,
            name: 'Thiago',
            phone_number: '+5511999999999',
            email: 'thiago@example.test',
          },
        ],
        conversations: [],
        can_crm: true,
        can_service_desk: true,
      },
    });
    mocks.commercial.mockResolvedValue({
      data: [
        {
          user: { id: 7, name: 'CS', email: 'cs@example.test' },
          metrics: {
            open_deals_count: 1,
            closed_won_count: 1,
            closed_lost_count: 0,
            won_revenue_cents: 10_000,
          },
        },
      ],
    });
  });

  it('CS-01 clears protected customer rows after a forbidden response', async () => {
    const wrapper = mountPortfolio();
    await flushPromises();
    expect(wrapper.findComponent(PortfolioTable).props('rows')[0].name).toBe(
      'Thiago'
    );
    mocks.api.metadata.mockRejectedValue({
      response: { data: { errors: ['Access denied'] } },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Atualizar')
      .trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(PortfolioTable).exists()).toBe(false);
    expect(wrapper.text()).toContain('Access denied');
    wrapper.unmount();
  });

  it('CS-10 discards a late response from the previous account', async () => {
    let resolvePrevious;
    mocks.api.metadata.mockImplementation(account =>
      account === '1'
        ? new Promise(resolve => {
            resolvePrevious = resolve;
          })
        : Promise.resolve({ data: metadata })
    );
    const wrapper = mountPortfolio();
    mocks.route.params.accountId = '2';
    await flushPromises();
    resolvePrevious({
      data: { ...metadata, owners: [[8, 'Previous tenant']] },
    });
    await flushPromises();
    expect(
      mocks.api.portfolio.mock.calls.every(([account]) => account === '2')
    ).toBe(true);
    expect(wrapper.text()).not.toContain('Previous tenant');
    wrapper.unmount();
  });

  it('clears customer data and discards a late response after changing user in the same account', async () => {
    let resolveOldUser;
    mocks.api.customer.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOldUser = resolve;
        })
    );
    const wrapper = shallowMount(CustomerPanel, {
      props: { assignmentId: 19, metadata },
    });
    mocks.store.getters.getCurrentUserID = 8;
    await flushPromises();
    resolveOldUser({ data: { ...customer, name: 'Former user customer' } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Former user customer');
    expect(mocks.api.customer).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('CS-06 passes the existing customer to the real channel components', async () => {
    const wrapper = shallowMount(CustomerPanel, {
      props: { assignmentId: 19, metadata },
      global: { stubs: { RouterLink: true } },
    });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'ComposeConversation' }).props('contactId')
    ).toBe('31');
    expect(
      wrapper.findComponent({ name: 'VoiceCallButton' }).props('contactId')
    ).toBe('31');
    expect(mocks.api.channels).toHaveBeenCalledWith('1', 19);
    wrapper.unmount();
  });

  it('CS-07 switches the existing management page and retains global dates', async () => {
    const wrapper = shallowMount(ManagementView);
    await flushPromises();
    await wrapper.findAll('input[type="date"]')[0].setValue('2026-10-01');
    await wrapper.findAll('input[type="date"]')[1].setValue('2026-10-05');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Relacionamento / CS')
      .trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(TeamPanel).props('startDate')).toBe(
      '2026-10-01'
    );
    expect(wrapper.findComponent(TeamPanel).props('endDate')).toBe(
      '2026-10-05'
    );
    const calls = mocks.commercial.mock.calls.length;
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Comercial')
      .trigger('click');
    await flushPromises();
    expect(wrapper.findComponent(TeamPanel).exists()).toBe(false);
    expect(mocks.commercial.mock.calls.length).toBe(calls + 1);
    expect(mocks.commercial).toHaveBeenLastCalledWith({
      start_date: '2026-10-01',
      end_date: '2026-10-05',
    });
    wrapper.unmount();
  });
});
