import { mount } from '@vue/test-utils';
import Editor from './SegmentCriteriaEditor.vue';
it('offers canonical values with friendly labels and switches E/OU without mutating the provided definition', async () => {
  const criteria = {
    match: 'all',
    rules: [
      { field: 'relationship_type', operator: 'equal_to', value: 'customer' },
    ],
  };
  const wrapper = mount(Editor, { props: { modelValue: criteria } });
  expect(wrapper.findAll('select').at(-1).text()).toContain('Cliente');
  await wrapper.findAll('select').at(0).setValue('any');
  expect(wrapper.emitted('update:modelValue')[0][0].match).toBe('any');
  expect(criteria.match).toBe('all');
  await wrapper.findAll('select').at(1).setValue('active');
  expect(wrapper.emitted('update:modelValue').at(-1)[0].rules[0]).toEqual({
    field: 'active',
    operator: 'equal_to',
    value: 'true',
  });
  wrapper.unmount();
});
