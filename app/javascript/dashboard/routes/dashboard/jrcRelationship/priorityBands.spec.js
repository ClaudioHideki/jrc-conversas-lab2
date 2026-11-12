import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import Form from './PriorityBandsForm.vue';
import Badge from './PriorityBandBadge.vue';
import { capturedPriorityBand, validPriorityBands } from './priorityBands';

const bands = ['P0', 'P1', 'P2', 'P3'].map((code, index) => ({
  code,
  minimum: [90, 80, 60, 0][index],
}));

describe('Explicit native priority bands', () => {
  it('never opts an existing configuration in by rendering the editor', () => {
    const wrapper = mount(Form);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.emitted('validity').at(-1)).toEqual([true]);
    expect(wrapper.findAll('input[type="number"]')).toHaveLength(0);
    wrapper.unmount();
  });

  it('requires operator limits, handles zero without coercing blank fields and disables only by explicit choice', async () => {
    const wrapper = mount(Form);
    await wrapper.get('input[type="checkbox"]').setValue(true);
    const explicit = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(explicit.map(row => row.minimum)).toEqual([null, null, null, null]);
    await wrapper.setProps({ modelValue: explicit });
    expect(wrapper.emitted('validity').at(-1)).toEqual([false]);
    await bands.reduce(async (previous, row, index) => {
      await previous;
      await wrapper
        .findAll('input[type="number"]')
        [index].setValue(row.minimum);
      await wrapper.setProps({
        modelValue: wrapper.emitted('update:modelValue').at(-1)[0],
      });
    }, Promise.resolve());
    expect(wrapper.props('modelValue')).toEqual(bands);
    expect(wrapper.emitted('validity').at(-1)).toEqual([true]);
    await wrapper.findAll('input[type="number"]')[3].setValue('');
    expect(
      wrapper.emitted('update:modelValue').at(-1)[0][3].minimum
    ).toBeNull();
    await wrapper.get('input[type="checkbox"]').setValue(false);
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual([]);
    wrapper.unmount();
  });

  it('validates order, integer minima and full coverage without a guessed fallback', () => {
    expect(validPriorityBands(bands)).toBe(true);
    [
      bands.slice(0, 3),
      bands.toReversed(),
      bands.map(row => ({ ...row, minimum: 10 })),
      bands.map(row => ({ ...row, minimum: String(row.minimum) })),
      bands.map(row => ({ ...row, minimum: row.minimum + 0.5 })),
      bands.map(row => ({ ...row, unknown: true })),
    ].forEach(value => expect(validPriorityBands(value)).toBe(false));
  });

  it('renders the captured label in a narrow wrapping badge and hides missing or stale classifications', async () => {
    const row = {
      priority: 88,
      factors: { priority_band: 'P1', priority_band_score: 88 },
    };
    expect(capturedPriorityBand(row)).toBe('P1');
    const wrapper = mount(Badge, { props: { record: row } });
    expect(wrapper.get('[data-testid="priority-band"]').text()).toContain('P1');
    expect(wrapper.get('span').classes()).toContain('dark:bg-amber-950');
    await wrapper.setProps({ record: { ...row, priority: 100 } });
    expect(wrapper.find('span').exists()).toBe(false);
    await wrapper.setProps({ record: { priority: 95, factors: {} } });
    expect(wrapper.find('span').exists()).toBe(false);
    wrapper.unmount();
  });
});
