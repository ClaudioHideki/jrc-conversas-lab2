import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { h, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import CalendarLibrary from './CalendarLibrary.vue';
import { newCalendarDefinition } from '../helpers/calendarForm';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
const calendar = locale.JRC_CONTACT_CENTER.CALENDAR;

const mocks = vi.hoisted(() => ({
  route: null,
  replace: vi.fn(),
  user: null,
  openEditor: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { unitCalendars: vi.fn(), previewUnitCalendar: vi.fn() },
}));
const Editor = {
  name: 'CalendarEditorDialog',
  props: { canManage: Boolean, timezone: String, unitId: String },
  emits: ['saved', 'denied'],
  setup(props, { expose }) {
    expose({ open: mocks.openEditor });
    return () =>
      h('div', {
        'data-calendar-editor-fixture': true,
        'data-unit': props.unitId,
        'data-timezone': props.timezone,
        'data-configure': String(props.canManage),
      });
  },
};
const Button = {
  props: { label: String, disabled: Boolean },
  emits: ['click'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};
const Dialog = {
  props: { disableConfirmButton: Boolean },
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
            [
              slots.default?.(),
              h(
                'button',
                {
                  type: 'submit',
                  disabled: props.disableConfirmButton,
                  'data-preview-submit': true,
                },
                'SYNTHETIC preview submit'
              ),
              h(
                'button',
                { type: 'button', onClick: close, 'data-preview-close': true },
                'SYNTHETIC preview close'
              ),
            ]
          )
        : null;
  },
};
const id = '11111111-1111-4111-8111-111111111111';
const row = (name = 'SYNTHETIC authorized calendar', identity = id) => {
  const definition = { ...newCalendarDefinition('America/Sao_Paulo'), name };
  definition.weekly['1'] = [['08:00', '12:00']];
  return { id: identity, active: false, definition };
};
const response = (unit = '10', page = 1) => ({
  data: {
    account_id: '1',
    unit_id: unit,
    unit_timezone: 'America/Sao_Paulo',
    local_only: true,
    pabx_confirmed: false,
    revision: 'a'.repeat(64),
    items: [row(`SYNTHETIC authorized calendar ${unit} page${page}`)],
    meta: { page, per_page: 20, total: 21, pages: 2 },
  },
});
const fixture = () =>
  mount(CalendarLibrary, {
    props: {
      accountId: '1',
      context: {
        capabilities: { configure: true },
        units: [
          { id: '10', name: 'SYNTHETIC unit A' },
          { id: '11', name: 'SYNTHETIC unit B' },
        ],
      },
    },
    global: {
      stubs: { Button, Dialog, CalendarEditorDialog: Editor },
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
  mocks.route = reactive({ query: { keep: 'SYNTHETIC unrelated query' } });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  mocks.user = ref({
    id: 7,
    accounts: [
      {
        id: 1,
        role: 'administrator',
        permissions: ['jrc_contact_center_configure'],
      },
    ],
  });
  API.unitCalendars.mockImplementation(async (_account, unit, params) =>
    response(unit, params.page)
  );
  API.previewUnitCalendar.mockImplementation(
    async (_account, unit, calendarId, date) => ({
      data: {
        account_id: '1',
        preview: {
          unit_id: unit,
          calendar_id: calendarId,
          date,
          name: 'SYNTHETIC native preview',
          timezone: 'America/Sao_Paulo',
          active: false,
          precedence: 'exception',
          working_seconds: 3600,
          intervals: [['10:00', '11:00']],
          local_only: true,
          pabx_confirmed: false,
        },
      },
    })
  );
});

describe('internal calendar library wiring; mocked APIs and Dialog, not native persistence or CSS', () => {
  it('loads the native current unit once and passes its actual timezone without inventing a default', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(API.unitCalendars).toHaveBeenCalledOnce();
    expect(API.unitCalendars).toHaveBeenCalledWith('1', '10', {
      q: '',
      status: 'all',
      page: 1,
      per_page: 20,
    });
    expect(wrapper.text()).toContain('SYNTHETIC authorized calendar 10 page1');
    expect(
      wrapper.get('[data-calendar-editor-fixture]').attributes()
    ).toMatchObject({
      'data-timezone': 'America/Sao_Paulo',
      'data-configure': 'true',
    });
    expect(wrapper.text()).toContain('Salvar não publica');
  });

  it('persists URL filters, native page calls and unrelated query state and clears filters without recursive Dialog closes', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get('[data-calendar-search]').setValue('SYNTHETIC selected');
    await wrapper.get('[data-calendar-status]').setValue('inactive');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.route.query).toMatchObject({
      keep: 'SYNTHETIC unrelated query',
      calendar_q: 'SYNTHETIC selected',
      calendar_status: 'inactive',
      calendar_page: 1,
    });
    expect(API.unitCalendars).toHaveBeenLastCalledWith('1', '10', {
      q: 'SYNTHETIC selected',
      status: 'inactive',
      page: 1,
      per_page: 20,
    });
    await wrapper.get('[data-calendar-next]').trigger('click');
    await flushPromises();
    expect(API.unitCalendars).toHaveBeenLastCalledWith('1', '10', {
      q: 'SYNTHETIC selected',
      status: 'inactive',
      page: 2,
      per_page: 20,
    });
    expect(wrapper.text()).toContain('SYNTHETIC authorized calendar 10 page2');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Limpar filtros')
      .trigger('click');
    await flushPromises();
    expect(API.unitCalendars).toHaveBeenLastCalledWith('1', '10', {
      q: '',
      status: 'all',
      page: 1,
      per_page: 20,
    });
    expect(mocks.route.query.keep).toBe('SYNTHETIC unrelated query');
    expect(API.unitCalendars).toHaveBeenCalledTimes(4);
  });

  it('reads a date preview and clears every private result immediately when the native user leaves the account context', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.get(`[data-preview-unit-calendar="${id}"]`).trigger('click');
    await flushPromises();
    await wrapper.get('[data-calendar-preview-date]').setValue('2026-11-23');
    await wrapper.get('[role="dialog"]').trigger('submit');
    await flushPromises();
    expect(API.previewUnitCalendar).toHaveBeenCalledWith(
      '1',
      '10',
      id,
      '2026-11-23'
    );
    expect(wrapper.get('[data-calendar-preview-result]').text()).toContain(
      'SYNTHETIC native preview'
    );
    expect(wrapper.get('[data-calendar-preview-precedence]').text()).toContain(
      'exceção explícita'
    );
    expect(wrapper.get('[data-calendar-preview-result]').text()).toContain(
      '3600 segundos'
    );
    mocks.user.value = null;
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC native preview');
    expect(wrapper.text()).not.toContain('SYNTHETIC authorized calendar');
    expect(API.unitCalendars).toHaveBeenCalledOnce();
  });

  it('discards a delayed list from an old native unit instead of replacing the selected unit data', async () => {
    let resolve;
    API.unitCalendars.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await wrapper.get('[data-calendar-unit]').setValue('11');
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC authorized calendar 11 page1');
    resolve(response('10'));
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'SYNTHETIC authorized calendar 10 page1'
    );
    expect(
      wrapper.get('[data-calendar-editor-fixture]').attributes('data-unit')
    ).toBe('11');
  });

  it('reloads a validated child receipt once and retains its real identity outside restrictive filters', async () => {
    const wrapper = fixture();
    await flushPromises();
    wrapper
      .getComponent({ name: 'CalendarEditorDialog' })
      .vm.$emit('saved', row());
    await flushPromises();
    expect(wrapper.get('[data-calendar-saved]').text()).toContain(
      'SYNTHETIC authorized calendar salvo'
    );
    expect(API.unitCalendars).toHaveBeenCalledTimes(2);
    await wrapper.get('[data-calendar-saved] button').trigger('click');
    expect(mocks.openEditor).toHaveBeenCalledOnce();
    expect(mocks.openEditor).toHaveBeenCalledWith(id);
  });

  it('does not render a foreign account payload or accept administrator as a fallback after native denial', async () => {
    API.unitCalendars.mockResolvedValueOnce({
      data: { ...response().data, account_id: '999' },
    });
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.find('[data-unit-calendar]').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Não foi possível carregar'
    );
    API.unitCalendars.mockRejectedValueOnce({ response: { status: 401 } });
    await wrapper.get('[data-calendar-unit]').setValue('11');
    await flushPromises();
    expect(
      wrapper.get('[data-calendar-editor-fixture]').attributes('data-configure')
    ).toBe('false');
    expect(wrapper.find('[data-unit-calendar]').exists()).toBe(false);
  });
});
