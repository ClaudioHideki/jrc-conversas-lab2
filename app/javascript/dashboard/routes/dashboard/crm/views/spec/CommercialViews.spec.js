import { mount, flushPromises } from '@vue/test-utils';
import SalesOrdersView from '../orders/SalesOrdersView.vue';
import SalesOrderWizard from '../orders/SalesOrderWizard.vue';
import ContractsView from '../contracts/ContractsView.vue';
import ContractWizard from '../contracts/ContractWizard.vue';
import ContractTemplates from '../contracts/ContractTemplates.vue';
import GoalsView from '../goals/GoalsView.vue';
import CommissionsView from '../commissions/CommissionsView.vue';
import BackofficeView from '../backoffice/BackofficeView.vue';

const mocks = vi.hoisted(() => {
  const list = () => vi.fn().mockResolvedValue({ data: [] });
  const api = () => ({
    list: list(),
    get: list(),
    create: vi.fn(),
    summary: vi.fn().mockResolvedValue({ data: {} }),
    dashboard: vi.fn().mockResolvedValue({ data: {} }),
    history: list(),
  });
  return {
    orders: api(), contracts: api(), templates: api(), goals: api(),
    commissions: api(), programs: api(), backoffice: api(), invoices: api(),
    catalog: api(), push: vi.fn(),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
  useRouter: () => ({ push: mocks.push, replace: vi.fn() }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: {
    getCurrentUser: { id: 1 }, getCurrentRole: 'administrator',
  } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/agents', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/teams', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/contacts', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/products', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/deals', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/proposals', () => ({ default: mocks.catalog }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  salesOrdersAPI: mocks.orders, contractsAPI: mocks.contracts,
  contractTemplatesAPI: mocks.templates, goalsAPI: mocks.goals,
  commissionsAPI: mocks.commissions, commissionProgramsAPI: mocks.programs,
  backofficeAPI: mocks.backoffice, invoicesAPI: mocks.invoices, paymentsAPI: {},
}));

describe('Commercial screens on an Account without commercial records', () => {
  beforeEach(() => {
    Object.values(mocks).forEach(api => {
      if (typeof api !== 'object') return;
      Object.entries(api).forEach(([method, fn]) => {
        fn.mockResolvedValue({ data: ['summary', 'dashboard'].includes(method) ? {} : [] });
      });
    });
  });

  it('sends the selected Account team when publishing a goal', async () => {
    mocks.goals.dashboard.mockResolvedValue({ data: { scope_options: {
      teams: [{ id: 42, name: 'Comercial JRC' }], business_units: [],
    } } });
    const wrapper = mount(GoalsView);
    await flushPromises();
    const click = async text => {
      await wrapper.findAll('button').find(button => button.text().includes(text)).trigger('click');
    };
    await click('Nova meta');
    await click('Equipe');
    await wrapper.get('[name="goal_team_id"]').setValue('42');
    for (let step = 1; step < 5; step += 1) {
      await click('Avançar');
    }
    await click('Publicar meta');
    await flushPromises();
    expect(mocks.goals.create).toHaveBeenCalledWith({ goal: expect.objectContaining({
      scope_kind: 'team', team_id: 42, status: 'active',
      allocations: [], product_targets: [],
    }) });
    wrapper.unmount();
  });
  it.each([
    ['Pedidos', SalesOrdersView, () => mocks.orders.list],
    ['Novo pedido', SalesOrderWizard, () => mocks.catalog.list],
    ['Contratos', ContractsView, () => mocks.contracts.list],
    ['Novo contrato', ContractWizard, () => mocks.orders.list],
    ['Modelos', ContractTemplates, () => mocks.templates.list],
    ['Metas', GoalsView, () => mocks.goals.dashboard],
    ['Comissões', CommissionsView, () => mocks.commissions.list],
    ['Backoffice', BackofficeView, () => mocks.backoffice.list],
  ])('%s initializes and reads its API without creating data', async (_, component, read) => {
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
  });
});
