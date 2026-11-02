import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import BackofficeCustomerPicker from '../backoffice/BackofficeCustomerPicker.vue';
import BackofficeNewRequest from '../backoffice/BackofficeNewRequest.vue';

const mocks = vi.hoisted(() => ({
  companies: vi.fn(),
  company: vi.fn(),
  orderOptions: vi.fn(),
  createForAccount: vi.fn(),
  push: vi.fn(),
  route: null,
  getters: null,
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({ backofficeAPI: mocks }));
const response = (payload = [], total = payload.length) => ({
  data: { payload, meta: { total } },
});
const options = {
  global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
};

describe('Backoffice customer and order intake', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.route = reactive({ params: { accountId: '1' } });
    mocks.getters = reactive({ getCurrentUserID: 7 });
    mocks.companies.mockResolvedValue(
      response([{ id: 21, name: 'Cliente sintético fora da primeira página' }])
    );
    mocks.orderOptions.mockResolvedValue(
      response([
        {
          id: 42,
          order_number: 'PED-42',
          status: 'approved',
          contact: { name: 'Contato sintético' },
        },
      ])
    );
  });
  afterEach(() => vi.useRealTimers());

  it('searches the server after debounce and restarts pagination for a changed term', async () => {
    vi.useFakeTimers();
    mocks.companies.mockResolvedValue(
      response([{ id: 21, name: 'Cliente sintético' }], 41)
    );
    const wrapper = mount(BackofficeCustomerPicker);
    await flushPromises();
    await wrapper.findAll('button').at(-1).trigger('click');
    await flushPromises();
    expect(mocks.companies.mock.lastCall[0].page).toBe(2);
    await wrapper.find('input').setValue('Cliente além da página');
    expect(wrapper.findAll('option')).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(350);
    await flushPromises();
    expect(mocks.companies.mock.lastCall).toEqual([
      { q: 'Cliente além da página', page: 1, per_page: 20 },
      expect.objectContaining({
        accountId: '1',
        signal: expect.any(AbortSignal),
      }),
    ]);
    wrapper.unmount();
  });

  it('distinguishes an empty directory from a permission denial and a failed query', async () => {
    mocks.companies.mockResolvedValueOnce(response());
    const wrapper = mount(BackofficeCustomerPicker);
    await flushPromises();
    expect(wrapper.find('[role="status"]').text()).toContain('Nenhum cliente');
    mocks.companies.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'não tem permissão'
    );
    mocks.companies.mockRejectedValueOnce(
      new Error('Synthetic transport failure')
    );
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Falha ao consultar'
    );
    wrapper.unmount();
  });

  it('discards a late customer response after an account switch', async () => {
    let finish;
    mocks.companies.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mount(BackofficeCustomerPicker, {
      props: { modelValue: '' },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    finish(response([{ id: 99, name: 'Dado antigo sintético' }]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Dado antigo');
    expect(mocks.companies.mock.lastCall[1].accountId).toBe('2');
    expect(wrapper.emitted('update:modelValue')).toContainEqual(['']);
    wrapper.unmount();
  });

  it('keeps a customer without orders selectable and explains why creation is unavailable', async () => {
    mocks.orderOptions.mockResolvedValueOnce(response());
    const wrapper = mount(BackofficeNewRequest, options);
    await flushPromises();
    await wrapper.find('select[name="company_id"]').setValue('21');
    await flushPromises();
    expect(wrapper.find('select[name="company_id"]').element.value).toBe('21');
    expect(wrapper.text()).toContain('sem pedido elegível');
    expect(wrapper.find('button:not([type="button"])').element.disabled).toBe(
      true
    );
    wrapper.unmount();
  });

  it('clears the old order when changing customer and creates Alteração with the selected canonical company', async () => {
    mocks.companies.mockResolvedValue(
      response([
        { id: 21, name: 'Cliente A sintético' },
        { id: 22, name: 'Cliente B sintético' },
      ])
    );
    mocks.createForAccount.mockResolvedValue({ data: { id: 70 } });
    const wrapper = mount(BackofficeNewRequest, options);
    await flushPromises();
    await wrapper.find('select[name="company_id"]').setValue('21');
    await flushPromises();
    await wrapper.find('select[name="sales_order_id"]').setValue('42');
    mocks.orderOptions.mockResolvedValueOnce(
      response([
        {
          id: 43,
          order_number: 'PED-43',
          status: 'approved',
          contact: { name: 'Contato B sintético' },
        },
      ])
    );
    await wrapper.find('select[name="company_id"]').setValue('22');
    await flushPromises();
    expect(wrapper.find('select[name="sales_order_id"]').element.value).toBe(
      ''
    );
    await wrapper.find('select[name="sales_order_id"]').setValue('43');
    await wrapper
      .find('input[name="title"]')
      .setValue('TESTE SINTÉTICO — Alteração');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.createForAccount).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        company_id: '22',
        backoffice_request: expect.objectContaining({
          sales_order_id: 43,
          request_kind: 'change',
        }),
      })
    );
    expect(mocks.push).toHaveBeenCalledWith(
      expect.objectContaining({ params: { accountId: '1', requestId: 70 } })
    );
    wrapper.unmount();
  });
});
