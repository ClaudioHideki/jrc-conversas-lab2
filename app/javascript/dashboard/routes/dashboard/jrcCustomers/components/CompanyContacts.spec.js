import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import People from './CompanyContacts.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  contacts: vi.fn(),
  saveContact: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
  }),
}));
const candidate = {
  id: 43,
  name: 'MOCK — Pessoa existente',
  company_id: null,
  email: 'candidate@example.test',
};
const result = (payload = []) => ({
  data: { payload, meta: { total: payload.length } },
});
const render = () =>
  mount(People, {
    props: { companyId: 7 },
    global: {
      stubs: {
        ContactDetailsDialog: {
          name: 'ContactDetailsDialog',
          props: ['contactId'],
          template: '<section />',
        },
        MasterContactPanel: true,
      },
    },
  });

const button = (wrapper, name) =>
  wrapper.findAll('button').find(item => item.text() === name);

it('confirms the primary change and saves the exact canonical person within the original account', async () => {
  mocks.contacts.mockResolvedValue(
    result([{ ...candidate, company_id: 7, company_contact_status: 'active' }])
  );
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Definir como principal').trigger('click');
  expect(mocks.saveContact).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  await button(wrapper, 'Definir como principal').trigger('click');
  await flushPromises();
  expect(mocks.saveContact).toHaveBeenCalledWith(
    { company_id: 7, company_primary: true },
    43,
    { confirm_primary_change: true },
    { accountId: 1 }
  );
  expect(wrapper.emitted('changed')).toHaveLength(1);
  confirm.mockRestore();
  wrapper.unmount();
});
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'agent' });
  mocks.contacts.mockImplementation(params =>
    Promise.resolve(result(params.q ? [candidate] : []))
  );
  mocks.saveContact.mockResolvedValue({ data: { payload: candidate } });
});

it('discards candidates returned after the account changed and the new directory denied the company', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Vincular contato existente').trigger('click');
  await wrapper.find('form input').setValue('MOCK');
  let resolveSearch;
  mocks.contacts.mockReturnValueOnce(
    new Promise(resolve => {
      resolveSearch = resolve;
    })
  );
  await wrapper.find('form').trigger('submit');
  mocks.contacts.mockRejectedValueOnce({
    response: { status: 404, data: { error: 'MOCK — unavailable company' } },
  });
  mocks.state.account = 2;
  await flushPromises();
  resolveSearch(
    result([{ ...candidate, name: 'PRIVATE_OLD_ACCOUNT_CANDIDATE' }])
  );
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_ACCOUNT_CANDIDATE');
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(mocks.saveContact).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('pins reassignment to its original account and discards a late write callback after a role change', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Vincular contato existente').trigger('click');
  await wrapper.find('form input').setValue('MOCK');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  let resolveWrite;
  mocks.saveContact.mockReturnValueOnce(
    new Promise(resolve => {
      resolveWrite = resolve;
    })
  );
  await button(wrapper, 'Usar existente').trigger('click');
  expect(mocks.saveContact).toHaveBeenCalledWith(
    { company_id: 7 },
    43,
    { confirm_reassignment: false },
    { accountId: 1 }
  );
  mocks.state.role = 'changed';
  await flushPromises();
  const calls = mocks.contacts.mock.calls.length;
  resolveWrite({ data: { payload: candidate } });
  await flushPromises();
  expect(mocks.contacts).toHaveBeenCalledTimes(calls);
  expect(wrapper.emitted('changed')).toBeUndefined();
  expect(wrapper.findComponent({ name: 'ContactDetailsDialog' }).exists()).toBe(
    false
  );
  wrapper.unmount();
});

it('uses the native create response and opens its exact contact ID without forcing a distinct duplicate', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Cadastrar contato').trigger('click');
  await wrapper.find('input[required]').setValue('MOCK — Nova pessoa');
  mocks.saveContact.mockResolvedValue({ data: { payload: { id: 99 } } });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveContact).toHaveBeenCalledWith(
    expect.objectContaining({ name: 'MOCK — Nova pessoa', company_id: 7 }),
    null,
    {},
    { accountId: 1 }
  );
  expect(
    wrapper.findComponent({ name: 'ContactDetailsDialog' }).props('contactId')
  ).toBe(99);
  expect(wrapper.emitted('changed')).toHaveLength(1);
  wrapper.unmount();
});

it('does not announce changed or an empty directory when the post-write read is denied', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Vincular contato existente').trigger('click');
  await wrapper.find('form input').setValue('MOCK');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  mocks.contacts.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'MOCK — withdrawn' } },
  });
  await button(wrapper, 'Usar existente').trigger('click');
  await flushPromises();
  expect(wrapper.emitted('changed')).toBeUndefined();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.find('[role="alert"]').text()).toContain('withdrawn');
  expect(wrapper.text()).not.toContain('Nenhum registro encontrado.');
  wrapper.unmount();
});
