import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Form from './PortfolioCapacityLimitsForm.vue';
import Summary from './DistributionCapacitySummary.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const entry = { user_id: 7, maximum: 50, availability: 0.8, dedication: 0.5 };

it('edits immutable entries and maps percentage controls to fractional server values', async () => {
  const wrapper = mount(Form, {
    props: { modelValue: [entry], owners: [[7, 'Synthetic analyst']] },
  });
  expect(wrapper.findAll('input').map(row => row.element.value)).toEqual([
    '50',
    '80',
    '50',
  ]);
  await wrapper.findAll('input')[1].setValue('25');
  expect(wrapper.emitted('update:modelValue').at(-1)[0][0].availability).toBe(
    0.25
  );
  expect(entry.availability).toBe(0.8);
  await wrapper.findAll('input')[0].setValue('');
  expect(wrapper.emitted('update:modelValue').at(-1)[0][0].maximum).toBeNull();
  wrapper.unmount();
});

it('rejects duplicate analysts and invalid limits but preserves current entries absent from bounded options', async () => {
  const wrapper = mount(Form, { props: { modelValue: [entry], owners: [] } });
  expect(wrapper.emitted('validity').at(-1)).toEqual([true]);
  expect(wrapper.get('select').element.value).toBe('7');
  await wrapper.setProps({ modelValue: [entry, entry] });
  expect(wrapper.emitted('validity').at(-1)).toEqual([false]);
  await wrapper.setProps({ modelValue: [{ ...entry, maximum: -1 }] });
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  wrapper.unmount();
});

it('adds only distinct selectable analysts with a safe zero maximum and does not mutate while disabled', async () => {
  const wrapper = mount(Form, {
    props: { modelValue: [], owners: [[7, 'Synthetic analyst']] },
  });
  await wrapper.get('button').trigger('click');
  expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
    { user_id: 7, maximum: 0, availability: 1, dedication: 1 },
  ]);
  await wrapper.setProps({ modelValue: [entry], disabled: true });
  const count = wrapper.emitted('update:modelValue').length;
  await wrapper.findAll('button')[0].trigger('click');
  expect(wrapper.emitted('update:modelValue')).toHaveLength(count);
  wrapper.unmount();
});

it('displays reviewed counts and treats redacted capacity as inaccessible rather than zero', () => {
  const wrapper = mount(Summary, {
    props: {
      rows: [
        {
          scope_key: 'account',
          current: 11,
          incoming: 3,
          projected: 14,
          effective_capacity: 20,
          available_after: 6,
        },
        { scope_key: 'unit:920', blocker: 'capacity_scope_denied' },
      ],
    },
  });
  expect(wrapper.findAll('dl')).toHaveLength(1);
  expect(wrapper.findAll('dd').map(row => row.text())).toEqual([
    '11',
    '3',
    '14',
    '20',
    '6',
  ]);
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'capacity_scope_denied'
  );
  expect(wrapper.text()).not.toContain('unit:920');
  wrapper.unmount();
});
