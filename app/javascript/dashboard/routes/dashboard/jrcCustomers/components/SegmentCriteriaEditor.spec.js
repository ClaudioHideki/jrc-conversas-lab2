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

it('captures explicit billing dates and a numeric operator without carrying financial options into a directory rule', async () => {
  const criteria = {
    match: 'all',
    rules: [{ field: 'size', operator: 'not_equal_to', value: 'large' }],
  };
  const wrapper = mount(Editor, {
    props: {
      modelValue: criteria,
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
  });
  await wrapper.findAll('select').at(1).setValue('invoiced_revenue');
  expect(wrapper.props('modelValue').rules[0]).toEqual({
    field: 'invoiced_revenue',
    operator: 'equal_to',
    value: '0',
    period_start: '',
    period_end: '',
  });
  await wrapper.findAll('select').at(2).setValue('at_least');
  await wrapper.get('input[type="number"]').setValue('123.45');
  await wrapper.findAll('input[type="date"]').at(0).setValue('2026-10-01');
  await wrapper.findAll('input[type="date"]').at(1).setValue('2026-10-31');
  expect(wrapper.props('modelValue').rules[0]).toEqual({
    field: 'invoiced_revenue',
    operator: 'at_least',
    value: '123.45',
    period_start: '2026-10-01',
    period_end: '2026-10-31',
  });
  expect(criteria.rules[0].field).toBe('size');
  await wrapper.findAll('select').at(1).setValue('active_contract_count');
  expect(wrapper.findAll('input[type="date"]')).toHaveLength(0);
  expect(wrapper.props('modelValue').rules[0]).toEqual({
    field: 'active_contract_count',
    operator: 'equal_to',
    value: '0',
  });
  await wrapper.findAll('select').at(1).setValue('active');
  expect(wrapper.props('modelValue').rules[0]).toEqual({
    field: 'active',
    operator: 'equal_to',
    value: 'true',
  });
  wrapper.unmount();
});
