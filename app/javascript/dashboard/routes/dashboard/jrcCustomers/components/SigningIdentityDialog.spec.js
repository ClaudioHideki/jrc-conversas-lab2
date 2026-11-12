import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import SigningIdentityDialog from './SigningIdentityDialog.vue';
import ContactCreateModal from './ContactCreateModal.vue';
import { draftKey } from '../../crm/helpers/formDrafts';

const mocks = vi.hoisted(() => ({
  signingIdentity: vi.fn(),
  saveSigningIdentity: vi.fn(),
  saveContact: vi.fn(),
  account: null,
  access: null,
  user: null,
  route: null,
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('dashboard/api/contacts', () => ({ default: { create: vi.fn() } }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: mocks.account,
    canAccess: mocks.access,
    enabled: ref(true),
  }),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      get getCurrentUser() {
        return mocks.user.value;
      },
    },
  }),
}));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    template: '<section><slot /></section>',
    emits: ['close'],
    methods: {
      open() {},
      close() {
        this.$emit('close');
      },
    },
  },
}));

const payload = (id = 7, cpf = '52998224725', revision = 1) => ({
  data: {
    contact: {
      id,
      name: `TESTE SINTÉTICO ${id}`,
      company_name: 'Empresa de teste',
    },
    payload: {
      personal_tax_identifier: cpf,
      revision,
      signing_authority_verified: false,
    },
  },
});
const options = { global: { stubs: { Teleport: true } } };

describe('Protected Contact signing identity', () => {
  beforeEach(() => {
    mocks.signingIdentity.mockReset().mockResolvedValue(payload());
    mocks.saveSigningIdentity.mockReset();
    mocks.saveContact.mockReset();
    mocks.account = ref(1);
    mocks.access = ref(true);
    mocks.user = ref({ id: 10 });
    mocks.route = reactive({ params: { accountId: '1' } });
    localStorage.clear();
    sessionStorage.clear();
  });

  it('reads the native Contact identity through an explicit account without storing the CPF locally', async () => {
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    expect(mocks.signingIdentity).toHaveBeenCalledWith(1, 7, {
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.find('input').element.value).toBe('52998224725');
    expect(wrapper.text()).toContain('Poderes para assinar dependem');
    expect(localStorage.length).toBe(0);
    wrapper.unmount();
  });

  it('saves the identifier and revision without treating it as signing authority', async () => {
    mocks.saveSigningIdentity.mockResolvedValue(payload(7, '11144477735', 2));
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    await wrapper.find('input').setValue('11144477735');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.saveSigningIdentity).toHaveBeenCalledWith(1, 7, {
      identity: { personal_tax_identifier: '11144477735' },
      revision: 1,
    });
    expect(wrapper.find('[role="status"]').text()).toContain(
      'poderes de assinatura ainda precisam ser validados'
    );
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(
      wrapper.find('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('discards a late response after changing account and Contact', async () => {
    let finish;
    mocks.signingIdentity.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    mocks.signingIdentity.mockResolvedValueOnce(payload(8, '11144477735'));
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    mocks.account.value = 2;
    await wrapper.setProps({ contactId: 8 });
    await flushPromises();
    finish(payload());
    await flushPromises();
    expect(wrapper.find('input').element.value).toBe('11144477735');
    expect(wrapper.text()).toContain('TESTE SINTÉTICO 8');
    expect(wrapper.text()).not.toContain('TESTE SINTÉTICO 7');
    wrapper.unmount();
  });

  it('ignores an old save after the user switches account', async () => {
    let finish;
    mocks.saveSigningIdentity.mockReturnValueOnce(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    await wrapper.find('input').setValue('11144477735');
    await wrapper.find('form').trigger('submit');
    mocks.account.value = 2;
    mocks.signingIdentity.mockResolvedValueOnce(payload(8, '11144477735'));
    await wrapper.setProps({ contactId: 8 });
    await flushPromises();
    finish(payload(7, '52998224725', 2));
    await flushPromises();
    expect(wrapper.find('input').element.value).toBe('11144477735');
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('clears protected data when permission is revoked during a save', async () => {
    mocks.saveSigningIdentity.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    await wrapper.find('input').setValue('11144477735');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toContain('acesso atual');
    expect(wrapper.html()).not.toMatch(/52998224725|11144477735/);
    wrapper.unmount();
  });

  it('reports a stale revision without showing a successful save', async () => {
    mocks.saveSigningIdentity.mockRejectedValue({ response: { status: 409 } });
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    await wrapper.find('input').setValue('11144477735');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Atualize antes de gravar'
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
    wrapper.unmount();
  });

  it('clears the Contact and closes the dialog when directory access disappears', async () => {
    const wrapper = mount(SigningIdentityDialog, { props: { contactId: 7 } });
    await flushPromises();
    mocks.access.value = false;
    await flushPromises();
    expect(wrapper.find('input').exists()).toBe(false);
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });

  it('preserves ordinary new-Contact drafts while excluding personal identifiers', async () => {
    const wrapper = mount(ContactCreateModal, options);
    await wrapper.find('input').setValue('TESTE SINTÉTICO — Rascunho');
    await wrapper
      .find('input[name="personal_tax_identifier"]')
      .setValue('52998224725');
    await wrapper.find('button[aria-label]').trigger('click');
    const stored = sessionStorage.getItem(
      draftKey('1', 10, 'crm:new_contact:standalone')
    );
    expect(stored).toContain('TESTE SINTÉTICO — Rascunho');
    expect(stored).not.toContain('52998224725');
    expect(stored).not.toContain('personal_tax_identifier');
    expect(localStorage.length).toBe(0);
    wrapper.unmount();
  });
});
