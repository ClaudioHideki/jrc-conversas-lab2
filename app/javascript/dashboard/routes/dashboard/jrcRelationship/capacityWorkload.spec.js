import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Workload from './CapacityWorkloadForm.vue';
import Limits from './PortfolioCapacityLimitsForm.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

it('requires all point factors explicitly and does not introduce illustrative Word values', async () => {
  const wrapper = mount(Workload, { props: { modelValue: {} } });
  await wrapper.get('[data-testid="enable-points"]').setValue(true);
  const draft = wrapper.emitted('update:modelValue').at(-1)[0];
  expect(Object.values(draft.points)).toEqual([null, null, null, null, null]);
  await wrapper.setProps({ modelValue: draft });
  await wrapper
    .get('[data-testid="workload-complexity_factor"]')
    .setValue('1.5');
  expect(
    wrapper.emitted('update:modelValue').at(-1)[0].points.complexity_factor
  ).toBe(1.5);
  expect(draft.points.complexity_factor).toBeNull();
  wrapper.unmount();
});

it('persists typed equivalent-hour input separately from points and permits explicit removal', async () => {
  const wrapper = mount(Workload, { props: { modelValue: { hours: 2 } } });
  await wrapper.get('[data-testid="workload-hours"]').setValue('2.5');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
    hours: 2.5,
  });
  await wrapper.get('[data-testid="enable-hours"]').setValue(false);
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({});
  wrapper.unmount();
});

it('supports fractional hours limits while keeping legacy customer limits integral', async () => {
  const row = {
    user_id: 3,
    maximum: 2.5,
    availability: 1,
    dedication: 1,
    unit: 'hours',
  };
  const wrapper = mount(Limits, {
    props: { modelValue: [row], owners: [[3, 'Synthetic analyst']] },
  });
  expect(wrapper.emitted('validity').at(-1)).toEqual([true]);
  expect(wrapper.findAll('input')[0].attributes('step')).toBe('any');
  await wrapper.setProps({ modelValue: [{ ...row, unit: 'customers' }] });
  expect(wrapper.emitted('validity').at(-1)).toEqual([false]);
  expect(wrapper.findAll('input')[0].attributes('step')).toBe('1');
  wrapper.unmount();
});

it('does not emit hidden edits from a disabled workload form', async () => {
  const wrapper = mount(Workload, {
    props: { modelValue: { hours: 2 }, disabled: true },
  });
  await wrapper.get('[data-testid="workload-hours"]').setValue('3');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  wrapper.unmount();
});
