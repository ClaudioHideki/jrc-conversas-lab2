import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { leadsAPI, pipelinesAPI, productsAPI } from 'dashboard/api/crm';
import LeadsIndex from '../LeadsIndex.vue';

const navigation = vi.hoisted(() => ({
  route: { params: { accountId: '1' }, query: {} },
  router: { push: vi.fn(), replace: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => navigation.router,
}));
vi.mock('dashboard/api/crm', () => ({
  leadsAPI: { update: vi.fn(), convert: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
  stagesAPI: { list: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/layout/useQuickActionTarget', () => ({
  useQuickActionTarget: vi.fn(),
}));

describe('Leads layout preserves its operational flows', () => {
  let wrapper;
  let fetchLeads;
  let deleteLead;

  beforeEach(async () => {
    navigation.route.query = {};
    pipelinesAPI.list.mockResolvedValue({ data: [] });
    productsAPI.list.mockResolvedValue({ data: [] });
    fetchLeads = vi.fn();
    deleteLead = vi.fn();
    const store = createStore({
      state: {
        leads: [
          { id: 1, name: 'Lead novo', status: 'new', source: 'WhatsApp' },
          { id: 2, name: 'Lead em contato', status: 'in_contact' },
          { id: 3, name: 'Lead qualificado', status: 'qualified' },
          { id: 4, name: 'Lead convertido', status: 'converted', deal_id: 81 },
          { id: 5, name: 'Lead descartado', status: 'discarded' },
        ],
      },
      getters: { 'jrcCrm/leads/allLeads': state => state.leads },
      actions: {
        'jrcCrm/leads/fetchLeads': fetchLeads,
        'jrcCrm/leads/deleteLead': deleteLead,
      },
    });
    wrapper = mount(LeadsIndex, {
      global: {
        plugins: [store],
        stubs: {
          Teleport: true,
          LeadCreateModal: true,
          LeadDetailModal: true,
          LeadConversionModal: true,
          CrmStatusBadge: true,
        },
      },
    });
    await flushPromises();
  });

  afterEach(() => {
    wrapper.unmount();
    vi.restoreAllMocks();
  });

  it('shows all records and derives the four indicators from real statuses', () => {
    expect(wrapper.findAll('tbody tr')).toHaveLength(5);
    expect(wrapper.findAll('article strong').map(card => card.text())).toEqual([
      '1',
      '1',
      '1',
      '1',
    ]);
    expect(wrapper.text()).toContain('Lead descartado');
    expect(productsAPI.list).toHaveBeenCalledWith({ active: true });
  });

  it('keeps search and status filters using the existing store action', async () => {
    await wrapper.get('input[type="search"]').setValue('cliente');
    await wrapper.get('form select').setValue('qualified');
    await wrapper.get('form').trigger('submit');
    expect(fetchLeads).toHaveBeenLastCalledWith(
      expect.anything(),
      expect.objectContaining({ search: 'cliente', status: 'qualified' })
    );
  });

  it('qualifies through the same endpoint without opening the lead detail', async () => {
    leadsAPI.update.mockResolvedValue({
      data: { id: 1, name: 'Lead novo', status: 'qualified' },
    });
    await wrapper.get('tbody tr button').trigger('click');
    await flushPromises();
    expect(leadsAPI.update).toHaveBeenCalledWith(1, {
      lead: { status: 'qualified' },
    });
    expect(navigation.router.replace).not.toHaveBeenCalled();
    expect(wrapper.get('tbody tr').text()).toContain('Converter em negócio');
  });

  it('keeps detail navigation in both list and Kanban', async () => {
    await wrapper.get('tbody tr').trigger('click');
    expect(navigation.router.replace).toHaveBeenLastCalledWith({
      query: { leadId: 1 },
    });
    const kanban = wrapper
      .findAll('button')
      .find(button => button.text() === 'Kanban');
    await kanban.trigger('click');
    expect(wrapper.find('table').exists()).toBe(false);
    const card = wrapper
      .findAll('button')
      .find(button => button.text().includes('Lead qualificado'));
    await card.trigger('click');
    expect(navigation.router.replace).toHaveBeenLastCalledWith({
      query: { leadId: 3 },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Lista')
      .trigger('click');
    expect(wrapper.findAll('tbody tr')).toHaveLength(5);
  });

  it('retains confirmed deletion with the contact-preservation notice', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    await wrapper.get('[title="Excluir lead"]').trigger('click');
    await flushPromises();
    expect(confirm).toHaveBeenCalledWith(
      expect.stringContaining('O contato continuará cadastrado')
    );
    expect(deleteLead).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ leadId: 1, params: { search: '', status: '' } })
    );
  });

  it('opens the existing creation modal and navigates to the returned lead', async () => {
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Novo lead'))
      .trigger('click');
    const modal = wrapper.getComponent({ name: 'LeadCreateModal' });
    modal.vm.$emit('created', { id: 91 });
    await flushPromises();
    expect(fetchLeads).toHaveBeenCalledTimes(2);
    expect(navigation.router.replace).toHaveBeenLastCalledWith({
      query: { leadId: 91 },
    });
    expect(wrapper.findComponent({ name: 'LeadCreateModal' }).exists()).toBe(
      false
    );
  });
});
