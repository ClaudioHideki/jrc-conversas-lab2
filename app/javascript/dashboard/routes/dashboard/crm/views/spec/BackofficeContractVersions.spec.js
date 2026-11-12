import { defineComponent, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import Versions from '../backoffice/BackofficeContractVersions.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  api: {
    list: vi.fn(),
    create: vi.fn(),
    download: vi.fn(),
    differences: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeContractVersionsAPI: mocks.api,
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
const version = {
  id: 19,
  number: 1,
  current: true,
  created_by_name: 'Sofia — TESTE SINTÉTICO',
  created_at: '2026-11-02T12:00:00Z',
  change_reason: 'Minuta inicial',
  pdf_sha256: 'a'.repeat(64),
};
const payload = {
  data: [version],
  meta: { page: 1, per_page: 10, total: 1 },
  writable: true,
  contract: {
    id: 7,
    number: 'CTR-TESTE',
    source_digest: 'b'.repeat(64),
    signature_status: 'not_started',
  },
};

beforeEach(() => {
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUser: { id: 4, accounts: [] },
    getCurrentRole: 'agent',
  });
  mocks.api.list.mockResolvedValue({ data: structuredClone(payload) });
  mocks.api.create.mockResolvedValue({ data: version });
});
const render = () =>
  mount(Versions, {
    props: { record: { id: 9, status: 'in_progress', contract: { id: 7 } } },
    global: { stubs: { Dialog: DialogStub, ContractVersionDetails: true } },
  });

describe('Backoffice contract version workflow', () => {
  it('explains directory access before generation without blocking otherwise permitted draft editing', async () => {
    mocks.api.list.mockResolvedValue({
      data: { ...structuredClone(payload), signer_directory_access: false },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('acesso ao cadastro de contatos');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Gerar nova versão')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Editar minuta')
        .attributes('disabled')
    ).toBeUndefined();
    expect(mocks.api.create).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('enables generation only after the server confirms the configured directory access', async () => {
    mocks.api.list.mockResolvedValue({
      data: { ...structuredClone(payload), signer_directory_access: true },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).not.toContain('acesso ao cadastro de contatos');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Gerar nova versão')
        .attributes('disabled')
    ).toBeUndefined();
    wrapper.unmount();
  });

  it('requires a reason and confirms creation only after the real API acknowledgement', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Gerar nova versão')
      .trigger('click');
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('textarea')
      .setValue('Conferência da cláusula de vigência');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.create).toHaveBeenCalledWith(
      '1',
      9,
      expect.objectContaining({
        expected_source_digest: 'b'.repeat(64),
        change_reason: 'Conferência da cláusula de vigência',
        idempotency_key: expect.any(String),
      }),
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.text()).toContain('Versão contratual criada e preservada');
    expect(wrapper.text()).toContain(
      'Nenhum envio para assinatura foi realizado'
    );
    expect(mocks.api.list).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('retains the same intent for an uncertain retry and does not invent a successful version', async () => {
    mocks.api.create.mockRejectedValueOnce(new Error('Network timeout'));
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Gerar nova versão')
      .trigger('click');
    await wrapper.get('textarea').setValue('Minuta com intenção preservada');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'Versão contratual criada e preservada'
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.create.mock.calls[0][2].idempotency_key).toBe(
      mocks.api.create.mock.calls[1][2].idempotency_key
    );
    wrapper.unmount();
  });

  it('discards a late history response when the account changes', async () => {
    let release;
    mocks.api.list.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = render();
    mocks.route.params.accountId = '2';
    mocks.api.list.mockResolvedValue({
      data: {
        ...structuredClone(payload),
        data: [],
        contract: null,
        writable: false,
      },
    });
    await flushPromises();
    release({ data: payload });
    await flushPromises();
    expect(wrapper.text()).not.toContain('CTR-TESTE');
    expect(wrapper.text()).not.toContain('Sofia');
    expect(mocks.api.list.mock.calls[1][0]).toBe('2');
    wrapper.unmount();
  });

  it('discards a late save acknowledgement after changing the acting user', async () => {
    let release;
    mocks.api.create.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          release = resolve;
        })
    );
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Gerar nova versão')
      .trigger('click');
    await wrapper.get('textarea').setValue('Operação do usuário anterior');
    await wrapper.get('form').trigger('submit');
    mocks.getters.getCurrentUser.id = 8;
    await flushPromises();
    release({ data: version });
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'Versão contratual criada e preservada'
    );
    expect(wrapper.find('textarea').exists()).toBe(false);
    wrapper.unmount();
  });

  it('clears the history on denied access and leaves sent contracts locked', async () => {
    const wrapper = render();
    await flushPromises();
    mocks.api.list.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Atualizar')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('Sofia');
    expect(wrapper.text()).toContain('não tem mais acesso');
    expect(
      wrapper
        .findAll('button')
        .find(button => button.text() === 'Gerar nova versão')
        .attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
    mocks.api.list.mockResolvedValue({
      data: {
        ...structuredClone(payload),
        contract: { ...payload.contract, signature_status: 'sent' },
      },
    });
    const locked = render();
    await flushPromises();
    expect(
      locked
        .findAll('button')
        .find(button => button.text() === 'Gerar nova versão')
        .attributes('disabled')
    ).toBeDefined();
    locked.unmount();
  });

  it('shows a source conflict without resubmitting and requests bounded history pages', async () => {
    mocks.api.create.mockRejectedValueOnce({
      response: { status: 409, data: { code: 'CONTRACT_SOURCE_CHANGED' } },
    });
    mocks.api.list.mockResolvedValue({
      data: {
        ...structuredClone(payload),
        meta: { page: 1, per_page: 10, total: 11 },
      },
    });
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
    await flushPromises();
    expect(mocks.api.list.mock.calls.at(-1)[2]).toEqual({ page: 2 });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Gerar nova versão')
      .trigger('click');
    await wrapper.get('textarea').setValue('Revisão que mudou');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('A minuta mudou desde a prévia');
    expect(wrapper.text()).not.toContain(
      'Versão contratual criada e preservada'
    );
    expect(mocks.api.create).toHaveBeenCalledTimes(1);
    expect(
      wrapper.get('button[type="submit"]').attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });

  it('clears scoped data and does not announce success when authorization is revoked after generation', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Gerar nova versão')
      .trigger('click');
    await wrapper
      .get('textarea')
      .setValue('Revisão autorizada antes da revogação');
    mocks.api.list.mockRejectedValueOnce({ response: { status: 403 } });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('não tem mais acesso');
    expect(wrapper.text()).not.toContain('Sofia');
    expect(wrapper.text()).not.toContain(
      'Versão contratual criada e preservada'
    );
    wrapper.unmount();
  });
});
