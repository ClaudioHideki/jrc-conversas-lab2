import { afterEach, describe, expect, it } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CalendarHoursInput from './CalendarHoursInput.vue';
import CalendarDetailsFields from './CalendarDetailsFields.vue';
import {
  newCalendarDefinition,
  validCalendarDefinition,
} from '../helpers/calendarForm';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
const calendar = locale.JRC_CONTACT_CENTER.CALENDAR;

const plugins = () => [
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { JRC_CONTACT_CENTER: { CALENDAR: calendar } } },
  }),
];
enableAutoUnmount(afterEach);
const hours = () => {
  let wrapper;
  wrapper = mount(CalendarHoursInput, {
    props: {
      modelValue: [['08:00', '12:00']],
      label: 'SYNTHETIC interval',
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
    global: { plugins: plugins() },
  });
  return wrapper;
};
const details = () => {
  let wrapper;
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC working calendar',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  wrapper = mount(CalendarDetailsFields, {
    props: {
      modelValue: definition,
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
    global: { plugins: plugins() },
  });
  return wrapper;
};

describe('internal Call Center calendar tabs and native interval helpers; no CSS or persistence claim', () => {
  it('keeps interval input and visible overlap errors instead of submitting previously valid hours', async () => {
    const wrapper = hours();
    const input = wrapper.get('[data-calendar-hours]');
    expect(
      wrapper.get(`label[for="${input.attributes('id')}"]`).text()
    ).toContain('SYNTHETIC interval');
    await input.setValue('08:00-12:00;11:00-17:00');
    await flushPromises();
    expect(wrapper.props('modelValue')).toBe('08:00-12:00;11:00-17:00');
    expect(input.attributes('aria-invalid')).toBe('true');
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'não podem se sobrepor'
    );
    await input.trigger('blur');
    expect(input.element.value).toBe('08:00-12:00;11:00-17:00');
    await input.setValue('08:00-12:00;13:00-17:00');
    await flushPromises();
    expect(wrapper.props('modelValue')).toEqual([
      ['08:00', '12:00'],
      ['13:00', '17:00'],
    ]);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('retains the native typing buffer for a second interval and treats an empty day as explicitly closed', async () => {
    const wrapper = hours();
    const input = wrapper.get('[data-calendar-hours]');
    await input.setValue('08:00-12:00;');
    await flushPromises();
    expect(input.element.value).toBe('08:00-12:00;');
    await input.setValue(' 08:00 - 12:00 , 13:00 - 17:00 ');
    await flushPromises();
    expect(input.element.value).toBe(' 08:00 - 12:00 , 13:00 - 17:00 ');
    await input.trigger('blur');
    expect(input.element.value).toBe('08:00-12:00;13:00-17:00');
    await input.setValue('');
    await flushPromises();
    expect(wrapper.props('modelValue')).toEqual([]);
  });

  it('shows Portuguese tabs, precedence and an explicit local-only boundary without fake bindings or published status', async () => {
    const wrapper = details();
    expect(wrapper.findAll('[role="tab"]').map(row => row.text())).toEqual([
      'Identificação',
      'Expediente',
      'Feriados',
      'Exceções',
    ]);
    expect(wrapper.get('[data-calendar-precedence]').text()).toBe(
      calendar.PRECEDENCE
    );
    expect(wrapper.text()).toContain('Salvar não publica');
    await wrapper.get('[data-calendar-tab="weekly"]').trigger('click');
    expect(wrapper.get('[data-calendar-timezone]').element.value).toBe(
      'America/Sao_Paulo'
    );
    expect(wrapper.findAll('[data-calendar-weekday]')).toHaveLength(7);
    expect(wrapper.findAll('[data-calendar-weekday]')[0].text()).toContain(
      'Segunda-feira'
    );
    expect(wrapper.find('[data-calendar-name]').exists()).toBe(false);
    expect(
      wrapper.get('[data-calendar-tab="weekly"]').attributes('aria-selected')
    ).toBe('true');
  });

  it('preserves typed invalid weekly hours when navigating away and back', async () => {
    const wrapper = details();
    await wrapper.get('[data-calendar-tab="weekly"]').trigger('click');
    await wrapper
      .get('[data-calendar-weekday="1"] input')
      .setValue('08:00-12:00;11:00-17:00');
    await flushPromises();
    expect(validCalendarDefinition(wrapper.props('modelValue'))).toBe(false);
    await wrapper.get('[data-calendar-tab="holidays"]').trigger('click');
    await wrapper.get('[data-calendar-tab="weekly"]').trigger('click');
    expect(wrapper.get('[data-calendar-weekday="1"] input').element.value).toBe(
      '08:00-12:00;11:00-17:00'
    );
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'não podem se sobrepor'
    );
  });

  it('requires actual holiday metadata, prevents duplicate dates and never invents the next year', async () => {
    const wrapper = details();
    await wrapper.get('[data-calendar-tab="holidays"]').trigger('click');
    expect(wrapper.text()).toContain(
      'não calcula nem cadastra automaticamente outros anos'
    );
    await wrapper.get('[data-calendar-holiday-date]').setValue('2026-11-23');
    await wrapper.get('[data-add-calendar-holiday]').trigger('click');
    await flushPromises();
    expect(wrapper.props('modelValue').holidays).toEqual([
      { date: '2026-11-23', name: '', kind: '', type: '' },
    ]);
    expect(validCalendarDefinition(wrapper.props('modelValue'))).toBe(false);
    const row = wrapper.get('[data-calendar-holiday="2026-11-23"]');
    await row
      .get('[data-calendar-date-name]')
      .setValue('SYNTHETIC unit holiday');
    await row.get('[data-calendar-holiday-kind]').setValue('internal');
    await row.get('[data-calendar-holiday-type]').setValue('movable');
    await flushPromises();
    expect(validCalendarDefinition(wrapper.props('modelValue'))).toBe(true);
    await wrapper.get('[data-calendar-holiday-date]').setValue('2026-11-23');
    expect(wrapper.get('[data-add-calendar-holiday]').element.disabled).toBe(
      true
    );
    expect(wrapper.props('modelValue').holidays).toHaveLength(1);
    await row.get('[data-remove-calendar-holiday]').trigger('click');
    await flushPromises();
    expect(wrapper.props('modelValue').holidays).toEqual([]);
  });

  it('keeps an explicitly closed exception and its required name across tabs without assigning a default work period', async () => {
    const wrapper = details();
    await wrapper.get('[data-calendar-tab="exceptions"]').trigger('click');
    await wrapper.get('[data-calendar-exception-date]').setValue('2026-11-23');
    await wrapper.get('[data-add-calendar-exception]').trigger('click');
    await flushPromises();
    const row = wrapper.get('[data-calendar-exception="2026-11-23"]');
    expect(wrapper.props('modelValue').exceptions).toEqual([
      { date: '2026-11-23', name: '', intervals: [] },
    ]);
    await row
      .get('[data-calendar-date-name]')
      .setValue('SYNTHETIC explicit closure');
    await flushPromises();
    expect(validCalendarDefinition(wrapper.props('modelValue'))).toBe(true);
    expect(row.get('[data-calendar-hours]').element.value).toBe('');
    await wrapper.get('[data-calendar-tab="general"]').trigger('click');
    await wrapper.get('[data-calendar-tab="exceptions"]').trigger('click');
    expect(wrapper.get('[data-calendar-date-name]').element.value).toBe(
      'SYNTHETIC explicit closure'
    );
    expect(wrapper.get('[data-calendar-hours]').element.value).toBe('');
  });
});
