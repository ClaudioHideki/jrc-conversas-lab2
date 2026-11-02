import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import CalendarFields from '../CalendarFields.vue';
import { emptyCalendar } from '../compositionForm';
import { validCalendar } from '../calendarRules';

let wrapper;
const calendar = () => {
  const value = emptyCalendar();
  value.timezone = 'America/Sao_Paulo';
  value.conditions.weekly['1'] = [
    ['08:00', '12:00'],
    ['13:00', '18:00'],
  ];
  value.conditions.exceptions['2026-10-27'] = [];
  return value;
};
function render(value) {
  wrapper = mount(CalendarFields, {
    props: {
      modelValue: value,
      'onUpdate:modelValue': next => wrapper.setProps({ modelValue: next }),
    },
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
}
afterEach(() => wrapper?.unmount());

it('loads native JSON as canonical semicolon text without mutating or emitting the draft', () => {
  const value = calendar();
  const original = JSON.stringify(value);
  render(value);
  expect(wrapper.get('input[id$="-day-1"]').element.value).toBe(
    '08:00-12:00;13:00-18:00'
  );
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  expect(JSON.stringify(value)).toBe(original);
});

it.each(['08:00-12:00;13:00-18:00', '08:00-12:00,13:00-18:00'])(
  'edits %s into exact pairs and canonicalizes on blur',
  async input => {
    render(calendar());
    const field = wrapper.get('input[id$="-day-1"]');
    await field.setValue(input);
    await flushPromises();
    expect(field.element.value).toBe(input);
    expect(wrapper.props('modelValue').conditions.weekly['1']).toEqual([
      ['08:00', '12:00'],
      ['13:00', '18:00'],
    ]);
    expect(validCalendar(wrapper.props('modelValue'))).toBe(true);
    await field.trigger('blur');
    expect(field.element.value).toBe('08:00-12:00;13:00-18:00');
  }
);

it('keeps invalid input visible, marks it inline and invalidates a previously valid model immediately', async () => {
  render(calendar());
  const field = wrapper.get('input[id$="-day-1"]');
  await field.setValue('08:00-13:00;12:00-18:00');
  await flushPromises();
  expect(field.attributes('aria-invalid')).toBe('true');
  expect(field.element.value).toBe('08:00-13:00;12:00-18:00');
  expect(
    wrapper
      .findAll('[role="alert"]')
      .some(row => row.text().includes('sobreposição'))
  ).toBe(true);
  expect(validCalendar(wrapper.props('modelValue'))).toBe(false);
  await field.setValue('08:00-12:00;13:00-18:00');
  await flushPromises();
  expect(field.attributes('aria-invalid')).toBe('false');
  expect(validCalendar(wrapper.props('modelValue'))).toBe(true);
});

it('loads a malformed legacy draft, exposes the error and repairs only after an explicit user action', async () => {
  const value = calendar();
  value.conditions.weekly['1'] = [['08:00', '12:00;13:00', '18:00']];
  const original = JSON.stringify(value);
  render(value);
  expect(wrapper.get('input[id$="-day-1"]').attributes('aria-invalid')).toBe(
    'true'
  );
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  expect(JSON.stringify(value)).toBe(original);
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'Aplicar correção dos horários')
    .trigger('click');
  await flushPromises();
  expect(wrapper.props('modelValue').conditions.weekly['1']).toEqual([
    ['08:00', '12:00'],
    ['13:00', '18:00'],
  ]);
  expect(validCalendar(wrapper.props('modelValue'))).toBe(true);
});

it('applies the same parser to exception hours and keeps a closed day as an empty array', async () => {
  render(calendar());
  const exception = wrapper.get('input[aria-label$="2026-10-27"]');
  await exception.setValue(' 08:00 - 12:00 , 13:00 - 18:00 ');
  await flushPromises();
  expect(
    wrapper.props('modelValue').conditions.exceptions['2026-10-27']
  ).toEqual([
    ['08:00', '12:00'],
    ['13:00', '18:00'],
  ]);
  await exception.trigger('blur');
  expect(exception.element.value).toBe('08:00-12:00;13:00-18:00');
  await exception.setValue('');
  await flushPromises();
  expect(
    wrapper.props('modelValue').conditions.exceptions['2026-10-27']
  ).toEqual([]);
  await wrapper.get('input[id$="-day-1"]').setValue('');
  await flushPromises();
  expect(wrapper.props('modelValue').conditions.weekly['1']).toEqual([]);
});
