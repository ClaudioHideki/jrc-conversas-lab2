import { describe, it, expect, vi, beforeEach } from 'vitest';
import { reactive } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import ModulePage from './ModulePage.vue';
import PortfolioTable from './PortfolioTable.vue';
import CustomerPanel from './CustomerPanel.vue';
import TransferLockDialog from './TransferLockDialog.vue';
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
    saveTransferLock: vi.fn(),
    saveAssignment: vi.fn(),
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
  it('keeps portfolio reassignment controls unavailable for a team viewer without native manage permission', async () => {
    mocks.api.customer.mockResolvedValue({ data: customer });
    const wrapper = shallowMount(CustomerPanel, {
      props: { assignmentId: 19, metadata: { ...metadata, can_manage: false } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="portfolio-owner"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="assign-portfolio-owner"]').exists()
    ).toBe(false);
    expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
    wrapper.unmount();
  });

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
    mocks.api.saveTransferLock.mockResolvedValue({ data: {} });
    mocks.api.saveAssignment.mockResolvedValue({ data: {} });
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
    const attempt = {
      state: 'deferred',
      reason: 'account_daily_budget',
      required_actions: 2,
    };
    mocks.api.customer.mockResolvedValueOnce({
      data: { ...customer, automatic_playbook_attempt: attempt },
    });
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
    expect(
      wrapper
        .findComponent({ name: 'AutomaticPlaybookNotice' })
        .props('attempt')
    ).toEqual(attempt);
    expect(
      wrapper.findComponent({ name: 'HealthCoverageNote' }).props('health')
    ).toEqual(customer.signals.health);
    wrapper.unmount();
  });

  it('reloads current portfolio facts before editing the restriction and reflects the persisted response', async () => {
    const current = {
      ...customer,
      assignment_version: '2026-11-06T12:00:00.123456Z',
      transfer_locked: false,
      settings: {},
    };
    const saved = {
      ...current,
      assignment_version: '2026-11-06T12:01:00.123456Z',
      transfer_locked: true,
      settings: {
        transfer_lock: { locked: true, reason: 'Synthetic continuity review' },
      },
    };
    mocks.api.customer.mockResolvedValue({ data: current });
    const wrapper = shallowMount(CustomerPanel, {
      props: { assignmentId: 19, metadata },
    });
    await flushPromises();
    await wrapper.get('[data-testid="open-transfer-lock"]').trigger('click');
    await flushPromises();
    expect(mocks.api.customer).toHaveBeenCalledTimes(2);
    const dialog = wrapper.getComponent(TransferLockDialog);
    expect(dialog.props('record').assignment_version).toBe(
      current.assignment_version
    );
    mocks.api.saveTransferLock.mockImplementationOnce(async () => {
      mocks.api.customer.mockResolvedValue({ data: saved });
      return { data: { id: 19, transfer_locked: true } };
    });
    const fields = {
      locked: true,
      reason: 'Synthetic continuity review',
      expected_version: current.assignment_version,
    };
    dialog.vm.$emit('save', fields);
    await flushPromises();
    expect(mocks.api.saveTransferLock).toHaveBeenCalledWith('1', 19, fields);
    expect(wrapper.findComponent(TransferLockDialog).exists()).toBe(false);
    expect(
      wrapper.get('[data-testid="portfolio-transfer-locked"]').text()
    ).toContain(fields.reason);
    expect(
      wrapper.get('[data-testid="portfolio-owner"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .get('[data-testid="assign-portfolio-owner"]')
        .attributes('disabled')
    ).toBeDefined();
    const form = wrapper
      .findAll('form')
      .find(node => node.find('[data-testid="portfolio-owner"]').exists());
    await form.trigger('submit');
    expect(mocks.api.saveAssignment).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('keeps a restricted portfolio visible but does not offer policy mutation without configuration authority', async () => {
    mocks.api.customer.mockResolvedValue({
      data: {
        ...customer,
        transfer_locked: true,
        settings: {
          transfer_lock: { locked: true, reason: 'Synthetic configured hold' },
        },
      },
    });
    const wrapper = shallowMount(CustomerPanel, {
      props: {
        assignmentId: 19,
        metadata: { ...metadata, can_configure: false },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="open-transfer-lock"]').exists()).toBe(
      false
    );
    expect(
      wrapper.get('[data-testid="portfolio-transfer-locked"]').text()
    ).toContain('Synthetic configured hold');
    expect(
      wrapper.get('[data-testid="portfolio-owner"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('does not open an old policy response after the authenticated user changes', async () => {
    const wrapper = shallowMount(CustomerPanel, {
      props: { assignmentId: 19, metadata },
    });
    await flushPromises();
    let finish;
    mocks.api.customer.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('[data-testid="open-transfer-lock"]').trigger('click');
    mocks.store.getters.getCurrentUserID = 8;
    await flushPromises();
    finish({
      data: {
        ...customer,
        name: 'Previous actor private policy',
        transfer_locked: true,
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Previous actor private policy');
    expect(wrapper.findComponent(TransferLockDialog).exists()).toBe(false);
    expect(mocks.api.saveTransferLock).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('binds ordinary owner edits to the viewed revision and preserves the draft after a native conflict', async () => {
    const current = {
      ...customer,
      assignment_version: '2026-11-06T12:00:00.123456Z',
      transfer_locked: false,
    };
    mocks.api.customer.mockResolvedValue({ data: current });
    mocks.api.saveAssignment.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { errors: ['Record changed. Refresh before retrying.'] },
      },
    });
    const wrapper = shallowMount(CustomerPanel, {
      props: {
        assignmentId: 19,
        metadata: {
          ...metadata,
          owners: [
            [7, 'CS'],
            [8, 'Other analyst'],
          ],
        },
      },
    });
    await flushPromises();
    await wrapper.get('[data-testid="portfolio-owner"]').setValue('8');
    const form = wrapper
      .findAll('form')
      .find(node => node.find('[data-testid="portfolio-owner"]').exists());
    await form.trigger('submit');
    await flushPromises();
    expect(mocks.api.saveAssignment).toHaveBeenCalledWith(
      '1',
      { owner_id: 8, expected_version: current.assignment_version },
      19
    );
    expect(wrapper.get('[data-testid="portfolio-owner"]').element.value).toBe(
      '8'
    );
    expect(wrapper.get('[role="alert"]').text()).toContain('Record changed');
    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(mocks.api.customer).toHaveBeenCalledTimes(1);
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
