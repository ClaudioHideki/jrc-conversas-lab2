import { mount, flushPromises } from '@vue/test-utils';
import ImportPreview from './ImportPreview.vue';

it('identifies the reviewed company record when its references are not adjacent in the CSV', async () => {
  const wrapper = mount(ImportPreview, {
    props: {
      preview: {
        payload: { kind: 'both', stats: { total_rows: 3 } },
        token: 'MOCK_REVIEW',
        errors: [],
        rows: [
          {
            line: 2,
            entity: 'company',
            action: 'create',
            attributes: { name: 'MOCK First company' },
            warnings: [],
          },
          {
            line: 3,
            entity: 'company',
            action: 'create',
            attributes: { name: 'MOCK Other company' },
            warnings: [],
          },
          {
            line: 4,
            entity: 'company',
            action: 'reference',
            reference_line: 2,
            attributes: {},
            warnings: [],
          },
        ],
      },
    },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Empresas')
    .trigger('click');
  await flushPromises();
  const rows = wrapper.findAll('tbody tr');
  expect(rows[2].text()).toContain('Empresa identificada no registro 2');
  expect(rows[2].text()).toContain('Vincular à empresa identificada');
  expect(rows[2].text()).not.toContain('linha anterior');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  wrapper.unmount();
});
