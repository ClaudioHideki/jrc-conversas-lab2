import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import EstablishmentPicker from '../EstablishmentPicker.vue';
import { request } from '../../../../../../portal/requester/client';

vi.mock('../../../../../../portal/requester/client', () => ({
  request: vi.fn(),
}));

const store = {
  id: '30',
  store_code: '030',
  name: 'Synthetic store',
  cnpj: '11222333000181',
  legal_name: 'Synthetic company',
  cluster: 'North',
};
const build = props =>
  mount(EstablishmentPicker, {
    props,
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          missingWarn: false,
          fallbackWarn: false,
          messages: { en: {} },
        }),
      ],
    },
  });

it('shows only authorized stores and preserves the selected store during a narrower search', async () => {
  request.mockResolvedValueOnce({ establishments: [store] });
  const wrapper = build({ serviceId: '12' });
  await flushPromises();
  await wrapper.get('select').setValue('30');
  await wrapper.setProps({ modelValue: '30' });
  expect(wrapper.text()).toContain('030');
  expect(wrapper.text()).toContain('Synthetic company');
  request.mockResolvedValueOnce({ establishments: [] });
  await wrapper.get('input').setValue('unmatched query');
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(request).toHaveBeenLastCalledWith(
    '/portal/api/catalogo/12/lojas?q=unmatched%20query'
  );
  expect(wrapper.get('select').element.value).toBe('30');
  wrapper.unmount();
});

it('discards a late result from the previous service and clears its selected store', async () => {
  let resolveOld;
  request.mockReturnValueOnce(
    new Promise(resolve => {
      resolveOld = resolve;
    })
  );
  const wrapper = build({ serviceId: '12', modelValue: '30' });
  request.mockResolvedValueOnce({ establishments: [] });
  await wrapper.setProps({ serviceId: '13', modelValue: null });
  await flushPromises();
  resolveOld({ establishments: [store] });
  await flushPromises();
  expect(wrapper.findAll('option')).toHaveLength(1);
  expect(wrapper.emitted('update:modelValue').flat()).toContain(null);
  wrapper.unmount();
});
