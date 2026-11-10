import { defineComponent, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Dialog from '../backoffice/SignatureIntentDialog.vue';

const mocks = vi.hoisted(() => ({
  preparation: vi.fn(),
  create: vi.fn(),
  cancelPrepared: vi.fn(),
}));
vi.mock('dashboard/api/crm/backofficeSignatures', () => ({ default: mocks }));
const preview = {
  can_send: true,
  version: { id: 31, number: 3, pdf_sha256: 'a'.repeat(64) },
  authority_proposal_id: 41,
  expected_source_digest: 'b'.repeat(64),
  connection: {
    id: 51,
    provider: 'docusign',
    environment: 'demo',
    revision: 2,
  },
};
const DialogStub = defineComponent({
  setup(_, { expose }) {
    const opened = ref(false);
    expose({
      open: () => {
        opened.value = true;
      },
    });
    return { opened };
  },
  template: '<section v-if="opened" role="dialog"><slot /></section>',
});
const render = (props = {}) =>
  mount(Dialog, {
    props: { accountId: '1', requestId: 9, ...props },
    global: { stubs: { Dialog: DialogStub } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.preparation.mockResolvedValue({ data: structuredClone(preview) });
  mocks.create.mockResolvedValue({
    data: { id: 71, state: 'prepared', external_id: null },
  });
  mocks.cancelPrepared.mockResolvedValue({
    data: { id: 71, state: 'canceled' },
  });
});

it('requires confirmation of the exact preview and registers an intent without claiming sent or signed', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Homologação');
  expect(wrapper.text()).toContain('DocuSign');
  expect(wrapper.text()).toContain('a'.repeat(64));
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.create).toHaveBeenCalledWith(
    '1',
    9,
    {
      version_id: 31,
      authority_proposal_id: 41,
      expected_connection_id: 51,
      expected_source_digest: 'b'.repeat(64),
      idempotency_key: expect.any(String),
    },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  expect(wrapper.emitted('registered')).toEqual([['prepared']]);
  expect(wrapper.text()).not.toContain('Enviado com sucesso');
  wrapper.unmount();
});

it('retains the same idempotency key and sealed binding after an unconfirmed broker or network outcome', async () => {
  mocks.create.mockRejectedValueOnce({ response: { status: 500 } });
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('registered')).toBeUndefined();
  expect(wrapper.find('[role="alert"]').text()).toContain('mesma intenção');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.create.mock.calls[0][2]).toEqual(mocks.create.mock.calls[1][2]);
  expect(wrapper.emitted('registered')).toHaveLength(1);
  wrapper.unmount();
});

it('invalidates confirmation after a changed connection and requires an explicit fresh preview', async () => {
  mocks.create.mockRejectedValueOnce({
    response: { status: 409, data: { code: 'CONNECTION_CHANGED' } },
  });
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).toContain('A conexão mudou');
  expect(wrapper.find('input').exists()).toBe(false);
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  mocks.preparation.mockResolvedValue({
    data: {
      ...structuredClone(preview),
      connection: { ...preview.connection, id: 52 },
    },
  });
  await wrapper.find('button[type="button"]').trigger('click');
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.create.mock.calls[1][2].expected_connection_id).toBe(52);
  expect(mocks.create.mock.calls[1][2].idempotency_key).not.toBe(
    mocks.create.mock.calls[0][2].idempotency_key
  );
  wrapper.unmount();
});

it.each([
  'AUTHORITY_APPROVAL_REQUIRED',
  'CONNECTION_NOT_READY',
  'DELIVERY_IN_PROGRESS',
  'DELIVERY_VERSION_ALREADY_REGISTERED',
])('shows a real %s block with no submit capability', async code => {
  mocks.preparation.mockResolvedValue({
    data: { can_send: false, blocked_code: code },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('input').exists()).toBe(false);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.create).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('maps unknown error codes to a safe message without exposing provider payloads', async () => {
  mocks.preparation.mockResolvedValue({
    data: { can_send: false, blocked_code: 'PRIVATE_PROVIDER_RESPONSE' },
  });
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain(
    'O envio está bloqueado pelas regras atuais.'
  );
  expect(wrapper.text()).not.toContain('PRIVATE_PROVIDER_RESPONSE');
  wrapper.unmount();
});

it('clears the preview and delegates permission denial when access is revoked on confirmation', async () => {
  mocks.create.mockRejectedValue({ response: { status: 404 } });
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('a'.repeat(64));
  expect(wrapper.emitted('registered')).toBeUndefined();
  wrapper.unmount();
});

it('ignores a late successful response after its request context was closed', async () => {
  let resolveSend;
  mocks.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveSend = resolve;
      })
  );
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  wrapper.unmount();
  resolveSend({ data: { id: 71, state: 'prepared' } });
  await flushPromises();
  expect(wrapper.emitted('registered')).toBeUndefined();
  expect(mocks.create.mock.calls[0][3].signal.aborted).toBe(true);
});

it('confirms prepared-only local cancellation using the existing intent ID with no new send', async () => {
  const wrapper = render({ delivery: { id: 71, state: 'prepared' } });
  await flushPromises();
  expect(wrapper.text()).toContain(
    'cancela somente uma intenção ainda não despachada'
  );
  expect(mocks.preparation).not.toHaveBeenCalled();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.cancelPrepared).toHaveBeenCalledWith(
    '1',
    9,
    71,
    expect.any(Object)
  );
  expect(mocks.create).not.toHaveBeenCalled();
  expect(wrapper.emitted('registered')).toEqual([['canceled']]);
  wrapper.unmount();
});

it('refuses local cancellation of an already claimed intent and reports the backend conflict', async () => {
  mocks.cancelPrepared.mockRejectedValue({
    response: { status: 409, data: { code: 'DELIVERY_ALREADY_DISPATCHED' } },
  });
  const wrapper = render({ delivery: { id: 71, state: 'prepared' } });
  await flushPromises();
  await wrapper.find('input').setValue(true);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).toContain('O processamento já começou');
  expect(wrapper.emitted('registered')).toBeUndefined();
  expect(wrapper.find('input').element.checked).toBe(false);
  wrapper.unmount();
});
