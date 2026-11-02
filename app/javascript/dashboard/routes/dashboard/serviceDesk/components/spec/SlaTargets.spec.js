import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import SlaTargetEditor from '../SlaTargetEditor.vue';
import {
  durationSeconds,
  targetBudgets,
  closureConfiguration,
} from '../../helpers/slaTargets';
const model = () => ({
  timezone: 'America/Sao_Paulo',
  source_version: 'synthetic-v1',
  policy_conditions: JSON.stringify({
    provenance: 'synthetic',
    clock_budgets_seconds: { first_response: 3600, resolution: 7200 },
  }),
  calendar_conditions: JSON.stringify({
    format: 'jrc-sd-snapshot-calendar-v1',
    weekly: Object.fromEntries(
      Array.from({ length: 7 }, (_, i) => [String(i + 1), []])
    ),
    holidays: ['2026-10-26'],
    exceptions: { '2026-10-27': [['10:00', '11:00']] },
  }),
});
const render = value =>
  mount(SlaTargetEditor, {
    props: { modelValue: value },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
    },
  });

describe('official SLA target editing', () => {
  it.each([
    ['1', 'minutes', 60],
    ['0.5', 'hours', 1800],
    ['1.5', 'minutes', 90],
    ['17', 'seconds', 17],
  ])('converts %s %s to explicit integer seconds', (value, unit, seconds) => {
    expect(durationSeconds(value, unit)).toBe(seconds);
  });
  it.each([
    '',
    '0',
    '-1',
    'NaN',
    'Infinity',
    '1e9',
    '0.001',
    String(Number.MAX_SAFE_INTEGER),
  ])(
    'rejects invalid or unsafe minute duration %s without treating it as no SLA',
    value => {
      expect(() => durationSeconds(value, 'minutes')).toThrow();
    }
  );
  it('does not invent any target or work interval on opening an empty draft', () => {
    const wrapper = render({
      policy_conditions: '{}',
      calendar_conditions: '{}',
    });
    expect(
      wrapper.findAll('input[type="number"]').map(row => row.element.value)
    ).toEqual(['', '']);
    expect(
      wrapper.findAll('input').every(row => row.element.value === '')
    ).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
  it('changes units without changing stored duration, then edits the chosen target preserving provenance and calendar', async () => {
    const value = model();
    const wrapper = render(value);
    await wrapper.findAll('select')[0].setValue('hours');
    expect(wrapper.findAll('input[type="number"]')[0].element.value).toBe('1');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    await wrapper.findAll('input[type="number"]')[0].setValue('2');
    const updated = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(targetBudgets(JSON.parse(updated.policy_conditions))).toEqual({
      first_response: 7200,
      resolution: 7200,
    });
    expect(JSON.parse(updated.policy_conditions).provenance).toBe('synthetic');
    expect(updated.calendar_conditions).toBe(value.calendar_conditions);
    expect(updated.source_version).toBe(value.source_version);
    wrapper.unmount();
  });
  it('keeps zero visibly invalid and refuses to serialize it as an approved target', async () => {
    const wrapper = render(model());
    await wrapper.findAll('input[type="number"]')[0].setValue('0');
    const updated = wrapper.emitted('update:modelValue').at(-1)[0];
    await wrapper.setProps({ modelValue: updated });
    expect(wrapper.findAll('input[type="number"]')[0].element.value).toBe('0');
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(() =>
      targetBudgets(JSON.parse(updated.policy_conditions))
    ).toThrow();
    wrapper.unmount();
  });
  it('edits explicit work intervals while retaining holidays and date exceptions', async () => {
    const value = model();
    const wrapper = render(value);
    const label = wrapper
      .findAll('label')
      .find(row => row.text().includes('Segunda-feira'));
    await label.get('input').setValue('09:00-12:00;13:00-17:00');
    const updated = JSON.parse(
      wrapper.emitted('update:modelValue').at(-1)[0].calendar_conditions
    );
    expect(updated.weekly['1']).toEqual([
      ['09:00', '12:00'],
      ['13:00', '17:00'],
    ]);
    expect(updated.holidays).toEqual(['2026-10-26']);
    expect(updated.exceptions).toEqual({ '2026-10-27': [['10:00', '11:00']] });
    wrapper.unmount();
  });
  it('only opts a draft into operational closure through explicit selection and preserves the SLA mode and other policy fields', () => {
    const original = {
      schema_version: 1,
      transitions: [{ key: 'original' }],
      sla: { mode: 'calendar_snapshot', initial_start: 'opened_at' },
    };
    const changed = JSON.parse(
      closureConfiguration(JSON.stringify(original), 'operational')
    );
    expect(changed.sla).toEqual({
      ...original.sla,
      obligation: 'operational',
      missing_configuration: 'allow_operational_closure',
    });
    expect(changed.transitions).toEqual(original.transitions);
    expect(
      JSON.parse(closureConfiguration(JSON.stringify(changed), 'contractual'))
        .sla.missing_configuration
    ).toBe('block');
    expect(
      JSON.parse(closureConfiguration(JSON.stringify(changed), 'strict'))
    ).toEqual(original);
  });
});
