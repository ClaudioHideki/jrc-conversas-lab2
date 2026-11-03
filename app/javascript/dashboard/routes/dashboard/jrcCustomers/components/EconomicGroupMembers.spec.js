import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Members from './EconomicGroupMembers.vue';
import Picker from './CompanyPicker.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  economicGroupRecords: vi.fn(),
  assignEconomicGroup: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.access}`),
    canAccess: computed(() => mocks.state.access),
  }),
}));
const group = {
  id: 7,
  name: 'MOCK — Grupo',
  can_manage: true,
  principal_company: null,
};
const company = {
  id: 8,
  name: 'MOCK — Empresa',
  economic_group: 'MOCK — Anterior',
  revision: '2026-11-03T10:00:00.000000Z',
};
const response = (row = company) => ({
  data: { payload: [row], meta: { total: 26, per_page: 25 } },
});
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, access: true });
  mocks.economicGroupRecords.mockResolvedValue(response());
  mocks.assignEconomicGroup.mockResolvedValue({ data: { group } });
});
const stubDialog = {
  setup: (_, { expose }) => expose({ open: vi.fn(), close: vi.fn() }),
  template: '<aside><slot /></aside>',
};
const render = props =>
  mount(Members, {
    props: { group, ...props },
    global: { stubs: { CompanyPicker: true, Dialog: stubDialog } },
  });

it('requires explicit transfer confirmation and submits the selected company revision, never a caller account grant', async () => {
  const wrapper = render();
  await flushPromises();
  wrapper.findComponent(Picker).vm.$emit('selected', company);
  await flushPromises();
  const link = () =>
    wrapper
      .findAll('button')
      .find(button => button.text() === 'Vincular ao grupo');
  expect(link().attributes('disabled')).toBeDefined();
  expect(mocks.assignEconomicGroup).not.toHaveBeenCalled();
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await link().trigger('click');
  await flushPromises();
  expect(mocks.assignEconomicGroup).toHaveBeenCalledWith(
    7,
    {
      company_id: 8,
      company_revision: company.revision,
      remove: false,
      confirm_transfer: true,
    },
    { accountId: 1 }
  );
  expect(wrapper.emitted('changed')).toHaveLength(1);
  wrapper.unmount();
});

it('keeps old-account rows out of the member view and pages through server results', async () => {
  let resolveOld;
  mocks.economicGroupRecords.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  mocks.state.account = 2;
  await flushPromises();
  resolveOld(response({ ...company, name: 'PRIVATE_OLD_ACCOUNT' }));
  await flushPromises();
  expect(wrapper.text()).not.toContain('PRIVATE_OLD_ACCOUNT');
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.economicGroupRecords).toHaveBeenLastCalledWith(
    7,
    'members',
    { q: '', page: 2 },
    expect.objectContaining({ accountId: 2 })
  );
  wrapper.unmount();
});

it('uses the real native confirmation form, retains the company on server rejection and sends no write on cancel', async () => {
  const originalShow = HTMLDialogElement.prototype.showModal;
  const originalClose = HTMLDialogElement.prototype.close;
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
  mocks.assignEconomicGroup.mockRejectedValue({
    response: { data: { error: 'MOCK — Vínculo preservado' } },
  });
  let wrapper;
  try {
    wrapper = mount(Members, {
      props: { group },
      attachTo: document.body,
      global: {
        stubs: {
          CompanyPicker: true,
          TeleportWithDirection: { template: '<div><slot /></div>' },
        },
      },
    });
    await flushPromises();
    const open = () =>
      wrapper
        .findAll('article button')
        .find(button => button.text() === 'Desvincular empresa')
        .trigger('click');
    await open();
    expect(mocks.assignEconomicGroup).not.toHaveBeenCalled();
    document.querySelector('dialog[open] button[type="button"]').click();
    await flushPromises();
    expect(mocks.assignEconomicGroup).not.toHaveBeenCalled();
    await open();
    document.querySelector('dialog[open] button[type="submit"]').click();
    await flushPromises();
    expect(mocks.assignEconomicGroup).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        company_id: 8,
        company_revision: company.revision,
        remove: true,
      }),
      { accountId: 1 }
    );
    expect(document.querySelector('dialog[open]').textContent).toContain(
      'MOCK — Vínculo preservado'
    );
    expect(wrapper.find('article').text()).toContain(company.name);
    expect(wrapper.emitted('changed')).toBeUndefined();
  } finally {
    wrapper?.unmount();
    HTMLDialogElement.prototype.showModal = originalShow;
    HTMLDialogElement.prototype.close = originalClose;
  }
});
