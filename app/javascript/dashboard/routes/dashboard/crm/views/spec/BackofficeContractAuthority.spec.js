import { defineComponent, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import Panel from '../backoffice/BackofficeContractAuthority.vue';
import Editor from '../backoffice/AuthorityProposalEditor.vue';
import Picker from '../backoffice/AuthorityDocumentPicker.vue';
import Origin from '../../../approvals/AuthorityOrigin.vue';
import NativeDialog from 'dashboard/components-next/dialog/Dialog.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  api: { list: vi.fn(), create: vi.fn(), show: vi.fn(), documents: vi.fn() },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('dashboard/api/crm/backofficeAuthorities', () => ({
  default: mocks.api,
}));
const DialogStub = defineComponent({
  setup(_, { expose }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
    });
    return { visible };
  },
  template: '<div v-if="visible"><slot /></div>',
});
const people = [
  {
    key: 'customer-key',
    name: 'CLIENTE SINTÉTICO',
    party: 'customer',
    email: 'customer@example.test',
    personal_tax_identifier_masked: '***.***.***-35',
  },
  {
    key: 'issuer-key',
    name: 'EMITENTE SINTÉTICO',
    party: 'issuer',
    email: 'issuer@example.test',
    personal_tax_identifier_masked: '***.***.***-25',
  },
];
const overview = {
  version: { id: 3, number: 2, source_digest: 'b'.repeat(64) },
  signers: {
    id: 7,
    signers: people,
    customer_mode: 'single',
    issuer_mode: 'single',
  },
  current: null,
  data: [],
  can_propose: true,
  approvals_enabled: true,
  meta: { page: 1, pages: 1, per_page: 10, total: 0 },
};
const proof = key => ({
  signer_key: key,
  basis: 'legal_representative',
  reason: 'TESTE SINTÉTICO — Ato de representação.',
  document_version_ids: [10],
  valid_from: '2026-11-01',
  valid_until: '2026-12-31',
  no_expiry: false,
});
const caseData = {
  proposal: {
    id: 4,
    revision: 1,
    proofs: people.map(person => proof(person.key)),
    change_reason: 'TESTE SINTÉTICO — Revisão.',
  },
  version: overview.version,
  signers: overview.signers,
  context: {
    customer: { name: 'EMPRESA SINTÉTICA' },
    financials: { total_cents: 1234 },
  },
  status: {
    status: 'blocked',
    facts: { people_current: true },
    requests: [{ id: 41, state: 'pending' }],
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUser: { id: 8, accounts: [] },
    getCurrentRole: 'agent',
  });
  mocks.api.list.mockResolvedValue({ data: structuredClone(overview) });
  mocks.api.create.mockResolvedValue({ data: structuredClone(caseData) });
  mocks.api.show.mockResolvedValue({ data: structuredClone(caseData) });
  mocks.api.documents.mockResolvedValue({
    data: {
      selected_key: 'powers',
      requirements: [{ key: 'powers', label: 'Procuração SINTÉTICA' }],
      data: [
        {
          id: 10,
          filename: 'SINTETICO.pdf',
          version: 1,
          current: true,
          status: 'approved',
          safety: { state: 'clean' },
          analysis: { state: 'review_required' },
        },
      ],
      meta: { page: 1, pages: 1, total: 1 },
    },
  });
});
const button = (wrapper, label) =>
  wrapper.findAll('button').find(row => row.text() === label);
const editor = () =>
  mount(Editor, {
    props: {
      accountId: '1',
      requestId: 9,
      overview: structuredClone(overview),
    },
    global: { stubs: { Dialog: DialogStub } },
  });
const fillPerson = async (wrapper, name) => {
  await button(wrapper, name).trigger('click');
  await flushPromises();
  await wrapper.find('select').setValue('legal_representative');
  await wrapper.findAll('input[type="date"]')[0].setValue('2026-11-01');
  await wrapper.findAll('input[type="date"]')[1].setValue('2026-12-31');
  await wrapper
    .findAll('textarea')[0]
    .setValue('TESTE SINTÉTICO — Ato de representação.');
  await button(wrapper, 'Selecionar').trigger('click');
};
const fillAll = async wrapper => {
  await flushPromises();
  await fillPerson(wrapper, people[0].name);
  await fillPerson(wrapper, people[1].name);
  await wrapper.findAll('textarea')[1].setValue('TESTE SINTÉTICO — Revisão.');
};

it('requires evidence for all required people and submits the exact version without a powers flag', async () => {
  const wrapper = editor();
  await flushPromises();
  await fillPerson(wrapper, people[0].name);
  await wrapper.findAll('textarea')[1].setValue('TESTE SINTÉTICO — Revisão.');
  expect(wrapper.find('button[type="submit"]').element.disabled).toBe(true);
  await wrapper.find('form').trigger('submit');
  expect(mocks.api.create).not.toHaveBeenCalled();
  await fillPerson(wrapper, people[1].name);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  const payload = mocks.api.create.mock.calls[0][2];
  expect(payload).toMatchObject({
    version_id: 3,
    expected_revision: 0,
    expected_source_digest: 'b'.repeat(64),
    proofs: people.map(person => proof(person.key)),
  });
  expect(payload).not.toHaveProperty('powers_verified');
  expect(payload).not.toHaveProperty('account_id');
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('preserves the intent across an uncertain response and never shows success without acknowledgment', async () => {
  mocks.api.create.mockRejectedValueOnce(
    new Error('Synthetic transport interruption')
  );
  const wrapper = editor();
  await fillAll(wrapper);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.create.mock.calls[0][2].idempotency_key).toBe(
    mocks.api.create.mock.calls[1][2].idempotency_key
  );
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('freezes a changed version and explains a missing native policy without approving anything', async () => {
  mocks.api.create.mockRejectedValueOnce({
    response: { status: 409, data: { code: 'POLICY_REQUIRED' } },
  });
  const wrapper = editor();
  await fillAll(wrapper);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).toContain('Configure e ative uma regra');
  expect(wrapper.find('button[type="submit"]').element.disabled).toBe(false);
  mocks.api.create.mockRejectedValueOnce({
    response: { status: 409, data: { code: 'AUTHORITY_CONTEXT_CHANGED' } },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('fieldset').element.disabled).toBe(true);
  expect(wrapper.find('button[type="submit"]').element.disabled).toBe(true);
  expect(wrapper.emitted('saved')).toBeUndefined();
  wrapper.unmount();
});

it('keeps absence of expiry as an explicit declaration and clears sensitive fields on access denial', async () => {
  const wrapper = editor();
  await fillAll(wrapper);
  await wrapper.find('input[type="checkbox"]').setValue(true);
  mocks.api.create.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.create.mock.calls[0][2].proofs[1]).toMatchObject({
    no_expiry: true,
    valid_until: null,
  });
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.text()).not.toContain(people[0].name);
  expect(
    wrapper.findAll('textarea').every(row => row.element.value === '')
  ).toBe(true);
  wrapper.unmount();
});

it('never offers quarantined, unreviewed or replaced evidence as an eligible choice', async () => {
  const rows = ['unavailable', 'clean', 'clean'].map((state, index) => ({
    id: index + 20,
    filename: `SINTETICO-${index}.pdf`,
    version: 1,
    current: index !== 2,
    status: index === 1 ? 'review_required' : 'approved',
    safety: { state },
    analysis: {},
  }));
  mocks.api.documents.mockResolvedValueOnce({
    data: { data: rows, requirements: [], meta: { page: 1, pages: 1 } },
  });
  const wrapper = mount(Picker, {
    props: { accountId: 1, requestId: 9, selected: [] },
  });
  await flushPromises();
  expect(
    wrapper
      .findAll('button')
      .filter(row => row.text() === 'Selecionar')
      .every(row => row.element.disabled)
  ).toBe(true);
  expect(wrapper.emitted('choose')).toBeUndefined();
  wrapper.unmount();
});

it('clears the panel on account changes and ignores late responses from the previous account', async () => {
  let resolve;
  mocks.api.list.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mount(Panel, {
    props: { record: { id: 9, contract: { id: 2 } } },
    global: { stubs: { AuthorityCaseView: true } },
  });
  await flushPromises();
  mocks.api.list.mockRejectedValueOnce({ response: { status: 403 } });
  mocks.route.params.accountId = '2';
  await flushPromises();
  resolve({ data: { ...overview, current: caseData } });
  await flushPromises();
  expect(wrapper.text()).toContain('Acesso negado');
  expect(wrapper.findComponent({ name: 'AuthorityCaseView' }).exists()).toBe(
    false
  );
  expect(mocks.api.list.mock.calls[1].slice(0, 2)).toEqual(['2', 9]);
  wrapper.unmount();
});

it('shows the native current case after reload and never enables proposing without a version or permission', async () => {
  mocks.api.list.mockResolvedValue({
    data: {
      ...overview,
      can_propose: false,
      current: caseData,
      data: [caseData.proposal],
    },
  });
  const wrapper = mount(Panel, {
    props: { record: { id: 9 } },
    global: { stubs: { AuthorityCaseView: true } },
  });
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'AuthorityCaseView' }).props('data').proposal
      .id
  ).toBe(4);
  expect(button(wrapper, 'Propor validação de poderes').element.disabled).toBe(
    true
  );
  expect(wrapper.text()).toContain('Para propor, gere uma versão');
  wrapper.unmount();
});

it('opens the bounded legal origin for the native reviewer and drops it immediately after a role change', async () => {
  const wrapper = mount(Origin, {
    props: {
      request: { id: 41, resource_id: 4, origin: { backoffice_request_id: 9 } },
    },
    global: { stubs: { AuthorityCaseView: true } },
  });
  await flushPromises();
  expect(mocks.api.show.mock.calls[0].slice(0, 3)).toEqual(['1', 9, 4]);
  expect(wrapper.findComponent({ name: 'AuthorityCaseView' }).exists()).toBe(
    true
  );
  mocks.api.show.mockRejectedValueOnce({ response: { status: 403 } });
  mocks.getters.getCurrentRole = 'restricted';
  await flushPromises();
  expect(wrapper.findComponent({ name: 'AuthorityCaseView' }).exists()).toBe(
    false
  );
  expect(wrapper.text()).toContain('Acesso negado');
  wrapper.unmount();
});

it('uses the real native bounded dialog with one form and a scrollable body', async () => {
  const showModal = HTMLDialogElement.prototype.showModal;
  const close = HTMLDialogElement.prototype.close;
  HTMLDialogElement.prototype.showModal = function open() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function hide() {
    this.removeAttribute('open');
  };
  let wrapper;
  try {
    wrapper = mount(Editor, {
      props: {
        accountId: '1',
        requestId: 9,
        overview: structuredClone(overview),
      },
      global: {
        stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
      },
    });
    await flushPromises();
    expect(wrapper.findComponent(NativeDialog).props()).toMatchObject({
      useForm: false,
      contained: true,
      showCloseButton: true,
    });
    expect(wrapper.findAll('form')).toHaveLength(1);
    expect(wrapper.find('.overflow-y-auto').exists()).toBe(true);
  } finally {
    wrapper?.unmount();
    HTMLDialogElement.prototype.showModal = showModal;
    HTMLDialogElement.prototype.close = close;
  }
});
