import { computed, reactive, onMounted } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import SegmentDialog from './SegmentDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  metadata: vi.fn(),
  taxonomy: vi.fn(),
  saveTaxonomy: vi.fn(),
  deleteTaxonomy: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.admin}`),
    canAdmin: computed(() => mocks.state.admin),
  }),
}));
const definition = {
  id: 7,
  kind: 'segment',
  name: 'MOCK — Salvo',
  description: '',
  active: true,
  position: 0,
  selection_mode: 'classification',
  criteria: { match: 'all', rules: [] },
  modules: [],
  revision: '2026-11-03T10:00:00.000000Z',
};
const render = (props, preview = true) =>
  mount(SegmentDialog, {
    props,
    global: {
      stubs: {
        Dialog: {
          setup: (_, { expose }) => {
            expose({ open: vi.fn(), close: vi.fn() });
          },
          template: '<section><slot /></section>',
        },
        SegmentResults: {
          name: 'SegmentResults',
          props: ['editable'],
          emits: ['preview'],
          setup: (_, { emit }) => {
            onMounted(() => {
              if (preview) emit('preview', { companies: 0, contacts: 0 });
            });
          },
          template: '<span>MOCK — Prévia</span>',
        },
        SegmentHistory: true,
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, admin: true });
  mocks.metadata.mockResolvedValue({ data: {} });
  mocks.taxonomy.mockResolvedValue({ data: { payload: definition } });
  mocks.saveTaxonomy.mockResolvedValue({ data: { payload: definition } });
});
it('requires four steps and a final save instead of persisting from the navigation buttons', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.find('input[maxlength="120"]').setValue('MOCK — Novo');
  const next = () =>
    wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
  await next();
  await next();
  await next();
  expect(wrapper.text()).toContain('Revisão');
  expect(mocks.saveTaxonomy).not.toHaveBeenCalled();
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(mocks.saveTaxonomy).toHaveBeenCalledWith(
    expect.objectContaining({ name: 'MOCK — Novo', manual_choices: [] }),
    null,
    { accountId: 1 }
  );
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});
it('retains entered data and server revision when validation rejects an edit', async () => {
  mocks.saveTaxonomy.mockRejectedValue({
    response: { data: { error: 'MOCK — Recarregue antes de salvar' } },
  });
  const wrapper = render({ taxonomyId: 7 });
  await flushPromises();
  await wrapper.find('textarea').setValue('MOCK — Preservar rascunho');
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('textarea').element.value).toBe(
    'MOCK — Preservar rascunho'
  );
  expect(mocks.saveTaxonomy).toHaveBeenCalledWith(
    expect.objectContaining({ revision: definition.revision }),
    7,
    { accountId: 1 }
  );
  expect(wrapper.emitted('saved')).toBeUndefined();
  wrapper.unmount();
});

it('requires a current server preview before confirming creation from the review step', async () => {
  const wrapper = render({}, false);
  await flushPromises();
  await wrapper
    .find('input[maxlength="120"]')
    .setValue('MOCK — Aguardar prévia');
  const next = () =>
    wrapper
      .findAll('button')
      .find(button => button.text() === 'Próxima')
      .trigger('click');
  await next();
  await next();
  await next();
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  wrapper
    .findComponent({ name: 'SegmentResults' })
    .vm.$emit('preview', { companies: 2, contacts: 3 });
  await flushPromises();
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeUndefined();
  wrapper.unmount();
});
it('provides the six existing-record tabs without granting edits to ordinary readers', async () => {
  mocks.state.admin = false;
  const wrapper = render({ taxonomyId: 7 });
  await flushPromises();
  expect(wrapper.findAll('nav button')).toHaveLength(6);
  expect(wrapper.find('fieldset').attributes('disabled')).toBeDefined();
  expect(wrapper.find('button[type="submit"]').exists()).toBe(false);
  mocks.state.account = 2;
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('submits the real native confirmation form and keeps the segment intact when deletion is blocked', async () => {
  const originalShow = HTMLDialogElement.prototype.showModal;
  const originalClose = HTMLDialogElement.prototype.close;
  let wrapper;
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
  mocks.deleteTaxonomy.mockRejectedValue({
    response: {
      status: 422,
      data: { error: 'MOCK — Dependências preservadas' },
    },
  });
  try {
    wrapper = mount(SegmentDialog, {
      props: { taxonomyId: 7 },
      attachTo: document.body,
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          SegmentResults: true,
          SegmentHistory: true,
        },
      },
    });
    await flushPromises();
    const main = wrapper.findComponent(Dialog);
    await main
      .find('footer')
      .findAll('button')
      .find(button => button.text() === 'Excluir segmento')
      .trigger('click');
    const open = document.querySelectorAll('dialog[open]');
    expect(open).toHaveLength(2);
    const alert = open[1];
    expect(alert.querySelector('form')).not.toBeNull();
    alert.querySelector('button[type="submit"]').click();
    await flushPromises();
    expect(mocks.deleteTaxonomy).toHaveBeenCalledWith(7, { accountId: 1 });
    expect(main.find('dialog').element.open).toBe(true);
    expect(wrapper.text()).toContain('MOCK — Dependências preservadas');
    expect(wrapper.emitted('saved')).toBeUndefined();
  } finally {
    wrapper?.unmount();
    HTMLDialogElement.prototype.showModal = originalShow;
    HTMLDialogElement.prototype.close = originalClose;
  }
});
