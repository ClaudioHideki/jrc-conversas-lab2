import { shallowMount, mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { dealsAPI, pipelinesAPI, stagesAPI, productsAPI, proposalsAPI } from 'dashboard/api/crm';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import ContactsAPI from 'dashboard/api/contacts';
import AgentsAPI from 'dashboard/api/agents';
import DealsIndex from '../../views/deals/DealsIndex.vue';
import ProposalsIndex from '../../views/proposals/ProposalsIndex.vue';
import ContactPicker from '../../../jrcCustomers/components/ContactPicker.vue';
import ContactCreateModal from '../../../jrcCustomers/components/ContactCreateModal.vue';
import { draftKey, readDraft } from '../formDrafts';

vi.mock('vue-router', () => ({ useRoute: vi.fn(), useRouter: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../../../jrcProjects/useProjects', () => ({
  useProjects: () => ({ projectText: value => value, enabled: ref(true) }),
}));
vi.mock('dashboard/api/crm', () => ({
  dealsAPI: { list: vi.fn(), create: vi.fn() },
  pipelinesAPI: { list: vi.fn() },
  stagesAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
  proposalsAPI: { create: vi.fn(), show: vi.fn(), creationOptions: vi.fn() },
}));
vi.mock('dashboard/api/contacts', () => ({ default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) } }));
vi.mock('dashboard/api/agents', () => ({ default: { get: vi.fn().mockResolvedValue({ data: [] }) } }));
vi.mock('dashboard/api/jrcCustomers', () => ({
  default: { contacts: vi.fn(), contact: vi.fn(), saveContact: vi.fn() },
}));

let wrappers;
let route;
const key = form => draftKey(1, 25, form);
const button = (wrapper, text) => wrapper.findAll('button').find(row => row.text().includes(text));
const input = (wrapper, label) => wrapper.findAll('label').find(row => row.text().startsWith(label)).find('input,select,textarea');
const page = async (component, full = false, props = {}) => {
  const store = createStore({ getters: {
    getCurrentRole: () => 'agent',
    getCurrentUser: () => ({ id: 25, accounts: [{ id: 1, role: 'agent' }] }),
    'accounts/isFeatureEnabledonAccount': () => () => true,
    'jrcCrm/deals/allDeals': () => [],
    'jrcCrm/proposals/allProposals': () => [],
  } });
  store.dispatch = vi.fn().mockResolvedValue();
  store.commit = vi.fn();
  const wrapper = (full ? mount : shallowMount)(component, {
    props, global: { plugins: [store], stubs: {
      Teleport: true, RouterLink: true,
      CrmPageHeader: { template: '<header><slot /><slot name="actions" /></header>' },
    } },
  });
  wrappers.push(wrapper);
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  wrappers = [];
  route = { name: 'crm_deals', query: {}, params: { accountId: '1' } };
  useRoute.mockReturnValue(route);
  useRouter.mockReturnValue({ push: vi.fn(), replace: vi.fn() });
  sessionStorage.clear();
  ContactsAPI.get.mockResolvedValue({ data: { payload: [] } });
  AgentsAPI.get.mockResolvedValue({ data: [] });
  pipelinesAPI.list.mockResolvedValue({ data: [{ id: 10, name: 'Vendas' }] });
  stagesAPI.list.mockResolvedValue({ data: [{ id: 11, name: 'Qualificação' }] });
  productsAPI.list.mockResolvedValue({ data: [{ id: 12, name: 'JRC', unit_price_cents: 10_000 }] });
  dealsAPI.list.mockResolvedValue({ data: [] });
  dealsAPI.create.mockResolvedValue({ data: { id: 20 } });
  proposalsAPI.creationOptions.mockResolvedValue({ data: { business_units: [] } });
});
afterEach(() => {
  wrappers.forEach(wrapper => wrapper.unmount());
  vi.clearAllMocks();
});

it('DRAFT-01 restores all deal fields and selected products after closing with X', async () => {
  const wrapper = await page(DealsIndex);
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  await input(wrapper, 'Título do negócio').setValue('Nexora completo');
  await input(wrapper, 'Observações').setValue('Notas que devem permanecer');
  await input(wrapper, 'Probabilidade').setValue(70);
  wrapper.findComponent({ name: 'CompanyPicker' }).vm.$emit('update:modelValue', 33);
  wrapper.findComponent({ name: 'ContactPicker' }).vm.$emit('update:modelValue', 44);
  const productSelect = wrapper.findAll('select').find(row => row.text().includes('Selecionar produto'));
  await productSelect.setValue(12);
  await button(wrapper, '+ Adicionar').trigger('click');
  await wrapper.get('button[aria-label="Fechar"]').trigger('click');
  expect(readDraft(key('crm:new_deal')).items).toHaveLength(1);
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  expect(input(wrapper, 'Título do negócio').element.value).toBe('Nexora completo');
  expect(input(wrapper, 'Observações').element.value).toBe('Notas que devem permanecer');
  expect(input(wrapper, 'Probabilidade').element.value).toBe('70');
  expect(wrapper.findComponent({ name: 'ContactPicker' }).props('modelValue')).toBe(44);
  expect(wrapper.text()).toContain('JRC');
});

it('DRAFT-02 clears only after a successful atomic save and preserves on an API failure', async () => {
  const wrapper = await page(DealsIndex);
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  await input(wrapper, 'Título do negócio').setValue('Não perder');
  dealsAPI.create.mockRejectedValueOnce({ response: { data: { errors: ['Falha'] } } });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  await wrapper.get('button[aria-label="Fechar"]').trigger('click');
  expect(readDraft(key('crm:new_deal')).form.title).toBe('Não perder');
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(dealsAPI.create).toHaveBeenLastCalledWith(expect.objectContaining({
    deal: expect.objectContaining({ title: 'Não perder' }), items: [],
  }));
  expect(readDraft(key('crm:new_deal'))).toBeNull();
});

it('DRAFT-03 discards explicitly while ESC preserves the current draft', async () => {
  const wrapper = await page(DealsIndex);
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  await input(wrapper, 'Título do negócio').setValue('Rascunho ESC');
  await wrapper.get('form').trigger('keydown', { key: 'Escape' });
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  expect(input(wrapper, 'Título do negócio').element.value).toBe('Rascunho ESC');
  await button(wrapper, 'Descartar rascunho').trigger('click');
  expect(readDraft(key('crm:new_deal'))).toBeNull();
  expect(input(wrapper, 'Título do negócio').element.value).toBe('');
});

it('DEAL-04 selects an inline native contact while keeping all parent deal fields', async () => {
  const wrapper = await page(DealsIndex);
  await button(wrapper, 'Novo Negócio').trigger('click');
  await flushPromises();
  await input(wrapper, 'Título do negócio').setValue('Negócio já preenchido');
  await input(wrapper, 'Observações').setValue('Escopo');
  await button(wrapper, 'Novo contato').trigger('click');
  wrapper.findComponent({ name: 'ContactCreateModal' }).vm.$emit('created', { id: 81, name: 'Comprador' });
  await flushPromises();
  expect(wrapper.findComponent({ name: 'ContactPicker' }).props('modelValue')).toBe(81);
  expect(input(wrapper, 'Título do negócio').element.value).toBe('Negócio já preenchido');
  expect(input(wrapper, 'Observações').element.value).toBe('Escopo');
  expect(wrapper.findComponent({ name: 'ContactCreateModal' }).exists()).toBe(false);
});

it('DRAFT-04 restores direct proposal identity, commercial conditions and discounted items', async () => {
  const wrapper = await page(ProposalsIndex);
  await button(wrapper, 'Nova proposta').trigger('click');
  await flushPromises();
  await wrapper.get('input[value="customer"]').setValue();
  wrapper.findComponent({ name: 'CompanyPicker' }).vm.$emit('update:modelValue', 33);
  wrapper.findComponent({ name: 'ContactPicker' }).vm.$emit('update:modelValue', 44);
  await input(wrapper, 'Título').setValue('Proposta recuperável');
  await wrapper.findAll('select').find(row => row.text().includes('Selecione produto')).setValue(12);
  await input(wrapper, 'Quantidade').setValue(2);
  await input(wrapper, 'Desconto do item').setValue(5);
  await button(wrapper, 'Adicionar item').trigger('click');
  await input(wrapper, 'Condição de pagamento').setValue('installments');
  await input(wrapper, 'Parcelas').setValue(4);
  await input(wrapper, 'Observações').setValue('Condição acordada');
  await wrapper.get('button[aria-label="Fechar"]').trigger('click');
  const draft = readDraft(key('crm:new_proposal'));
  expect(draft.items[0]).toMatchObject({ quantity: 2, discount_cents: 500 });
  await button(wrapper, 'Nova proposta').trigger('click');
  await flushPromises();
  expect(wrapper.get('input[value="customer"]').element.checked).toBe(true);
  expect(input(wrapper, 'Título').element.value).toBe('Proposta recuperável');
  expect(input(wrapper, 'Parcelas').element.value).toBe('4');
  expect(wrapper.findComponent({ name: 'CompanyPicker' }).props('modelValue')).toBe(33);
  expect(wrapper.findComponent({ name: 'ContactPicker' }).props('modelValue')).toBe(44);
});

it('DEAL-01/02 queries the official paginated master contacts and limits the result height', async () => {
  CustomerAPI.contacts.mockResolvedValue({ data: { payload: [{ id: 44, name: 'Thiago', company_id: 33 }] } });
  const wrapper = await page(ContactPicker, true, { companyId: 33 });
  await wrapper.get('input[type="search"]').setValue('Thiago');
  await wrapper.get('input').trigger('keydown', { key: 'Enter' });
  await flushPromises();
  expect(CustomerAPI.contacts).toHaveBeenLastCalledWith({ q: 'Thiago', company_id: 33, per_page: 15 });
  expect(wrapper.get('.max-h-48').classes()).toContain('overflow-y-auto');
  await button(wrapper, 'Thiago').trigger('click');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([44]);
});

it('DEAL-03 submits inline contact to the official master endpoint and returns its identity', async () => {
  CustomerAPI.saveContact.mockResolvedValue({ data: { payload: { id: 81, name: 'Comprador', company_id: 33 } } });
  const wrapper = await page(ContactCreateModal, true, { companyId: 33 });
  await input(wrapper, 'Nome').setValue('Comprador');
  await input(wrapper, 'E-mail').setValue('comprador@example.test');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(CustomerAPI.saveContact).toHaveBeenCalledWith(expect.objectContaining({
    name: 'Comprador', email: 'comprador@example.test', company_id: 33,
  }));
  expect(wrapper.emitted('created')[0][0].id).toBe(81);
  expect(readDraft(key('crm:new_contact:33'))).toBeNull();
});
