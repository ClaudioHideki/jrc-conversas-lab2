import { defineComponent, reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Panel from '../backoffice/BackofficeContractSignatures.vue';
import Details from '../backoffice/SignatureDeliveryDetails.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  replace: vi.fn(),
  api: { list: vi.fn(), show: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/backofficeSignatures', () => ({
  default: mocks.api,
}));
const overview = {
  data: [
    {
      id: 8,
      version_number: 2,
      provider: 'docusign',
      environment: 'demo',
      connection_revision: 1,
      state: 'completion_reported',
      external_id: 'SYNTHETIC-ENVELOPE',
      last_event_at: '2026-11-02T12:00:00Z',
    },
  ],
  meta: { page: 1, pages: 2, total: 12, per_page: 10 },
  contract: { id: 4, signature_verified: false, signature_status: 'sent' },
  signature_required: true,
  signature_requirement_satisfied: false,
};
const DialogStub = defineComponent({
  setup(_, { expose }) {
    const open = ref(false);
    expose({
      open: () => {
        open.value = true;
      },
    });
    return { open };
  },
  template: '<section v-if="open" role="dialog"><slot /></section>',
});
const render = () =>
  mount(Panel, {
    props: { record: { id: 9, contract: { id: 4 } } },
    global: {
      stubs: { SignatureDeliveryDetails: true, SignatureIntentDialog: true },
    },
  });
const button = (wrapper, label) =>
  wrapper.findAll('button').find(row => row.text() === label);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({
    params: { accountId: '1' },
    query: { status: 'blocked', contractTab: 'signature' },
  });
  mocks.getters = reactive({
    getCurrentUser: { id: 3 },
    getCurrentRole: 'agent',
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  mocks.api.list.mockResolvedValue({ data: structuredClone(overview) });
  mocks.api.show.mockResolvedValue({
    data: {
      delivery: overview.data[0],
      data: [
        {
          id: 2,
          kind: 'completion_reported',
          created_at: '2026-11-02T12:00:00Z',
        },
      ],
      meta: { page: 1, pages: 2, per_page: 20, total: 21 },
    },
  });
});

it('keeps a reported completion distinct from evidence verification and operational release', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain(
    'Conclusão informada; evidências precisam de validação'
  );
  expect(wrapper.text()).toContain(
    'O contrato precisa estar assinado para liberar a implantação.'
  );
  expect(wrapper.text()).not.toContain(
    'Assinatura com evidências validadas internamente.'
  );
  expect(wrapper.text()).toContain('DocuSign');
  expect(wrapper.text()).toContain('Homologação');
  wrapper.unmount();
});

it('retains page and surrounding filters while closing details and reopening the responsive panel', async () => {
  mocks.route.query.signaturePage = '2';
  mocks.api.list.mockResolvedValue({
    data: { ...structuredClone(overview), meta: { page: 2, pages: 3 } },
  });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Histórico do envio').trigger('click');
  wrapper.findComponent({ name: 'SignatureDeliveryDetails' }).vm.$emit('close');
  await flushPromises();
  expect(mocks.api.list).toHaveBeenCalledTimes(1);
  expect(mocks.route.query).toMatchObject({
    signaturePage: '2',
    status: 'blocked',
  });
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(mocks.route.query).toMatchObject({
    signaturePage: '3',
    status: 'blocked',
    contractTab: 'signature',
    tab: 'contracts',
  });
  wrapper.unmount();
  const restored = render();
  await flushPromises();
  expect(mocks.api.list).toHaveBeenLastCalledWith(
    '1',
    9,
    3,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  restored.unmount();
});

it('discards a late response after changing accounts and never displays the previous envelope', async () => {
  let resolveOld;
  mocks.api.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  mocks.api.list.mockResolvedValue({
    data: { ...structuredClone(overview), data: [] },
  });
  mocks.route.params.accountId = '2';
  await flushPromises();
  resolveOld({ data: structuredClone(overview) });
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-ENVELOPE');
  expect(wrapper.text()).toContain('Nenhum envio registrado');
  wrapper.unmount();
});

it('clears records and closes details when current permissions are denied', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Histórico do envio').trigger('click');
  mocks.api.list.mockRejectedValue({ response: { status: 403 } });
  mocks.getters.getCurrentRole = 'denied';
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-ENVELOPE');
  expect(wrapper.text()).toContain(
    'Seu acesso a este histórico não está mais disponível.'
  );
  expect(
    wrapper.findComponent({ name: 'SignatureDeliveryDetails' }).exists()
  ).toBe(false);
  wrapper.unmount();
});

it('offers a real refresh after a network error without retaining stale success', async () => {
  mocks.api.list.mockRejectedValueOnce(new Error('synthetic network failure'));
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  await button(wrapper, 'Atualizar').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.text()).toContain('SYNTHETIC-ENVELOPE');
  wrapper.unmount();
});

it('closes an open send confirmation when a history refresh denies access', async () => {
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Enviar para assinatura').trigger('click');
  expect(
    wrapper.findComponent({ name: 'SignatureIntentDialog' }).exists()
  ).toBe(true);
  mocks.api.list.mockRejectedValueOnce({ response: { status: 403 } });
  await button(wrapper, 'Atualizar').trigger('click');
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'SignatureIntentDialog' }).exists()
  ).toBe(false);
  expect(
    button(wrapper, 'Enviar para assinatura').attributes('disabled')
  ).toBeDefined();
  expect(wrapper.text()).not.toContain('SYNTHETIC-ENVELOPE');
  wrapper.unmount();
});

it('offers local cancellation only before dispatch and reloads persisted state without changing filters', async () => {
  mocks.api.list.mockResolvedValue({
    data: {
      ...structuredClone(overview),
      data: [{ ...overview.data[0], state: 'prepared' }],
    },
  });
  const wrapper = render();
  await flushPromises();
  await button(wrapper, 'Cancelar antes do envio').trigger('click');
  const dialog = wrapper.findComponent({ name: 'SignatureIntentDialog' });
  expect(dialog.props('delivery').id).toBe(8);
  mocks.api.list.mockResolvedValue({
    data: {
      ...structuredClone(overview),
      data: [{ ...overview.data[0], state: 'canceled' }],
    },
  });
  dialog.vm.$emit('registered', 'canceled');
  await flushPromises();
  expect(wrapper.text()).toContain(
    'Intenção cancelada antes do envio. Nenhum cancelamento externo foi solicitado.'
  );
  expect(button(wrapper, 'Cancelar antes do envio')).toBeUndefined();
  expect(mocks.route.query.status).toBe('blocked');
  wrapper.unmount();
});

it('uses the native legacy satisfaction flag without inventing a verified signature', async () => {
  mocks.api.list.mockResolvedValue({
    data: {
      ...structuredClone(overview),
      workflow_version: 1,
      signature_requirement_satisfied: true,
      contract: { signature_verified: false },
    },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).not.toContain(
    'O contrato precisa estar assinado para liberar a implantação.'
  );
  expect(wrapper.text()).not.toContain(
    'Assinatura com evidências validadas internamente.'
  );
  wrapper.unmount();
});

it('requires an explicit boolean verified fact rather than a truthy provider field', async () => {
  mocks.api.list.mockResolvedValue({
    data: {
      ...structuredClone(overview),
      contract: { signature_verified: 'true' },
    },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).not.toContain(
    'Assinatura com evidências validadas internamente.'
  );
  wrapper.unmount();
});

it('pages actual event history and keeps unknown or private payload fields out of the popup', async () => {
  const wrapper = mount(Details, {
    props: { accountId: '1', requestId: 9, deliveryId: 8 },
    global: { stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  expect(wrapper.text()).toContain('Conclusão informada pelo fornecedor');
  mocks.api.show.mockResolvedValue({
    data: {
      delivery: overview.data[0],
      data: [
        {
          id: 1,
          kind: 'PRIVATE_EVENT_NAME',
          payload: 'PRIVATE_SECRET_CONTENT',
        },
      ],
      meta: { page: 2, pages: 2 },
    },
  });
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(mocks.api.show).toHaveBeenLastCalledWith(
    '1',
    9,
    8,
    2,
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(wrapper.text()).toContain('Evento registrado');
  expect(wrapper.text()).not.toContain('PRIVATE');
  wrapper.unmount();
});

it('propagates a denied direct history URL instead of rendering a cached event', async () => {
  mocks.api.show.mockRejectedValue({ response: { status: 404 } });
  const wrapper = mount(Details, {
    props: { accountId: '1', requestId: 9, deliveryId: 8 },
    global: { stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('Conclusão informada pelo fornecedor');
  wrapper.unmount();
});
