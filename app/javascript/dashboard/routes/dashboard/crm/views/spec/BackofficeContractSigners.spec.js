import { defineComponent, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import Signers from '../backoffice/BackofficeContractSigners.vue';
import Editor from '../backoffice/ContractSignerEditor.vue';
import Picker from '../backoffice/SignerContactPicker.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  api: { list: vi.fn(), create: vi.fn(), contacts: vi.fn() },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/backofficeSigners', () => ({ default: mocks.api }));
vi.mock('../../../jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: ref(true) }),
}));
const DialogStub = defineComponent({
  setup(_, { expose }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return { visible };
  },
  template: '<div v-if="visible"><slot /></div>',
});
const customer = {
  contact_id: 21,
  name: 'Contato cliente — SINTÉTICO',
  email: 'cliente@example.test',
  party: 'customer',
  personal_tax_identifier_masked: '***.***.***-25',
};
const issuer = {
  contact_id: 28,
  name: 'Contato emitente — SINTÉTICO',
  email: 'emitente@example.test',
  party: 'issuer',
  personal_tax_identifier_masked: '***.***.***-35',
};
const roster = {
  id: 7,
  revision: 1,
  customer_mode: 'single',
  issuer_mode: 'single',
  signers: [customer, issuer],
  current: true,
  change_reason: 'Proposta inicial',
  created_at: '2026-11-02T13:00:00Z',
};
const payload = {
  current: roster,
  data: [roster],
  contract: { id: 3, number: 'CTR-SINTÉTICO', source_digest: 'b'.repeat(64) },
  writable: true,
  meta: { page: 1, pages: 1, per_page: 10, total: 1 },
};
beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUser: { id: 4, accounts: [] },
    getCurrentRole: 'agent',
  });
  mocks.api.list.mockResolvedValue({ data: structuredClone(payload) });
  mocks.api.create.mockResolvedValue({ data: { id: 8, revision: 2 } });
  mocks.api.contacts.mockResolvedValue({
    data: {
      data: [],
      company: { name: 'Empresa SINTÉTICA' },
      meta: { page: 1, pages: 1, total: 0 },
    },
  });
});
const render = () =>
  mount(Signers, {
    props: { record: { id: 9, contract: { id: 3 } } },
    global: { stubs: { Dialog: DialogStub, SignerContactPicker: true } },
  });
const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);
const edit = async wrapper => {
  await flushPromises();
  await button(wrapper, 'Selecionar assinantes').trigger('click');
  await flushPromises();
};

describe('Canonical contract signers in Backoffice', () => {
  it('preserves a revision and reloads the canonical history without claiming authority or delivery', async () => {
    const wrapper = render();
    await edit(wrapper);
    await wrapper.get('textarea').setValue('Conferência das duas partes');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.create).toHaveBeenCalledWith(
      '1',
      9,
      expect.objectContaining({
        expected_revision: 1,
        expected_source_digest: 'b'.repeat(64),
        customer_mode: 'single',
        issuer_mode: 'single',
        signers: [
          { contact_id: 21, party: 'customer' },
          { contact_id: 28, party: 'issuer' },
        ],
        idempotency_key: expect.any(String),
      }),
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.text()).toContain('Proposta de assinantes preservada');
    expect(wrapper.text()).toContain('nenhum envio foi realizado');
    expect(wrapper.text()).toContain('não comprova poderes');
    expect(mocks.api.list).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('requires all selected joint signers and both parties before saving', async () => {
    const wrapper = render();
    await edit(wrapper);
    await wrapper.get('textarea').setValue('Assinatura conjunta');
    await wrapper.get('select').setValue('joint');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    wrapper.findComponent({ name: 'SignerContactPicker' }).vm.$emit('choose', {
      id: 22,
      name: 'Segundo cliente SINTÉTICO',
      email: 'segundo@example.test',
      selectable: true,
    });
    await flushPromises();
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.create.mock.calls[0][2].signers).toHaveLength(3);
    expect(mocks.api.create.mock.calls[0][2].customer_mode).toBe('joint');
    wrapper.unmount();
  });

  it('retains intent on an uncertain retry and freezes conflicting proposals until refresh', async () => {
    mocks.api.create.mockRejectedValueOnce(new Error('Network timeout'));
    mocks.api.create.mockRejectedValueOnce({ response: { status: 409 } });
    const wrapper = render();
    await edit(wrapper);
    await wrapper.get('textarea').setValue('Intenção preservada');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Proposta de assinantes preservada');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.create.mock.calls[0][2].idempotency_key).toBe(
      mocks.api.create.mock.calls[1][2].idempotency_key
    );
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain('O contrato ou a proposta mudou');
    await wrapper.get('form').trigger('submit');
    expect(mocks.api.create).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('clears canonical identities on denied save and never retains the old party data', async () => {
    mocks.api.create.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = render();
    await edit(wrapper);
    await wrapper.get('textarea').setValue('Acesso revogado');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).not.toContain(customer.name);
    expect(wrapper.text()).not.toContain(customer.email);
    expect(wrapper.text()).toContain('Os dados da tela foram limpos');
    expect(wrapper.findComponent(Editor).exists()).toBe(false);
    wrapper.unmount();
  });

  it('ignores a late save when the acting user changes', async () => {
    let release;
    mocks.api.create.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = render();
    await edit(wrapper);
    await wrapper.get('textarea').setValue('Usuário anterior');
    await wrapper.get('form').trigger('submit');
    mocks.getters.getCurrentUser.id = 5;
    await flushPromises();
    release({ data: { id: 8, revision: 2 } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Proposta de assinantes preservada');
    expect(wrapper.findComponent(Editor).exists()).toBe(false);
    wrapper.unmount();
  });

  it('discards late tenant responses and uses bounded history pages', async () => {
    let release;
    mocks.api.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = render();
    mocks.api.list.mockResolvedValue({
      data: {
        ...structuredClone(payload),
        data: [],
        current: null,
        meta: { page: 1, pages: 2, total: 11 },
      },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    release({ data: payload });
    await flushPromises();
    expect(wrapper.text()).not.toContain(customer.email);
    await button(wrapper, 'Próxima').trigger('click');
    await flushPromises();
    expect(mocks.api.list.mock.calls.at(-1).slice(0, 3)).toEqual(['2', 9, 2]);
    wrapper.unmount();
  });
});

describe('Scoped canonical signer picker', () => {
  it('searches and paginates the derived company and blocks incomplete people', async () => {
    mocks.api.contacts.mockResolvedValue({
      data: {
        data: [
          {
            id: 21,
            ...customer,
            selectable: false,
            identity_registered: false,
          },
        ],
        company: { name: 'Cliente SINTÉTICO' },
        meta: { page: 1, pages: 2, total: 11 },
      },
    });
    const wrapper = mount(Picker, {
      props: {
        accountId: '1',
        requestId: 9,
        contextKey: '1:9:4',
        party: 'customer',
      },
      global: { stubs: { SigningIdentityDialog: true } },
    });
    await flushPromises();
    expect(button(wrapper, 'Selecionar').attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('Confira nome, e-mail, CPF protegido');
    await wrapper.get('input').setValue('Outra pessoa');
    await button(wrapper, 'Buscar').trigger('click');
    await flushPromises();
    expect(mocks.api.contacts.mock.calls.at(-1)[2]).toEqual({
      party: 'customer',
      q: 'Outra pessoa',
      page: 1,
    });
    await button(wrapper, 'Próxima').trigger('click');
    await flushPromises();
    expect(mocks.api.contacts.mock.calls.at(-1)[2].page).toBe(2);
    await wrapper.setProps({ party: 'issuer' });
    await flushPromises();
    expect(mocks.api.contacts.mock.calls.at(-1)[2]).toEqual({
      party: 'issuer',
      q: '',
      page: 1,
    });
    wrapper.unmount();
  });

  it('ignores late contacts after switching parties and reports withdrawn directory access', async () => {
    let release;
    mocks.api.contacts.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = mount(Picker, {
      props: {
        accountId: '1',
        requestId: 9,
        contextKey: '1:9:4',
        party: 'customer',
      },
    });
    mocks.api.contacts.mockRejectedValueOnce({ response: { status: 401 } });
    await wrapper.setProps({ party: 'issuer' });
    await flushPromises();
    release({
      data: { data: [{ id: 21, ...customer }], meta: { page: 1, pages: 1 } },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain(customer.email);
    expect(wrapper.emitted('denied')).toHaveLength(1);
    wrapper.unmount();
  });
});
