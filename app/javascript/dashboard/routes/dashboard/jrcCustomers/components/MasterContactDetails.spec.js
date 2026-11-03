import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Details from './MasterContactDetails.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  contact: vi.fn(),
  saveContact: vi.fn(),
  duplicates: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    enabled: computed(() => true),
    canAccess: computed(() => mocks.state.access),
    canAdmin: computed(() => false),
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
const record = (point = 'MOCK — PRIVATE_CONTACT_CHANNEL') => ({
  data: {
    payload: {
      id: 42,
      company_id: null,
      job_title: 'Analista',
      department: 'Atendimento',
      registration_status: 'registered',
      company_role: null,
      company_primary: false,
      company_contact_status: 'active',
    },
    contact_points: [{ id: 1, kind: 'email', value: point }],
  },
});
const render = () =>
  mount(Details, {
    props: { contactId: 42, expandedByDefault: true },
    global: {
      stubs: {
        CompanyPicker: true,
        SigningIdentityDialog: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, role: 'agent', access: true });
  mocks.contact.mockResolvedValue(record());
  mocks.saveContact.mockResolvedValue({ data: {} });
});

it('uses the existing editor and pins the source account separately from reassignment confirmation', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.findAll('form')).toHaveLength(2);
  await wrapper.find('form input').setValue('MOCK — Novo cargo');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveContact).toHaveBeenCalledWith(
    expect.objectContaining({ job_title: 'MOCK — Novo cargo' }),
    42,
    { confirm_reassignment: false, confirm_primary_change: false },
    { accountId: 1 }
  );
  expect(mocks.contact).toHaveBeenLastCalledWith(
    42,
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(wrapper.emitted('updated')).toHaveLength(1);
  wrapper.unmount();
});

it('saves a company role and primary only after explicit confirmation using the existing canonical update', async () => {
  const linked = record();
  linked.data.payload.company_id = 7;
  mocks.contact.mockResolvedValue(linked);
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
  const wrapper = render();
  await flushPromises();
  await wrapper.find('form select').setValue('technical');
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(confirm).toHaveBeenCalledOnce();
  expect(mocks.saveContact).toHaveBeenCalledWith(
    expect.objectContaining({
      company_id: 7,
      company_role: 'technical',
      company_primary: true,
    }),
    42,
    { confirm_reassignment: false, confirm_primary_change: true },
    { accountId: 1 }
  );
  expect(wrapper.emitted('updated')).toHaveLength(1);
  confirm.mockRestore();
  wrapper.unmount();
});

it('clears the previous company context before a confirmed transfer and makes no write when confirmation is canceled', async () => {
  const linked = record();
  Object.assign(linked.data.payload, {
    company_id: 7,
    company_role: 'finance',
    company_primary: true,
  });
  mocks.contact.mockResolvedValue(linked);
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
  const wrapper = render();
  await flushPromises();
  wrapper
    .findComponent({ name: 'CompanyPicker' })
    .vm.$emit('update:modelValue', 8);
  await flushPromises();
  expect(wrapper.find('form input').element.disabled).toBe(true);
  expect(wrapper.find('input[type="checkbox"]').element.checked).toBe(false);
  await wrapper.find('form').trigger('submit');
  expect(mocks.saveContact).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveContact).toHaveBeenCalledWith(
    expect.objectContaining({
      company_id: 8,
      job_title: '',
      department: '',
      company_role: '',
      company_primary: false,
    }),
    42,
    { confirm_reassignment: true, confirm_primary_change: false },
    { accountId: 1 }
  );
  confirm.mockRestore();
  wrapper.unmount();
});

it('does not emit saved when the post-write refresh is denied and clears previous private channels', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('PRIVATE_CONTACT_CHANNEL');
  mocks.contact.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'MOCK — access withdrawn' } },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveContact).toHaveBeenCalledTimes(1);
  expect(wrapper.emitted('updated')).toBeUndefined();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('PRIVATE_CONTACT_CHANNEL');
  expect(wrapper.find('[role="alert"]').text()).toContain('access withdrawn');
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
  wrapper.unmount();
});

it('discards a read that belongs to a previous account after the new account is denied', async () => {
  let resolveOld;
  mocks.contact.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  const wrapper = render();
  mocks.contact.mockRejectedValueOnce({
    response: { status: 404, data: { error: 'MOCK — unavailable subject' } },
  });
  mocks.state.account = 2;
  await flushPromises();
  resolveOld(record());
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_CONTACT_CHANNEL');
  expect(wrapper.findAll('form')).toHaveLength(0);
  expect(wrapper.emitted('denied')).toHaveLength(1);
  wrapper.unmount();
});

it('does not apply a late mutation callback to a changed role or overwrite its fresh view', async () => {
  let resolveWrite;
  mocks.saveContact.mockReturnValueOnce(
    new Promise(resolve => {
      resolveWrite = resolve;
    })
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.find('form').trigger('submit');
  mocks.contact.mockResolvedValue(record('MOCK — NEW_ROLE_CHANNEL'));
  mocks.state.role = 'changed';
  await flushPromises();
  resolveWrite({ data: {} });
  await flushPromises();
  expect(mocks.contact).toHaveBeenCalledTimes(2);
  expect(wrapper.text()).toContain('NEW_ROLE_CHANNEL');
  expect(wrapper.emitted('updated')).toBeUndefined();
  expect(wrapper.find('[role="status"]').exists()).toBe(false);
  wrapper.unmount();
});

it('clears channels and forms as soon as directory access is withdrawn', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.state.access = false;
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_CONTACT_CHANNEL');
  expect(wrapper.findAll('form')).toHaveLength(0);
  expect(mocks.contact).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
