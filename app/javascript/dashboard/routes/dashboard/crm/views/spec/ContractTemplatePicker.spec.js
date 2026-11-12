import { flushPromises, mount } from '@vue/test-utils';
import Picker from '../backoffice/ContractTemplatePicker.vue';

const api = vi.hoisted(() => ({ templates: vi.fn() }));
vi.mock('dashboard/api/crm/commercialCycle', () => ({
  backofficeContractVersionsAPI: api,
}));
const result = {
  data: [
    { id: 82, name: 'TESTE SINTÉTICO — Modelo elegível', category: 'Jurídico' },
  ],
  meta: { page: 1, pages: 2, total: 11 },
};
const button = (wrapper, label) =>
  wrapper.findAll('button').find(item => item.text() === label);
const render = () => mount(Picker, { props: { accountId: '1', requestId: 9 } });
beforeEach(() => {
  api.templates.mockResolvedValue({ data: structuredClone(result) });
});

it('uses explicit account/request and bounded server pages and emits only the chosen native reference', async () => {
  const wrapper = render();
  await flushPromises();
  expect(api.templates).toHaveBeenCalledWith(
    '1',
    9,
    { q: '', page: 1 },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  await wrapper.get('input').setValue('Modelo elegível');
  await button(wrapper, 'Buscar').trigger('click');
  await flushPromises();
  expect(api.templates.mock.calls.at(-1)[2]).toEqual({
    q: 'Modelo elegível',
    page: 1,
  });
  await button(wrapper, 'Próxima').trigger('click');
  await flushPromises();
  expect(api.templates.mock.calls.at(-1)[2].page).toBe(2);
  await button(wrapper, 'Selecionar').trigger('click');
  expect(wrapper.emitted('choose')).toEqual([[result.data[0]]]);
  wrapper.unmount();
});

it('discards a late response from a different account and reports denied access without showing the old model', async () => {
  let release;
  api.templates.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        release = resolve;
      })
  );
  const wrapper = render();
  api.templates.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.setProps({ accountId: '2', requestId: 10 });
  await flushPromises();
  release({ data: result });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Modelo elegível');
  expect(wrapper.emitted('denied')).toHaveLength(1);
  expect(api.templates.mock.calls.at(-1).slice(0, 3)).toEqual([
    '2',
    10,
    { q: '', page: 1 },
  ]);
  wrapper.unmount();
});

it('shows a real empty/error state and never invents a successful choice', async () => {
  api.templates.mockRejectedValueOnce(new Error('Network timeout'));
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Não foi possível consultar os modelos');
  expect(wrapper.emitted('choose')).toBeUndefined();
  api.templates.mockResolvedValueOnce({
    data: { data: [], meta: { page: 1, pages: 1, total: 0 } },
  });
  await button(wrapper, 'Atualizar').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Nenhum modelo ativo atende aos critérios');
  expect(wrapper.emitted('choose')).toBeUndefined();
  wrapper.unmount();
});
