import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import CoordinatedAutomationStudio from './CoordinatedAutomationStudio.vue';
import { blankComposition, clone } from './compositionForm';
const mocks = vi.hoisted(() => ({
  session: { state: null },
  api: {
    list: vi.fn(),
    options: vi.fn(),
    read: vi.fn(),
    preview: vi.fn(),
    publish: vi.fn(),
  },
  drafts: { read: vi.fn(), save: vi.fn() },
}));
vi.mock('dashboard/api/serviceDeskAutomationPublications', () => ({
  default: mocks.api,
}));
vi.mock('dashboard/api/serviceDeskAutomationDrafts', () => ({
  default: mocks.drafts,
}));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
let wrapper;
const fixture = () => {
  const attributes = blankComposition('operational');
  Object.assign(attributes, {
    code: 'synthetic-policy',
    name: 'Synthetic test policy',
  });
  const row = attributes.definition.families.routing.rules[0];
  row.match.priority_id = 1;
  delete row.conditions;
  row.precedence = 7;
  row.output.queue_id = 3;
  return {
    attributes,
    version: 0,
    calendar: { timezone: '', conditions: {} },
    calendarCode: '',
    calendarVersion: '',
  };
};
const byText = text =>
  wrapper.findAll('button').find(button => button.text().endsWith(text));
async function openDraft() {
  await byText('Nova política').trigger('click');
  await flushPromises();
  await wrapper.get('input[maxlength="64"]').setValue('synthetic-policy');
  await byText('Recuperar rascunho').trigger('click');
  await flushPromises();
  await byText('Revisão e publicação').trigger('click');
  await flushPromises();
}
beforeEach(() => {
  mocks.session.state = reactive({
    status: 'ready',
    context: {
      account_id: '11',
      units: [
        {
          id: '21',
          name: 'Synthetic unit',
          operator_company: { id: '31', name: 'Synthetic operator' },
        },
      ],
      capabilities: { operational_rules: { routing: true } },
    },
  });
  mocks.api.list.mockResolvedValue({
    items: [],
    total: 0,
    counts: { total: 0, enabled: 0, disabled: 0 },
  });
  mocks.api.options.mockResolvedValue({ labels: [], inboxes: [] });
  mocks.api.preview.mockResolvedValue({
    valid: true,
    native_versions: {
      families: { routing: 0 },
      queues: {},
      notifications: {},
    },
    simulation: { routing: null },
    sla_deadlines: [],
  });
  mocks.drafts.read.mockResolvedValue({ lock_version: 2, payload: fixture() });
  wrapper = mount(CoordinatedAutomationStudio, {
    props: { kind: 'operational', initialUnitId: '21' },
    attachTo: document.body,
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        teleport: true,
        ScopeBar: true,
        LookupSelect: true,
        ServiceDefinitionSelect: true,
        OperationalRulePanel: true,
        LifecyclePolicyEditor: true,
      },
    },
  });
});
afterEach(() => {
  wrapper.unmount();
});

it('blocks publication until the server validates the exact draft and the user confirms', async () => {
  await flushPromises();
  await openDraft();
  expect(byText('Publicar versão').attributes('disabled')).toBeDefined();
  await byText('Validar configuração e simular').trigger('click');
  await flushPromises();
  expect(mocks.api.preview).toHaveBeenCalledTimes(1);
  expect(mocks.api.publish).not.toHaveBeenCalled();
  const confirmation = wrapper
    .findAll('label')
    .find(row => row.text().includes('Confirmo a publicação'));
  await confirmation.get('input').setValue(true);
  expect(byText('Publicar versão').attributes('disabled')).toBeUndefined();
});

it('invalidates validation when activation changes, without activating or sending anything', async () => {
  await flushPromises();
  await openDraft();
  await byText('Validar configuração e simular').trigger('click');
  await flushPromises();
  const activation = wrapper
    .findAll('label')
    .find(row => row.text().includes('Habilitar explicitamente'));
  await activation.get('input').setValue(true);
  await flushPromises();
  expect(byText('Publicar versão').attributes('disabled')).toBeDefined();
  expect(mocks.api.publish).not.toHaveBeenCalled();
});

it('reads back an exact publication before reporting success', async () => {
  await flushPromises();
  await openDraft();
  await byText('Validar configuração e simular').trigger('click');
  await flushPromises();
  await wrapper
    .findAll('label')
    .find(row => row.text().includes('Confirmo a publicação'))
    .get('input')
    .setValue(true);
  const saved = {
    ...clone(mocks.api.preview.mock.calls[0][2]),
    id: '61',
    version: 1,
    digest: 'a'.repeat(64),
  };
  mocks.api.publish.mockResolvedValue({ publication: saved, audit_id: '71' });
  mocks.api.read.mockResolvedValue(saved);
  await byText('Publicar versão').trigger('click');
  await flushPromises();
  expect(mocks.api.read).toHaveBeenCalledWith(
    '11',
    '21',
    '61',
    expect.any(AbortSignal)
  );
  expect(wrapper.text()).toContain(
    'Publicação concluída e relida do servidor.'
  );
  expect(mocks.api.publish.mock.calls[0][2].attributes.enabled).toBe(false);
});

it('does not claim success after a readback mismatch and retries with the same idempotency key', async () => {
  await flushPromises();
  await openDraft();
  await byText('Validar configuração e simular').trigger('click');
  await flushPromises();
  await wrapper
    .findAll('label')
    .find(row => row.text().includes('Confirmo a publicação'))
    .get('input')
    .setValue(true);
  const saved = {
    ...clone(mocks.api.preview.mock.calls[0][2]),
    id: '61',
    version: 1,
    digest: 'a'.repeat(64),
  };
  mocks.api.publish.mockResolvedValue({ publication: saved });
  mocks.api.read.mockResolvedValue({ ...saved, enabled: true });
  await byText('Publicar versão').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(
    'A resposta da publicação não pôde ser confirmada.'
  );
  const first = clone(mocks.api.publish.mock.calls[0][2]);
  await byText('Repetir mesmo comando').trigger('click');
  await flushPromises();
  expect(mocks.api.publish.mock.calls[1][2]).toEqual(first);
});

it('closes the editor and discards loaded records on an Account context change', async () => {
  await flushPromises();
  await openDraft();
  mocks.session.state.context = {
    ...mocks.session.state.context,
    account_id: '12',
    units: [],
  };
  await flushPromises();
  expect(wrapper.find('dialog main').exists()).toBe(false);
  expect(mocks.api.publish).not.toHaveBeenCalled();
});

it('preserves a newer published version when a private draft belongs to an older version and saves only after an explicit action', async () => {
  await flushPromises();
  const row = {
    ...fixture().attributes,
    id: '61',
    version: 3,
    name: 'Published version three',
    digest: 'a'.repeat(64),
  };
  mocks.api.list.mockResolvedValue({
    items: [row],
    total: 1,
    counts: { total: 1, enabled: 0, disabled: 1 },
  });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  await byText('Editar').trigger('click');
  await flushPromises();
  expect(wrapper.get('input[maxlength="255"]').element.value).toBe(
    'Published version three'
  );
  expect(mocks.drafts.save).not.toHaveBeenCalled();
  await byText('Recuperar rascunho').trigger('click');
  await flushPromises();
  expect(wrapper.get('input[maxlength="255"]').element.value).toBe(
    'Published version three'
  );
  expect(wrapper.text()).toContain('Rascunho de uma versão anterior');
  mocks.drafts.save.mockResolvedValue({ lock_version: 3 });
  mocks.drafts.read.mockImplementation(async () => ({
    lock_version: 3,
    payload: mocks.drafts.save.mock.calls.at(-1)[4],
  }));
  await byText('Salvar rascunho').trigger('click');
  await flushPromises();
  expect(mocks.drafts.save).toHaveBeenCalledWith(
    '11',
    '21',
    'operational',
    'synthetic-policy',
    expect.objectContaining({ version: 3 }),
    2
  );
  expect(wrapper.text()).toContain('Rascunho salvo no servidor e relido');
  expect(mocks.api.publish).not.toHaveBeenCalled();
});
