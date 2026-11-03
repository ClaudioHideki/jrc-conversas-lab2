import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import Page from './CompanyPage.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  company: vi.fn(),
  overview: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.accountId),
    identity: computed(() => `${mocks.state.accountId}:${mocks.state.viewer}`),
    date: value => value || '—',
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId: mocks.state.accountId, ...params },
      query,
    }),
  }),
}));
const company = {
  id: 101,
  name: 'MOCK — Empresa canônica',
  revision: '2026-11-02T12:00:00Z',
  relationship_type: 'customer',
  active: true,
};
const summary = { contacts: 1, conversations_open: 0, capabilities: {} };
const record = () => ({
  data: {
    payload: structuredClone(company),
    addresses: [],
    branches: [],
    branches_total: 0,
  },
});
const render = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/app/accounts/:accountId/customers/companies', component: Page },
    ],
  });
  await router.push('/app/accounts/1/customers/companies');
  return mount(Page, {
    props: { subjectId: 101, embedded: true },
    global: {
      plugins: [router],
      stubs: {
        CompanyEditorDialog: true,
        BackofficeContextPanel: true,
        RelationshipMapPanel: true,
        TimelinePanel: true,
        CompanyContacts: true,
        CompanyAddresses: true,
        RecordsPanel: true,
        RelationshipPanel: true,
      },
    },
  });
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ accountId: '1', viewer: 'agent:1' });
  mocks.company.mockResolvedValue(record());
  mocks.overview.mockResolvedValue({ data: structuredClone(summary) });
});

it('uses the popup subject rather than a missing standalone route parameter and preserves the canonical edit revision', async () => {
  const wrapper = await render();
  await flushPromises();
  expect(mocks.company).toHaveBeenCalledWith(
    101,
    expect.objectContaining({ accountId: '1', signal: expect.any(AbortSignal) })
  );
  expect(mocks.overview).toHaveBeenCalledWith(
    101,
    expect.objectContaining({ accountId: '1' })
  );
  expect(wrapper.text()).toContain(company.name);
  const edit = wrapper
    .findAll('button')
    .find(item => item.text() === 'Editar empresa');
  await edit.trigger('click');
  expect(
    wrapper.findComponent({ name: 'CompanyEditorDialog' }).props('company')
  ).toMatchObject({ id: 101, revision: company.revision });
  wrapper.unmount();
});

it('mounts Backoffice context lazily only when the native capability is available', async () => {
  mocks.overview.mockResolvedValue({
    data: { ...structuredClone(summary), capabilities: { backoffice: true } },
  });
  const wrapper = await render();
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'BackofficeContextPanel' }).exists()
  ).toBe(false);
  const button = wrapper
    .findAll('button')
    .find(item => item.text() === 'Backoffice');
  await button.trigger('click');
  expect(
    wrapper.findComponent({ name: 'BackofficeContextPanel' }).props('companyId')
  ).toBe(101);
  wrapper.unmount();
});

it('keeps the map and timeline in their own tabs rather than loading both on the overview', async () => {
  const wrapper = await render();
  await flushPromises();
  expect(wrapper.findComponent({ name: 'RelationshipMapPanel' }).exists()).toBe(
    false
  );
  expect(wrapper.findComponent({ name: 'TimelinePanel' }).exists()).toBe(false);
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Mapa de relacionamento')
    .trigger('click');
  expect(
    wrapper.findComponent({ name: 'RelationshipMapPanel' }).props('companyId')
  ).toBe(101);
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Relacionamento')
    .trigger('click');
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Linha do tempo')
    .trigger('click');
  expect(
    wrapper.findComponent({ name: 'TimelinePanel' }).props('resourceId')
  ).toBe(101);
  expect(wrapper.findComponent({ name: 'RelationshipMapPanel' }).exists()).toBe(
    false
  );
  wrapper.unmount();
});

it('clears company details and edit state after a current permission denial', async () => {
  const wrapper = await render();
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(item => item.text() === 'Editar empresa')
    .trigger('click');
  mocks.company.mockRejectedValue({
    response: { status: 403, data: { error: 'MOCK — denied' } },
  });
  mocks.state.viewer = 'revoked';
  await flushPromises();
  expect(wrapper.text()).not.toContain(company.name);
  expect(wrapper.findComponent({ name: 'CompanyEditorDialog' }).exists()).toBe(
    false
  );
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});
