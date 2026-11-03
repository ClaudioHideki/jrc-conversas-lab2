import { computed, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Picker from './SegmentFilterPicker.vue';
const mocks = vi.hoisted(() => ({
  state: null,
  taxonomy: vi.fn(),
  taxonomies: vi.fn(),
}));
vi.mock('dashboard/api/jrcCustomers', () => ({ default: mocks }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountId: computed(() => mocks.state.account),
    identity: computed(() => `${mocks.state.account}:${mocks.state.viewer}`),
  }),
}));
const item = {
  id: 7,
  name: 'MOCK — Filtro dinâmico',
  selection_mode: 'dynamic',
};
const response = (record = item) => ({
  data: { payload: [record], meta: { page: 1, per_page: 10, total: 11 } },
});
const render = props => mount(Picker, { props });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.state = reactive({ account: 1, viewer: 1 });
  mocks.taxonomy.mockResolvedValue({ data: { payload: item } });
  mocks.taxonomies.mockResolvedValue(response());
});

it('shows the URL-selected definition by its canonical ID even when it is not on the first result page', async () => {
  const wrapper = render({ modelValue: 7 });
  await flushPromises();
  expect(wrapper.text()).toContain(item.name);
  expect(mocks.taxonomy).toHaveBeenCalledWith(
    7,
    expect.objectContaining({ accountId: 1, signal: expect.any(AbortSignal) })
  );
  expect(mocks.taxonomies).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('searches active definitions with bounded server paging and emits the selected ID without mutating a company', async () => {
  const wrapper = render();
  await wrapper.find('input').trigger('focus');
  await flushPromises();
  expect(mocks.taxonomies).toHaveBeenCalledWith(
    { kind: 'segment', active: true, q: '', page: 1, per_page: 10 },
    expect.objectContaining({ accountId: 1 })
  );
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Próxima')
    .trigger('click');
  await flushPromises();
  expect(mocks.taxonomies).toHaveBeenLastCalledWith(
    expect.objectContaining({ page: 2 }),
    expect.objectContaining({ accountId: 1 })
  );
  await wrapper
    .findAll('button')
    .find(button => button.text().includes(item.name))
    .trigger('click');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([7]);
  wrapper.unmount();
});

it('makes a stale or unavailable URL filter removable without reusing its old name', async () => {
  mocks.taxonomy.mockRejectedValue({
    response: { status: 404, data: { error: 'MOCK — Indisponível' } },
  });
  const wrapper = render({ modelValue: 7 });
  await flushPromises();
  expect(wrapper.text()).not.toContain(item.name);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Limpar filtro de segmento')
    .trigger('click');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual(['']);
  wrapper.unmount();
});

it('discards an in-flight selected definition when the account or access identity changes', async () => {
  let finish;
  mocks.taxonomy.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render({ modelValue: 7 });
  await flushPromises();
  mocks.taxonomy.mockResolvedValue({
    data: { payload: { id: 66, name: 'MOCK — Nova conta' } },
  });
  mocks.state.account = 2;
  await wrapper.setProps({ modelValue: 66 });
  await flushPromises();
  finish({
    data: { payload: { id: 7, name: 'MOCK — Conta anterior proibida' } },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Conta anterior proibida');
  expect(wrapper.text()).toContain('Nova conta');
  expect(mocks.taxonomy).toHaveBeenLastCalledWith(
    66,
    expect.objectContaining({ accountId: 2 })
  );
  wrapper.unmount();
});

it('clears old search choices and ignores a late response after the viewer changes', async () => {
  let finish;
  mocks.taxonomies.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await wrapper.find('input').trigger('focus');
  await flushPromises();
  mocks.state.viewer = 2;
  await flushPromises();
  finish(response({ id: 8, name: 'MOCK — Resultado anterior proibido' }));
  await flushPromises();
  expect(wrapper.text()).not.toContain('Resultado anterior proibido');
  wrapper.unmount();
});

it('requests the module catalog and rejects an inactive or unpublished URL-selected definition', async () => {
  const wrapper = render({ modelValue: 7, moduleKey: 'crm' });
  await flushPromises();
  expect(wrapper.text()).not.toContain(item.name);
  expect(wrapper.get('[role="alert"]').text()).toContain('não está publicado');
  await wrapper.find('input').trigger('focus');
  await flushPromises();
  expect(mocks.taxonomies).toHaveBeenLastCalledWith(
    expect.objectContaining({ module_key: 'crm', active: true, per_page: 10 }),
    expect.objectContaining({ accountId: 1 })
  );
  wrapper.unmount();
});
