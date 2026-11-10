import { computed, reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import ImportsPage from './ImportsPage.vue';

const mocks = vi.hoisted(() => ({
  state: null,
  importMetadata: vi.fn(),
  importRun: vi.fn(),
  previewImport: vi.fn(),
  applyImport: vi.fn(),
  importRecords: vi.fn(),
  importRuns: vi.fn(),
  uploadImport: vi.fn(),
  importTemplate: vi.fn(),
  importErrorsFile: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('./components/CompanyDetailsDialog.vue', () => ({
  default: {
    name: 'CompanyDetailsDialog',
    template: '<div>MOCK company popup</div>',
  },
}));
vi.mock('./components/ContactDetailsDialog.vue', () => ({
  default: {
    name: 'ContactDetailsDialog',
    template: '<div>MOCK contact popup</div>',
  },
}));
vi.mock('./useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.role}`),
    date: value => value,
  }),
}));
const draft = {
  data: {
    payload: {
      id: 17,
      filename: 'MOCK.csv',
      kind: 'contacts',
      status: 'pending',
      can_review: true,
    },
    file: {
      headers: ['Nome', 'Email'],
      fields: ['contact.name', 'contact.email'],
      row_count: 1,
    },
    column_mapping: { Nome: 'contact.name', Email: 'contact.email' },
    import_options: { existing: 'skip', confirmations: {} },
  },
};
const DialogStub = {
  props: ['confirmButtonLabel', 'isLoading'],
  emits: ['confirm', 'close'],
  setup(_props, { expose }) {
    const open = ref(false);
    expose({
      open: () => {
        open.value = true;
      },
      close: () => {
        open.value = false;
      },
    });
    return { open, cancelLabel: 'MOCK Cancel' };
  },
  template:
    '<section v-if="open" data-testid="mock-confirm-dialog"><button :disabled="isLoading" @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button><button @click="$emit(\'close\'); open = false">{{ cancelLabel }}</button></section>',
};
const render = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/imports', component: { template: '<div />' } }],
  });
  await router.push('/imports?import_id=17');
  const wrapper = mount(ImportsPage, {
    global: {
      plugins: [router],
      stubs: {
        Dialog: DialogStub,
        CompanyDetailsDialog: true,
        ContactDetailsDialog: true,
      },
    },
  });
  await flushPromises();
  return { wrapper, router };
};
const click = (wrapper, label) => {
  const buttons = wrapper.findAll('button');
  const match = buttons.find(button => button.text() === label);
  if (!match)
    throw new Error(
      `Missing ${label}; buttons: ${buttons.map(button => button.text()).join(' | ')}`
    );
  return match.trigger('click');
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.state = reactive({ account: 1, role: 'administrator' });
  mocks.importMetadata.mockResolvedValue({
    data: { available_kinds: ['companies', 'contacts', 'both'], max_rows: 500 },
  });
  mocks.importRun.mockResolvedValue(draft);
  mocks.previewImport.mockResolvedValue({
    data: {
      payload: {
        ...draft.data.payload,
        stats: { total_rows: 1, valid_rows: 1, contact_create: 1 },
      },
      rows: [
        {
          line: 2,
          entity: 'contact',
          action: 'create',
          attributes: { name: 'MOCK Person' },
          warnings: [],
        },
      ],
      errors: [],
      token: 'MOCK_TOKEN',
    },
  });
  mocks.applyImport.mockResolvedValue({
    data: {
      payload: {
        ...draft.data.payload,
        status: 'completed',
        can_review: false,
        stats: { applied_entities: 1 },
      },
    },
  });
  mocks.importRecords.mockResolvedValue({
    data: {
      payload: [
        {
          id: 9,
          line: 2,
          entity: 'contact',
          action: 'create',
          record_id: 41,
          name: 'MOCK Persisted',
        },
      ],
      meta: { page: 1, per_page: 25, total: 1 },
    },
  });
  mocks.importRuns.mockResolvedValue({
    data: { payload: [], meta: { page: 1, per_page: 20, total: 0 } },
  });
});

it('makes mapping editable, previews without writing, and requires the final popup before showing the server result', async () => {
  const { wrapper } = await render();
  expect(
    wrapper
      .findAll('select')
      .slice(0, 2)
      .map(select => select.element.value)
  ).toEqual(['contact.name', 'contact.email']);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.applyImport).not.toHaveBeenCalled();
  await click(wrapper, 'Contatos');
  expect(wrapper.text()).toContain('MOCK Person');
  await click(wrapper, 'Aplicar importação');
  expect(wrapper.find('[data-testid="mock-confirm-dialog"]').exists()).toBe(
    true
  );
  expect(mocks.applyImport).not.toHaveBeenCalled();
  await click(wrapper, 'Confirmar gravação');
  await flushPromises();
  expect(wrapper.text()).toContain('Importação concluída');
  expect(wrapper.text()).toContain('MOCK Persisted');
  await click(wrapper, 'MOCK Persisted');
  expect(wrapper.findComponent({ name: 'ContactDetailsDialog' }).exists()).toBe(
    true
  );
  wrapper.findComponent({ name: 'ContactDetailsDialog' }).vm.$emit('updated');
  await flushPromises();
  expect(mocks.importRecords).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});

it('keeps invalid rows visible and blocks confirmation while offering the real error export action', async () => {
  mocks.previewImport.mockResolvedValue({
    data: {
      payload: {
        ...draft.data.payload,
        stats: { total_rows: 1, invalid_rows: 1 },
      },
      rows: [],
      errors: [
        {
          line: 2,
          entity: 'contact',
          field: 'email',
          message: 'MOCK Invalid email',
        },
      ],
      token: null,
    },
  });
  const { wrapper } = await render();
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  await click(wrapper, 'Erros');
  expect(wrapper.text()).toContain('MOCK Invalid email');
  expect(
    wrapper
      .findAll('button')
      .find(button => button.text() === 'Aplicar importação')
      .attributes('disabled')
  ).toBeDefined();
  expect(
    wrapper
      .findAll('button')
      .find(button => button.text() === 'Baixar relatório de erros')
  ).toBeDefined();
  await click(wrapper, 'Revisar mapeamento');
  expect(wrapper.findAll('select').length).toBe(3);
  expect(mocks.applyImport).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('reloads the currently selected run when it is opened from history and clears it on an account change', async () => {
  const { wrapper } = await render();
  mocks.importRuns.mockResolvedValue({
    data: {
      payload: [
        {
          ...draft.data.payload,
          initiated_by: { name: 'MOCK Actor' },
          total_records: 1,
        },
      ],
      meta: { page: 1, per_page: 20, total: 1 },
    },
  });
  await click(wrapper, 'Histórico');
  await flushPromises();
  expect(wrapper.text()).toContain('MOCK.csv');
  await click(wrapper, 'Retomar revisão');
  await flushPromises();
  expect(mocks.importRun).toHaveBeenCalledTimes(2);
  expect(wrapper.findAll('select').length).toBe(3);
  mocks.importMetadata.mockResolvedValue({ data: { available_kinds: [] } });
  mocks.state.account = 2;
  await flushPromises();
  expect(wrapper.text()).not.toContain('MOCK.csv');
  expect(wrapper.text()).toContain('Seu acesso atual não permite');
  wrapper.unmount();
});
