import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import BackofficeWorklist from '../backoffice/BackofficeWorklist.vue';
import BackofficeOverview from '../backoffice/BackofficeOverview.vue';
import BackofficeRequest360 from '../backoffice/BackofficeRequest360.vue';

const mocks = vi.hoisted(() => ({
  workspace: vi.fn(),
  show: vi.fn(),
  advance: vi.fn(),
  update: vi.fn(),
  reopen: vi.fn(),
  route: null,
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentRole: 'administrator' } }),
}));
vi.mock('dashboard/api/crm/commercialCycle', () => ({ backofficeAPI: mocks }));
vi.mock('dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue', () => ({
  default: { template: '<div />' },
}));

const row = {
  id: 7,
  request_number: 'BKO-7',
  title: 'Instalação filial',
  stage: 'documentation',
  request_kind: 'fulfillment',
  status: 'blocked',
  priority: 'high',
  due_at: null,
  contact: { id: 10, name: 'Cliente autorizado' },
  owner: { id: 2, name: 'Ana' },
  queue: { id: 3, name: 'Documentação' },
  business_unit: null,
  order: { id: 4, order_number: 'PED-4', snapshot: {} },
  sla: { state: 'within', total_due_at: null },
  requested_by: { id: 2, name: 'Ana' },
  metadata: {},
  documents: [],
  history: [],
  commercial: {
    origin: 'direct_sale',
    owner: { id: 2, name: 'Ana' },
    items: [],
    deal: null,
    order_accessible: true,
  },
  workflow_stages: ['analysis', 'documentation', 'finance', 'completed'],
  stage_blockers: [],
  next_stage: 'finance',
};
const payload = (data = [row], page = 1) => ({
  data: {
    data,
    meta: { total: 21, page, pages: 2, per_page: 20 },
    summary: {
      total: 21,
      active: 21,
      overdue: 1,
      blocked: 1,
      stages: { documentation: 21 },
      queues: { 3: 21 },
      statuses: { blocked: 21 },
      kinds: [{ kind: 'fulfillment', total: 21, overdue: 1 }],
      observed: {
        first_action_seconds: null,
        completion_seconds: null,
        configured_sla: 0,
      },
    },
    dashboard: { mine: data, mine_total: 21 },
    options: { queues: [row.queue], owners: [row.owner], business_units: [] },
  },
});
const options = {
  global: {
    stubs: {
      BackofficeCustomerPicker: true,
      BackofficeAssignment: true,
      RouterLink: {
        name: 'RouterLink',
        props: ['to'],
        template: '<a><slot /></a>',
      },
    },
  },
};

describe('Backoffice workspace', () => {
  beforeEach(() => {
    mocks.route = reactive({
      params: { accountId: '1', requestId: '7' },
      query: {},
    });
    mocks.workspace.mockResolvedValue(payload());
    mocks.show.mockResolvedValue({ data: structuredClone(row) });
  });

  it('renders source labels and dates in the pt_BR locale', async () => {
    mocks.workspace.mockResolvedValue(
      payload([{ ...row, due_at: '2026-11-01T15:00:00Z' }])
    );
    const wrapper = mount(BackofficeWorklist, options);
    await flushPromises();
    wrapper.vm.$i18n.locale = 'pt_BR';
    await flushPromises();
    const content = wrapper.text();
    wrapper.vm.$i18n.locale = 'en';
    wrapper.unmount();
    expect(content).toContain('Bloqueado');
    expect(content).toContain('01/11/2026');
    expect(content).not.toContain('VALUES.blocked');
  });

  it('shows a rejected approval gate without pretending the stage advanced', async () => {
    mocks.advance.mockRejectedValueOnce({
      response: { status: 409, data: { code: 'APPROVAL_REQUIRED' } },
    });
    const wrapper = mount(BackofficeRequest360, options);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Avançar etapa')
      .trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Confira as aprovações'
    );
    expect(mocks.show).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('Documentação');
    wrapper.unmount();
  });

  it('paginates on the server and resets the page when applying filters', async () => {
    const wrapper = mount(BackofficeWorklist, options);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2, per_page: 20 })
    );
    await flushPromises();
    await wrapper.get('[name="q"]').setValue('Ana');
    await wrapper.get('[name="stage"]').setValue('documentation');
    await wrapper.get('form').trigger('submit');
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 1, q: 'Ana', stage: 'documentation' })
    );
    wrapper.unmount();
  });

  it('requests Minha Operação without sending a user identifier', async () => {
    const wrapper = mount(BackofficeWorklist, {
      ...options,
      props: { mine: true },
    });
    await flushPromises();
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ view: 'mine' })
    );
    expect(mocks.workspace.mock.lastCall[0]).not.toHaveProperty('user_id');
    expect(wrapper.find('[name="owner_id"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('reloads a published segment, paginates inside it and removes it without stale results', async () => {
    mocks.route.query.customer_segment_id = '12';
    const wrapper = mount(BackofficeWorklist, options);
    await flushPromises();
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ customer_segment_id: '12', page: 1 })
    );
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
    await flushPromises();
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ customer_segment_id: '12', page: 2 })
    );
    let resolve;
    mocks.workspace.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    mocks.route.query.customer_segment_id = '13';
    await flushPromises();
    expect(wrapper.text()).not.toContain('Cliente autorizado');
    delete mocks.route.query.customer_segment_id;
    await flushPromises();
    expect(mocks.workspace).toHaveBeenLastCalledWith(
      expect.objectContaining({ customer_segment_id: undefined, page: 1 })
    );
    resolve(payload([{ ...row, title: 'Resposta de segmento antigo' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Resposta de segmento antigo');
    expect(wrapper.text()).toContain('Cliente autorizado');
    wrapper.unmount();
  });

  it('uses aggregate totals rather than the five displayed overview rows', async () => {
    const wrapper = mount(BackofficeOverview, options);
    await flushPromises();
    expect(mocks.workspace).toHaveBeenCalledWith(
      expect.objectContaining({ per_page: 5, status: '' })
    );
    expect(wrapper.text()).toContain('21');
    wrapper.unmount();
  });

  it('preserves the selected segment in dashboard drilldowns, request links and the native return link', async () => {
    mocks.route.query.customer_segment_id = '12';
    const overview = mount(BackofficeOverview, options);
    await flushPromises();
    const destinations = overview
      .findAllComponents({ name: 'RouterLink' })
      .map(link => link.props('to'))
      .filter(to =>
        ['crm_backoffice', 'crm_backoffice_request'].includes(to.name)
      );
    expect(destinations.length).toBeGreaterThan(0);
    expect(
      destinations.every(to => to.query?.customer_segment_id === '12')
    ).toBe(true);
    overview.unmount();
    const list = mount(BackofficeWorklist, options);
    await flushPromises();
    expect(
      list.findComponent({ name: 'RouterLink' }).props('to')
    ).toMatchObject({
      name: 'crm_backoffice_request',
      query: { customer_segment_id: '12' },
    });
    list.unmount();
    const detail = mount(BackofficeRequest360, options);
    await flushPromises();
    expect(
      detail.findComponent({ name: 'RouterLink' }).props('to')
    ).toMatchObject({
      name: 'crm_backoffice',
      query: { customer_segment_id: '12' },
    });
    detail.unmount();
  });

  it('discards a response from the previous Account and clears denied data', async () => {
    let resolve;
    mocks.workspace.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(BackofficeWorklist, options);
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(wrapper.text()).toContain('Cliente autorizado');
    resolve(payload([{ ...row, title: 'Resposta antiga' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Resposta antiga');
    mocks.workspace.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Atualizar')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Cliente autorizado');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('shows blockers and prevents advancing while dependencies are pending', async () => {
    mocks.show.mockResolvedValue({
      data: { ...row, stage_blockers: ['Documento obrigatório pendente.'] },
    });
    const wrapper = mount(BackofficeRequest360, options);
    await flushPromises();
    expect(wrapper.text()).toContain('Documento obrigatório pendente.');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Avançar etapa')
        .attributes('disabled')
    ).toBeDefined();
    expect(mocks.advance).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('reloads detail and audit history after advancing through the native API', async () => {
    mocks.advance.mockResolvedValue({ data: row });
    const wrapper = mount(BackofficeRequest360, options);
    await flushPromises();
    mocks.show.mockResolvedValue({
      data: {
        ...row,
        stage: 'finance',
        history: [{ id: 1, event_type: 'backoffice_advanced' }],
      },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Avançar etapa')
      .trigger('click');
    await flushPromises();
    expect(mocks.advance).toHaveBeenCalledWith(7);
    expect(mocks.show).toHaveBeenCalledTimes(2);
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Histórico')
      .trigger('click');
    expect(wrapper.text()).toContain('backoffice_advanced');
    wrapper.unmount();
  });

  it('never retains a detail from another Account after access is denied', async () => {
    const wrapper = mount(BackofficeRequest360, options);
    await flushPromises();
    mocks.show.mockRejectedValueOnce({ response: { status: 404 } });
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(wrapper.text()).not.toContain('Cliente autorizado');
    expect(wrapper.text()).toContain('sem permissão');
    wrapper.unmount();
  });
});
