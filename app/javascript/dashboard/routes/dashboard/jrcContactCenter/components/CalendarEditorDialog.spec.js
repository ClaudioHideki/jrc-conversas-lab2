import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import CalendarEditorDialog from './CalendarEditorDialog.vue';
import { newCalendarDefinition } from '../helpers/calendarForm';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
const calendar = locale.JRC_CONTACT_CENTER.CALENDAR;
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    unitCalendars: vi.fn(),
    unitCalendar: vi.fn(),
    saveUnitCalendar: vi.fn(),
    configurationRecord: vi.fn(),
  },
}));
const Button = {
  props: { label: String, disabled: Boolean },
  emits: ['click'],
  template:
    '<button type="button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};
const Dialog = {
  props: { dismissible: Boolean },
  emits: ['confirm', 'close'],
  setup(props, { expose, emit, slots }) {
    const visible = ref(false);
    const close = () => {
      visible.value = false;
      emit('close');
    };
    expose({
      open: () => {
        visible.value = true;
      },
      close,
    });
    return () =>
      visible.value
        ? h(
            'form',
            {
              role: 'dialog',
              onSubmit: event => {
                event.preventDefault();
                emit('confirm');
              },
            },
            [slots.default?.(), slots.footer?.()]
          )
        : null;
  },
};
const id = '11111111-1111-4111-8111-111111111111';
const row = () => {
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC reviewed schedule',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  return { id, active: false, definition };
};
const scope = overrides => ({
  account_id: '1',
  unit_id: '10',
  revision: 'a'.repeat(64),
  local_only: true,
  pabx_confirmed: false,
  ...overrides,
});
const fixture = () =>
  mount(CalendarEditorDialog, {
    props: {
      accountId: '1',
      unitId: '10',
      timezone: 'America/Sao_Paulo',
      contextKey: 'SYNTHETIC configure',
      canManage: true,
    },
    global: {
      stubs: { Button, Dialog },
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { JRC_CONTACT_CENTER: { CALENDAR: calendar } } },
        }),
      ],
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.unitCalendar.mockResolvedValue({ data: scope({ item: row() }) });
  API.unitCalendars.mockResolvedValue({
    data: scope({ items: [row()], meta: { total: 1 } }),
  });
  API.saveUnitCalendar.mockImplementation(async (_account, _unit, item) => ({
    data: scope({ item, revision: 'b'.repeat(64) }),
  }));
});
describe('calendar dialog with real fields/editor/revision hook and mocked APIs; not persistence or CSS', () => {
  it('requires human review, performs one write and emits confirmed content', async () => {
    const wrapper = fixture();
    await wrapper.vm.open(id);
    await flushPromises();
    expect(
      wrapper.get('[data-save-unit-calendar]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain('Salvar não publica');
    await wrapper.get('[data-review-unit-calendar]').setValue(true);
    await wrapper.get('[data-save-unit-calendar]').trigger('click');
    await flushPromises();
    expect(API.saveUnitCalendar).toHaveBeenCalledWith(
      '1',
      '10',
      row(),
      'a'.repeat(64),
      true
    );
    expect(API.saveUnitCalendar).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('saved')[0][0]).toMatchObject(row());
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  });
  it('locks its own footer during a pending request without a duplicate write', async () => {
    let finish;
    API.saveUnitCalendar.mockImplementationOnce(
      () =>
        new Promise(done => {
          finish = done;
        })
    );
    const wrapper = fixture();
    await wrapper.vm.open(id);
    await flushPromises();
    await wrapper.get('[data-review-unit-calendar]').setValue(true);
    await wrapper.get('[data-save-unit-calendar]').trigger('click');
    expect(
      wrapper.get('[data-close-unit-calendar]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.get('[data-save-unit-calendar]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-close-unit-calendar]').trigger('click');
    await wrapper.get('[role="dialog"]').trigger('submit');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    expect(API.saveUnitCalendar).toHaveBeenCalledOnce();
    finish({ data: scope({ item: row() }) });
    await flushPromises();
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });
  it('preserves a stale draft and requires review of a freshly reloaded definition', async () => {
    API.saveUnitCalendar.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    const wrapper = fixture();
    await wrapper.vm.open(id);
    await flushPromises();
    await wrapper.get('[data-review-unit-calendar]').setValue(true);
    await wrapper.get('[data-save-unit-calendar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-calendar-revision-conflict]').exists()).toBe(
      true
    );
    await wrapper.get('[data-reload-calendar-revision]').trigger('click');
    await flushPromises();
    expect(API.configurationRecord).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-save-unit-calendar]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.findAll('fieldset[disabled]').length).toBeGreaterThan(0);
    await wrapper.get('[data-review-calendar-revision]').setValue(true);
    await wrapper.get('[data-review-unit-calendar]').setValue(true);
    expect(
      wrapper.get('[data-save-unit-calendar]').attributes('disabled')
    ).toBeUndefined();
    expect(API.saveUnitCalendar).toHaveBeenCalledOnce();
  });
  it('clears the form on native access withdrawal and refuses to reopen', async () => {
    const wrapper = fixture();
    await wrapper.vm.open(id);
    await flushPromises();
    await wrapper.setProps({ canManage: false });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC reviewed schedule');
    await wrapper.vm.open(id);
    await flushPromises();
    expect(API.unitCalendar).toHaveBeenCalledOnce();
    expect(API.saveUnitCalendar).not.toHaveBeenCalled();
  });
});
