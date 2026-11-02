import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import CompositionSlaTargets from '../CompositionSlaTargets.vue';
import {
  blankComposition,
  compositionPayload,
  emptyCalendar,
} from '../compositionForm';

it('converts the three actual SLA minute fields to seconds and emits a native split-period calendar', async () => {
  const attributes = blankComposition('lifecycle');
  attributes.code = 'synthetic-explicit-sla';
  attributes.definition.lifecycle.sla.mode = 'calendar_snapshot';
  attributes.definition.families.sla_selection = {
    rules: [
      {
        key: 'normal',
        precedence: 1,
        match: { priority_id: 8 },
        output: {
          snapshot: { policy_conditions: { clock_budgets_seconds: {} } },
        },
      },
    ],
  };
  const calendar = emptyCalendar();
  calendar.timezone = 'America/Sao_Paulo';
  const wrapper = mount(CompositionSlaTargets, {
    props: {
      unitId: '1',
      modelValue: attributes.definition,
      calendar,
      calendarCode: 'explicit-calendar',
      calendarVersion: 'v1',
      'onUpdate:calendar': next => wrapper.setProps({ calendar: next }),
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        LookupSelect: true,
        LifecycleVisualEditor: true,
        ClockThresholdEditor: true,
      },
    },
  });
  try {
    const clocks = messages.JRC_SERVICE_DESK.COORDINATED.clocks;
    await wrapper
      .get(`input[aria-label="${clocks.first_response}"]`)
      .setValue('30');
    await wrapper
      .get(`input[aria-label="${clocks.attendance}"]`)
      .setValue('60');
    await wrapper
      .get(`input[aria-label="${clocks.resolution}"]`)
      .setValue('240');
    await wrapper
      .get('input[id$="-day-1"]')
      .setValue('08:00-12:00;13:00-18:00');
    await flushPromises();
    const payload = compositionPayload(
      attributes,
      0,
      wrapper.props('calendar'),
      'explicit-calendar',
      'v1'
    );
    const snapshot =
      payload.definition.families.sla_selection.rules[0].output.snapshot;
    expect(payload.definition.lifecycle.schema_version).toBe(2);
    expect(snapshot.policy_conditions.clock_budgets_seconds).toEqual({
      first_response: 1800,
      attendance: 3600,
      resolution: 14400,
    });
    expect(snapshot.calendar_conditions.weekly['1']).toEqual([
      ['08:00', '12:00'],
      ['13:00', '18:00'],
    ]);
    expect(
      Object.keys(snapshot.policy_conditions.clock_budgets_seconds)
    ).not.toContain('update');
  } finally {
    wrapper.unmount();
  }
});
