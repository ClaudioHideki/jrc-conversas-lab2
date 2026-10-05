import { mount, flushPromises } from '@vue/test-utils';
import SalesOrdersView from '../orders/SalesOrdersView.vue';
import SalesOrderWizard from '../orders/SalesOrderWizard.vue';
import ContractsView from '../contracts/ContractsView.vue';
import ContractWizard from '../contracts/ContractWizard.vue';
import ContractTemplates from '../contracts/ContractTemplates.vue';
import GoalsView from '../goals/GoalsView.vue';
import CommissionsView from '../commissions/CommissionsView.vue';
import BackofficeView from '../backoffice/BackofficeView.vue';
import BackofficeSlaQueues from '../backoffice/components/BackofficeSlaQueues.vue';

const mocks = vi.hoisted(() => {
  const list = () => vi.fn().mockResolvedValue({ data: [] });
  const api = () => ({
    list: list(),
    get: list(),
    create: vi.fn(),
    summary: vi.fn().mockResolvedValue({ data: {} }),
    dashboard: vi.fn().mockResolvedValue({ data: {} }),
    history: list(),
    orderOptions: list(),
    selectionOptions: vi
      .fn()
      .mockResolvedValue({ data: { eligible: [], waiting: [], linked: [] } }),
  });
  return {
    orders: api(),
    contracts: api(),
    templates: api(),
    goals: api(),
    commissions: api(),
    programs: api(),
    queues: api(),
    policies: api(),
    backoffice: api(),
    invoices: api(),
    catalog: api(),
    push: vi.fn(),
    copilot: vi.fn(),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: mocks.push, replace: vi.fn() }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getCurrentUser: { id: 1 },
      getCurrentRole: 'administrator',
    },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/jrcCopilot/useJrcCopilot', () => ({
  useJrcCopilot: () => ({ openWithPrompt: mocks.copilot }),
}));
vi.mock('dashboard/api/agents', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/teams', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/contacts', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/products', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/deals', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/proposals', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/organizationStructure', () => ({
  default: {
    load: vi.fn().mockResolvedValue({
      data: { business_units: [], operating_companies: [] },
    }),
  },
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  salesOrdersAPI: mocks.orders,
  contractsAPI: mocks.contracts,
  contractTemplatesAPI: mocks.templates,
  goalsAPI: mocks.goals,
  commissionsAPI: mocks.commissions,
  commissionProgramsAPI: mocks.programs,
  backofficeAPI: mocks.backoffice,
  invoicesAPI: mocks.invoices,
  paymentsAPI: {},
  operationsQueuesAPI: mocks.queues,
  operationsSlaPoliciesAPI: mocks.policies,
}));

describe('Commercial screens on an Account without commercial records', () => {
  it('sends explicit queue and SLA settings without inventing deadline minutes', async () => {
    const wrapper = mount(BackofficeSlaQueues, {
      props: { summary: { within_sla: 2 }, requests: [] },
    });
    await flushPromises();
    Object.assign(wrapper.vm.queueForm, {
      name: 'Operations',
      code: 'ops',
      assignment_strategy: 'round_robin',
      product_id: 7,
    });
    await wrapper.vm.saveQueue();
    expect(mocks.queues.create).toHaveBeenCalledWith({
      operations_queue: expect.objectContaining({
        code: 'OPS',
        assignment_strategy: 'round_robin',
        settings: { product_ids: [7] },
      }),
    });
    wrapper.vm.policyForm.name = 'Monitor only';
    await wrapper.vm.savePolicy();
    expect(mocks.policies.create).toHaveBeenCalledWith({
      operations_sla_policy: expect.objectContaining({
        first_action_minutes: null,
        stage_minutes: null,
        total_minutes: null,
        alert_thresholds: [50, 75, 90, 100],
      }),
    });
    wrapper.unmount();
  });
  beforeEach(() => {
    vi.clearAllMocks();
    Object.values(mocks).forEach(api => {
      if (typeof api !== 'object') return;
      Object.entries(api).forEach(([method, fn]) => {
        fn.mockResolvedValue({
          data: ['summary', 'dashboard'].includes(method) ? {} : [],
        });
      });
    });
  });

  it('adds all remaining sellers/products without duplicates or losing a partial allocation', async () => {
    const agents = Array.from({ length: 12 }, (_, index) => ({
      id: index + 1,
      name: `Seller ${index + 1}`,
    }));
    const products = Array.from({ length: 12 }, (_, index) => ({
      id: index + 101,
      name: `Product ${index + 1}`,
    }));
    mocks.catalog.get.mockResolvedValue({ data: { payload: agents } });
    mocks.catalog.list.mockResolvedValue({ data: { payload: products } });
    const wrapper = mount(GoalsView);
    await flushPromises();
    wrapper.vm.sellerToAdd = 1;
    wrapper.vm.addSellerAllocation();
    wrapper.vm.form.allocations[0].target = '12.34';
    wrapper.vm.seedAllocations();
    wrapper.vm.seedAllocations();
    expect(wrapper.vm.form.allocations).toHaveLength(12);
    expect(wrapper.vm.form.allocations[0].target).toBe('12.34');
    wrapper.vm.removeSellerAllocation(0);
    wrapper.vm.distributeEqually();
    expect(wrapper.vm.form.allocations).toHaveLength(11);
    expect(
      wrapper.vm.form.allocations.reduce(
        (sum, row) => sum + Math.round(Number(row.target) * 100),
        0
      )
    ).toBe(50000000);
    wrapper.vm.productToAdd = 101;
    wrapper.vm.addProductTarget();
    wrapper.vm.seedProducts();
    wrapper.vm.seedProducts();
    expect(wrapper.vm.form.product_targets).toHaveLength(12);
    wrapper.vm.removeProductTarget(0);
    wrapper.vm.distributeProducts();
    expect(wrapper.vm.form.product_targets).toHaveLength(11);
    expect(
      wrapper.vm.form.product_targets.reduce(
        (sum, row) => sum + Math.round(Number(row.target) * 100),
        0
      )
    ).toBe(50000000);
    wrapper.unmount();
  });

  it('sends real recommendation records to NICO and opens the seller portfolio/activity', async () => {
    const wrapper = mount(GoalsView);
    await flushPromises();
    const action = {
      key: 'sellers_below_pace',
      reason: 'Below expected pace',
      records: [
        {
          type: 'seller',
          id: 7,
          owner_id: 7,
          label: 'Seller 7',
          forecast_cents: 10000,
        },
      ],
    };
    wrapper.vm.analyzeWithNico(action);
    expect(mocks.copilot).toHaveBeenCalledWith(
      expect.stringContaining('"owner_id":7')
    );
    expect(mocks.copilot).toHaveBeenCalledWith(
      expect.stringContaining('Seller 7')
    );
    wrapper.vm.openActionRecords(action);
    expect(mocks.push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'crm_deals',
        query: { ownerId: 7, status: 'open' },
      })
    );
    wrapper.vm.createActionActivity({ deal_ids: [42] });
    expect(mocks.push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'crm_activities',
        query: { new: '1', dealId: 42 },
      })
    );
    wrapper.unmount();
  });

  it('sends the selected Account team when publishing a goal', async () => {
    mocks.goals.dashboard.mockResolvedValue({
      data: {
        scope_options: {
          teams: [{ id: 42, name: 'Comercial JRC' }],
          business_units: [],
        },
      },
    });
    const wrapper = mount(GoalsView);
    await flushPromises();
    const click = async text => {
      await wrapper
        .findAll('button')
        .find(button => button.text().includes(text))
        .trigger('click');
    };
    await click('Nova meta');
    await click('Equipe');
    await wrapper.get('[name="goal_team_id"]').setValue('42');
    await click('Avançar');
    await click('Avançar');
    await click('Avançar');
    await click('Avançar');
    await click('Publicar meta');
    await flushPromises();
    expect(mocks.goals.create).toHaveBeenCalledWith({
      goal: expect.objectContaining({
        scope_kind: 'team',
        team_id: 42,
        status: 'active',
        allocations: [],
        product_targets: [],
      }),
    });
    wrapper.unmount();
  });
  it.each([
    ['Pedidos', SalesOrdersView, () => mocks.orders.list],
    ['Novo pedido', SalesOrderWizard, () => mocks.catalog.list],
    ['Contratos', ContractsView, () => mocks.contracts.list],
    ['Novo contrato', ContractWizard, () => mocks.contracts.orderOptions],
    ['Modelos', ContractTemplates, () => mocks.templates.list],
    ['Metas', GoalsView, () => mocks.goals.dashboard],
    ['Comissões', CommissionsView, () => mocks.commissions.list],
    ['Backoffice', BackofficeView, () => mocks.backoffice.list],
  ])(
    '%s initializes and reads its API without creating data',
    async (_, component, read) => {
      const errors = [];
      const wrapper = mount(component, {
        global: {
          stubs: { Teleport: true, RouterLink: true },
          config: { errorHandler: error => errors.push(error) },
        },
      });
      await flushPromises();
      expect(errors).toEqual([]);
      expect(read()).toHaveBeenCalled();
      expect(wrapper.text().length).toBeGreaterThan(20);
      expect(mocks.push).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );
});
