import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import CompaniesPage from './CompaniesPage.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  companies: vi.fn(),
  metadata: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.accountId),
    identity: computed(() => `${mocks.state.accountId}:${mocks.state.viewer}`),
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId: mocks.state.accountId, ...params },
      query,
    }),
  }),
}));
const row = {
  id: 101,
  name: 'MOCK — Alpha',
  relationship_type: 'customer',
  contact_count: 1,
  active: true,
};
let router;
const render = async (
  query = { page: '2', q: 'Alpha', segment: 'Carteira A' }
) => {
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        name: 'jrc_customer_companies',
        path: '/app/accounts/:accountId/customers/companies',
        component: CompaniesPage,
      },
    ],
  });
  await router.push({
    name: 'jrc_customer_companies',
    params: { accountId: '1' },
    query,
  });
  return mount(CompaniesPage, {
    global: {
      plugins: [router],
      stubs: { CompanyDetailsDialog: true, CompanyEditorDialog: true },
    },
  });
};
const button = (wrapper, name) =>
  wrapper.findAll('button').find(item => item.text() === name);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ accountId: '1', viewer: 'agent:1' });
  mocks.companies.mockResolvedValue({
    data: {
      payload: [structuredClone(row)],
      meta: { total: 60, per_page: 25, page: 2 },
    },
  });
  mocks.metadata.mockResolvedValue({
    data: { owners: [{ id: 7, name: 'MOCK — Responsável' }] },
  });
});

it('opens and closes the canonical company popup without losing URL filters or the server page', async () => {
  const wrapper = await render();
  await flushPromises();
  expect(mocks.companies).toHaveBeenLastCalledWith(
    expect.objectContaining({ page: 2, q: 'Alpha', segment: 'Carteira A' }),
    expect.objectContaining({ accountId: '1' })
  );
  await button(wrapper, row.name).trigger('click');
  const dialog = wrapper.findComponent({ name: 'CompanyDetailsDialog' });
  expect(dialog.props('companyId')).toBe(101);
  dialog.vm.$emit('close');
  await flushPromises();
  expect(router.currentRoute.value.query).toMatchObject({
    page: '2',
    q: 'Alpha',
    segment: 'Carteira A',
  });
  expect(mocks.companies).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});

it('restores the same filters/page on remount and keeps surrounding query parameters during search', async () => {
  const wrapper = await render({
    page: '2',
    q: 'Alpha',
    segment: 'Carteira A',
    source: 'review',
  });
  await flushPromises();
  await wrapper.find('input[placeholder]').setValue('Nova busca');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(router.currentRoute.value.query).toMatchObject({
    page: '1',
    q: 'Nova busca',
    segment: 'Carteira A',
    source: 'review',
  });
  expect(mocks.companies).toHaveBeenLastCalledWith(
    expect.objectContaining({ page: 1, q: 'Nova busca' }),
    expect.any(Object)
  );
  const query = { ...router.currentRoute.value.query };
  wrapper.unmount();
  const restored = await render(query);
  await flushPromises();
  expect(restored.find('input[placeholder]').element.value).toBe('Nova busca');
  expect(mocks.companies).toHaveBeenLastCalledWith(
    expect.objectContaining({ page: 1, segment: 'Carteira A' }),
    expect.any(Object)
  );
  restored.unmount();
});

it('opens the existing company editor in a dialog and selects its returned canonical ID', async () => {
  const wrapper = await render();
  await flushPromises();
  await button(wrapper, 'Nova empresa').trigger('click');
  const editor = wrapper.findComponent({ name: 'CompanyEditorDialog' });
  expect(editor.exists()).toBe(true);
  editor.vm.$emit('saved', { id: 202, name: 'MOCK — Persisted by API' });
  await flushPromises();
  expect(wrapper.findComponent({ name: 'CompanyEditorDialog' }).exists()).toBe(
    false
  );
  expect(
    wrapper.findComponent({ name: 'CompanyDetailsDialog' }).props('companyId')
  ).toBe(202);
  expect(router.currentRoute.value.query).toMatchObject({
    page: '2',
    q: 'Alpha',
  });
  wrapper.unmount();
});

it('discards old-account data and closes its open popup when the account changes', async () => {
  const wrapper = await render();
  await flushPromises();
  await button(wrapper, row.name).trigger('click');
  let resolveOld;
  mocks.companies.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  mocks.companies.mockResolvedValue({
    data: {
      payload: [{ ...row, id: 303, name: 'MOCK — Beta' }],
      meta: { total: 1 },
    },
  });
  mocks.state.accountId = '2';
  await router.push({
    name: 'jrc_customer_companies',
    params: { accountId: '2' },
    query: { page: '1' },
  });
  await flushPromises();
  resolveOld({ data: { payload: [row], meta: { total: 1 } } });
  await flushPromises();
  expect(wrapper.text()).not.toContain(row.name);
  expect(wrapper.text()).toContain('MOCK — Beta');
  expect(wrapper.findComponent({ name: 'CompanyDetailsDialog' }).exists()).toBe(
    false
  );
  expect(mocks.companies.mock.calls.at(-1)[1].accountId).toBe('2');
  wrapper.unmount();
});

it('clears cached rows, counts and the popup after current access is denied', async () => {
  const wrapper = await render();
  await flushPromises();
  await button(wrapper, row.name).trigger('click');
  mocks.companies.mockRejectedValue({
    response: { status: 403, data: { error: 'MOCK — Access denied' } },
  });
  mocks.state.viewer = 'revoked';
  await flushPromises();
  expect(wrapper.text()).not.toContain(row.name);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('footer').exists()).toBe(false);
  expect(wrapper.findComponent({ name: 'CompanyDetailsDialog' }).exists()).toBe(
    false
  );
  wrapper.unmount();
});
