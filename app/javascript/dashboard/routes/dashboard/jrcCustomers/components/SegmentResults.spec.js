import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Results from './SegmentResults.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  segmentPreview: vi.fn(),
  segmentRecords: vi.fn(),
  segmentOverride: vi.fn(),
  removeSegmentOverride: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.viewer}`),
  }),
}));
const definition = {
  name: 'MOCK — Segmento',
  kind: 'segment',
  selection_mode: 'classification',
  criteria: { match: 'all', rules: [] },
};
const result = name => ({
  data: {
    payload: [{ id: 21, name }],
    meta: { page: 1, total: 11, per_page: 10 },
    counts: { companies: 11, contacts: 2 },
  },
});
const render = props =>
  mount(Results, {
    props: { definition, editable: true, ...props },
    global: { stubs: { CompanyPicker: true, ContactPicker: true } },
  });
const settle = async () => {
  await vi.advanceTimersByTimeAsync(300);
  await flushPromises();
};
beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, viewer: 1 });
  mocks.segmentPreview.mockResolvedValue(result('MOCK — Empresa acessível'));
  mocks.segmentRecords.mockResolvedValue({
    data: { payload: [], meta: { page: 1, total: 0, per_page: 10 } },
  });
  mocks.segmentOverride.mockResolvedValue({ data: {} });
});
afterEach(() => vi.useRealTimers());
it('previews without writing and requests the second bounded page for the same canonical segment', async () => {
  const wrapper = render({ taxonomyId: 7 });
  await settle();
  expect(wrapper.text()).toContain('11 empresas e 2 contatos');
  expect(mocks.segmentPreview).toHaveBeenCalledWith(
    expect.objectContaining({ name: definition.name }),
    expect.objectContaining({ taxonomy_id: 7, page: 1, per_page: 10 }),
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(mocks.segmentOverride).not.toHaveBeenCalled();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.segmentPreview).toHaveBeenLastCalledWith(
    expect.anything(),
    expect.objectContaining({ page: 2 }),
    expect.anything()
  );
  wrapper.unmount();
});

it('shows loading instead of a false empty result while a preview is being scheduled', async () => {
  const wrapper = render();
  expect(wrapper.text()).toContain('Carregando');
  expect(wrapper.text()).not.toContain('Nenhum registro encontrado');
  expect(wrapper.emitted('pending')).toHaveLength(1);
  await settle();
  expect(wrapper.emitted('preview')[0][0]).toEqual({
    companies: 11,
    contacts: 2,
  });
  wrapper.unmount();
});
it('retains unsaved manual choices in the wizard without prematurely creating database records', async () => {
  const wrapper = render();
  await settle();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Excluir da seleção')
    .trigger('click');
  expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
    {
      subject_kind: 'companies',
      subject_id: 21,
      mode: 'exclude',
      name: 'MOCK — Empresa acessível',
    },
  ]);
  expect(mocks.segmentOverride).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('persists an explicit choice on an existing segment and refreshes real server counts', async () => {
  const wrapper = render({ taxonomyId: 7 });
  await settle();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Excluir da seleção')
    .trigger('click');
  await flushPromises();
  expect(mocks.segmentOverride).toHaveBeenCalledWith(
    7,
    expect.objectContaining({
      subject_kind: 'companies',
      subject_id: 21,
      mode: 'exclude',
    }),
    { accountId: 1 }
  );
  expect(mocks.segmentPreview).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});
it('clears stale results during a role change and discards the old in-flight response', async () => {
  let finish;
  mocks.segmentPreview.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await settle();
  mocks.state.viewer = 2;
  await flushPromises();
  await settle();
  finish(result('MOCK — Resultado anterior proibido'));
  await flushPromises();
  expect(wrapper.text()).not.toContain('Resultado anterior proibido');
  expect(wrapper.text()).toContain('Empresa acessível');
  wrapper.unmount();
});
it('does not render mutation controls in read-only mode and reports access denial without stale rows', async () => {
  mocks.segmentPreview.mockRejectedValue({
    response: { status: 401, data: { error: 'MOCK — acesso negado' } },
  });
  const wrapper = render({ editable: false });
  await settle();
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(wrapper.findComponent({ name: 'CompanyPicker' }).exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Empresa acessível');
  wrapper.unmount();
});
