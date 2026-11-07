import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import DealsIndex from '../DealsIndex.vue';
import deals from 'dashboard/store/crm/modules/deals';
import activities from 'dashboard/store/crm/modules/activities';
import {
  activitiesAPI,
  dealsAPI,
  pipelinesAPI,
  productsAPI,
  stagesAPI,
} from 'dashboard/api/crm';
import AgentsAPI from 'dashboard/api/agents';
import ContactsAPI from 'dashboard/api/contacts';
import { useAlert } from 'dashboard/composables';
import { draftKey, readDraft, saveDraft } from '../../../helpers/formDrafts';

const navigation = vi.hoisted(() => ({
  route: null,
  router: { push: vi.fn(), replace: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => navigation.router,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/layout/useQuickActionTarget', () => ({
  useQuickActionTarget: vi.fn(),
}));
vi.mock('dashboard/routes/dashboard/jrcProjects/useProjects', () => ({
  useProjects: () => ({
    projectText: (_key, fallback) => fallback,
    enabled: ref(true),
  }),
}));
vi.mock('dashboard/api/crm', () => ({
  dealsAPI: {
    list: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    createProduct: vi.fn(),
    updateProduct: vi.fn(),
    deleteProduct: vi.fn(),
  },
  activitiesAPI: { list: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
  stagesAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    get: vi.fn().mockResolvedValue({
      data: { payload: [{ id: 8, name: 'Synthetic customer' }] },
    }),
  },
}));
vi.mock('dashboard/api/agents', () => ({
  default: {
    get: vi
      .fn()
      .mockResolvedValue({ data: [{ id: 7, name: 'Synthetic agent' }] }),
  },
}));
let wrapper;
let authority;
let store;
const ownerKey = draftKey(1, 7, 'crm:new_deal');
const record = id => ({
  id,
  title: `Synthetic deal ${id}`,
  pipeline_id: 1,
  stage_id: 11,
  owner_id: 7,
  status: 'open',
  value_cents: 10_000,
  products_count: 1,
  deal_products: [
    {
      id: id * 100 + 1,
      product_id: 3,
      product: { id: 3, name: 'Synthetic native product' },
      quantity: 2,
      unit_price_cents: 5000,
      discount_cents: 0,
      total_cents: 10_000,
    },
  ],
});
beforeEach(() => {
  vi.resetAllMocks();
  AgentsAPI.get.mockResolvedValue({
    data: [{ id: 7, name: 'Synthetic agent' }],
  });
  ContactsAPI.get.mockResolvedValue({
    data: { payload: [{ id: 8, name: 'Synthetic customer' }] },
  });
  activitiesAPI.list.mockResolvedValue({ data: [] });
  sessionStorage.clear();
  authority = reactive({
    user: 7,
    role: 'administrator',
    grant: 1,
    master: false,
  });
  navigation.route = reactive({ params: { accountId: '1' }, query: {} });
  dealsAPI.list.mockResolvedValue({ data: [record(1), record(2)] });
  dealsAPI.show.mockImplementation(async id => ({ data: record(Number(id)) }));
  dealsAPI.create.mockResolvedValue({ data: { id: 3 } });
  dealsAPI.update.mockResolvedValue({ data: record(1) });
  dealsAPI.createProduct.mockResolvedValue({ data: {} });
  dealsAPI.updateProduct.mockResolvedValue({ data: {} });
  dealsAPI.deleteProduct.mockResolvedValue({ status: 204 });
  pipelinesAPI.list.mockResolvedValue({
    data: [
      { id: 1, name: 'Synthetic pipeline one' },
      { id: 2, name: 'Synthetic pipeline two' },
    ],
  });
  stagesAPI.list.mockImplementation(async ({ pipeline_id: id }) => ({
    data: [{ id: Number(id) * 10 + 1, name: `Synthetic stage ${id}` }],
  }));
  productsAPI.list.mockResolvedValue({
    data: [{ id: 3, name: 'Synthetic scoped product', unit_price_cents: 5000 }],
  });
});
afterEach(() => wrapper?.unmount());
const render = async (query = {}, props = {}) => {
  navigation.route.query = query;
  store = createStore({
    getters: {
      getCurrentAccountId: () => Number(navigation.route.params.accountId),
      getCurrentUserID: () => authority.user,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        id: authority.user,
        accounts: [
          { id: 1, role: authority.role, custom_role_id: authority.grant },
        ],
      }),
      'accounts/isFeatureEnabledonAccount': () => () => authority.master,
    },
    modules: {
      jrcCrm: {
        namespaced: true,
        modules: {
          deals: { ...deals, state: structuredClone(deals.state) },
          activities: {
            ...activities,
            state: structuredClone(activities.state),
          },
        },
      },
    },
  });
  wrapper = mount(DealsIndex, {
    props,
    global: {
      plugins: [store],
      stubs: {
        Teleport: true,
        RouterLink: true,
        CompanyPicker: true,
        ContactPicker: true,
        ContactCreateModal: true,
        OperationsLinks: true,
      },
    },
  });
  await flushPromises();
};
const openCreation = async () => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Novo Negócio')
    .trigger('click');
  await flushPromises();
  const form = wrapper.get('form[role="dialog"]');
  await form
    .get('input[placeholder="Ex.: STIR/SHAKEN"]')
    .setValue('Synthetic owner draft');
  return form;
};

it('closes the previous-role creation form and retains the owner draft', async () => {
  await render();
  await openCreation();
  authority.role = 'agent';
  await flushPromises();
  expect(wrapper.find('form[role="dialog"]').exists()).toBe(false);
  expect(readDraft(ownerKey).form.title).toBe('Synthetic owner draft');
});

it('does not restore private older product options after a replacement actor initializes', async () => {
  let finish;
  productsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  productsAPI.list.mockResolvedValueOnce({
    data: [{ id: 4, name: 'Synthetic current product' }],
  });
  authority.user = 99;
  await flushPromises();
  finish({ data: [{ id: 3, name: 'Synthetic obsolete product' }] });
  await flushPromises();
  await openCreation();
  expect(wrapper.text()).toContain('Synthetic current product');
  expect(wrapper.text()).not.toContain('Synthetic obsolete product');
});

it('keeps the selected pipelines current stages when older stage responses arrive late', async () => {
  const pending = [];
  stagesAPI.list.mockImplementation(({ pipeline_id: id }) =>
    Number(id) === 1
      ? new Promise(resolve => {
          pending.push(resolve);
        })
      : Promise.resolve({
          data: [{ id: 21, name: 'Synthetic selected stage' }],
        })
  );
  await render();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Novo Negócio')
    .trigger('click');
  const form = wrapper.get('form[role="dialog"]');
  const pipeline = form
    .findAll('label')
    .find(label => label.text().startsWith('Funil'))
    .find('select');
  await pipeline.setValue('2');
  await flushPromises();
  pending.forEach(resolve =>
    resolve({ data: [{ id: 11, name: 'Synthetic obsolete stage' }] })
  );
  await flushPromises();
  const stage = wrapper
    .get('form[role="dialog"]')
    .findAll('label')
    .find(label => label.text().startsWith('Etapa'))
    .find('select');
  expect(stage.text()).toContain('Synthetic selected stage');
  expect(stage.text()).not.toContain('Synthetic obsolete stage');
});

it('does not clear an owner draft or continue an old creation receipt after grants changed', async () => {
  let finish;
  dealsAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  authority.grant = 2;
  await flushPromises();
  const requests = dealsAPI.list.mock.calls.length;
  finish({ data: { id: 3 } });
  await flushPromises();
  expect(dealsAPI.list).toHaveBeenCalledTimes(requests);
  expect(useAlert).not.toHaveBeenCalled();
  expect(readDraft(ownerKey).form.title).toBe('Synthetic owner draft');
});

it('does not report an unmounted native creation as success or clear its preserved draft', async () => {
  let finish;
  dealsAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  wrapper.unmount();
  finish({ data: { id: 3 } });
  await flushPromises();
  expect(useAlert).not.toHaveBeenCalled();
  expect(readDraft(ownerKey).form.title).toBe('Synthetic owner draft');
});

it('does not let a previous detail update reload or notify a newly selected deal', async () => {
  let finish;
  dealsAPI.update.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  await wrapper.get('aside form').trigger('submit');
  navigation.route.query.dealId = '2';
  await flushPromises();
  const requests = dealsAPI.show.mock.calls.length;
  finish({ data: record(1) });
  await flushPromises();
  expect(dealsAPI.show).toHaveBeenCalledTimes(requests);
  expect(useAlert).not.toHaveBeenCalled();
  expect(wrapper.get('aside').text()).toContain('Synthetic deal 2');
});

it('does not let an obsolete inline product removal reload a replacement detail', async () => {
  let finish;
  dealsAPI.deleteProduct.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  await wrapper.get('aside button.i-lucide-trash-2').trigger('click');
  navigation.route.query.dealId = '2';
  await flushPromises();
  const requests = dealsAPI.show.mock.calls.length;
  finish({ status: 204 });
  await flushPromises();
  expect(dealsAPI.show).toHaveBeenCalledTimes(requests);
  expect(dealsAPI.deleteProduct).toHaveBeenCalledWith(1, 101);
});

it('does not leave an unsaved inline quantity masquerading as the persisted record after native rejection', async () => {
  dealsAPI.updateProduct.mockRejectedValue({ response: { status: 403 } });
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  await wrapper.get('aside table tbody input[type="number"]').setValue(5);
  await flushPromises();
  expect(
    store.getters['jrcCrm/deals/currentDeal'].deal_products[0].quantity
  ).toBe(2);
  expect(useAlert).toHaveBeenCalled();
});

it('renders a single native company editor for the selected deal', async () => {
  authority.master = true;
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  expect(wrapper.findAllComponents({ name: 'CompanyPicker' })).toHaveLength(1);
});

it('preserves the existing global creation draft while stage metadata is slow', async () => {
  vi.useFakeTimers();
  const pending = [];
  saveDraft(ownerKey, {
    form: {
      title: 'Synthetic preserved global draft',
      pipeline_id: 2,
      stage_id: 21,
    },
    items: [],
    product: {},
  });
  stagesAPI.list.mockImplementation(
    ({ pipeline_id: id }) =>
      new Promise(resolve => {
        pending.push(() =>
          resolve({
            data: [{ id: Number(id) * 10 + 1, name: 'Synthetic loaded stage' }],
          })
        );
      })
  );
  try {
    await render({}, { creationOnly: true });
    await vi.advanceTimersByTimeAsync(350);
    expect(readDraft(ownerKey).form.title).toBe(
      'Synthetic preserved global draft'
    );
    expect(
      wrapper.get('input[placeholder="Ex.: STIR/SHAKEN"]').element.value
    ).toBe('Synthetic preserved global draft');
  } finally {
    pending.forEach(finish => finish());
    await flushPromises();
    vi.useRealTimers();
  }
});

it('preserves the native inline product creation payload and blocks a repeated pending addition', async () => {
  let finish;
  dealsAPI.createProduct.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  const product = wrapper
    .findAll('aside select')
    .find(select => select.text().includes('Synthetic scoped product'));
  await product.setValue('3');
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Adicionar')
    .trigger('click');
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Adicionar')
    .trigger('click');
  expect(dealsAPI.createProduct).toHaveBeenCalledTimes(1);
  expect(dealsAPI.createProduct).toHaveBeenCalledWith(1, {
    item: {
      product_id: 3,
      quantity: 1,
      unit_price_cents: 5000,
      discount_cents: 0,
    },
  });
  finish({ data: [] });
  await flushPromises();
  expect(dealsAPI.show).toHaveBeenCalledTimes(2);
});

it('reloads the current native product and totals after a successful inline update', async () => {
  await render({ dealId: '1' });
  await wrapper
    .findAll('aside button')
    .find(button => button.text() === 'Editar')
    .trigger('click');
  await flushPromises();
  dealsAPI.show.mockResolvedValueOnce({
    data: {
      ...record(1),
      value_cents: 15_000,
      deal_products: [
        { ...record(1).deal_products[0], quantity: 3, total_cents: 15_000 },
      ],
    },
  });
  await wrapper.get('aside table tbody input[type="number"]').setValue(3);
  await flushPromises();
  expect(dealsAPI.updateProduct).toHaveBeenCalledWith(1, 101, {
    item: { quantity: 3, unit_price_cents: 5000, discount_cents: 0 },
  });
  expect(store.getters['jrcCrm/deals/currentDeal'].value_cents).toBe(15_000);
  expect(
    store.getters['jrcCrm/deals/currentDeal'].deal_products[0].quantity
  ).toBe(3);
});

it('explains denied creation options, blocks provisional writes and retains the draft through retry', async () => {
  productsAPI.list.mockRejectedValueOnce({ response: { status: 403 } });
  await render();
  await openCreation();
  let form = wrapper.get('form[role="dialog"]');
  expect(form.find('[role="alert"]').exists()).toBe(true);
  expect(form.get('[type="submit"]').attributes('disabled')).toBeDefined();
  await form.trigger('submit');
  expect(dealsAPI.create).not.toHaveBeenCalled();
  await form.find('[role="alert"] button').trigger('click');
  await flushPromises();
  form = wrapper.get('form[role="dialog"]');
  expect(form.find('[role="alert"]').exists()).toBe(false);
  expect(form.get('input[placeholder="Ex.: STIR/SHAKEN"]').element.value).toBe(
    'Synthetic owner draft'
  );
  expect(form.get('[type="submit"]').attributes('disabled')).toBeUndefined();
});
