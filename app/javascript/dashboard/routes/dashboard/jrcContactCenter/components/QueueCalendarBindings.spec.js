import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import QueueCalendarBindings from './QueueCalendarBindings.vue';
import { newCalendarDefinition } from '../helpers/calendarForm';
import locale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    queueCalendars: vi.fn(),
    queueCalendar: vi.fn(),
    unitCalendar: vi.fn(),
    saveQueueCalendar: vi.fn(),
    removeQueueCalendar: vi.fn(),
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
const current = () => {
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC calendar',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  return {
    account_id: '1',
    unit_id: '10',
    revision: 'a'.repeat(64),
    local_only: true,
    pabx_confirmed: false,
    item: { id, active: false, definition },
  };
};
const row = () => ({
  account_id: '1',
  unit_id: '10',
  queue_id: '20',
  queue_name: 'SYNTHETIC queue',
  queue_revision: 'b'.repeat(64),
  binding: null,
  calendar_changed: false,
  local_only: true,
  pabx_confirmed: false,
  external_impact: 'unknown',
});
const fixture = () =>
  mount(QueueCalendarBindings, {
    props: {
      accountId: '1',
      unitId: '10',
      calendarId: id,
      contextKey: 'SYNTHETIC profile',
      canManage: true,
    },
    global: {
      stubs: { Button, Dialog },
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
      ],
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.queueCalendars.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '10',
      items: [row()],
      meta: { page: 1, per_page: 20, total: 1, pages: 1 },
    },
  });
  API.queueCalendar.mockImplementation(async () => ({ data: row() }));
  API.unitCalendar.mockImplementation(async () => ({ data: current() }));
  API.saveQueueCalendar.mockImplementation(async (_account, _queue, body) => ({
    data: {
      ...row(),
      queue_revision: 'c'.repeat(64),
      binding: {
        format: 'jrc-cc-queue-calendar-v1',
        id: body.idempotency_key,
        calendar_snapshot: current().item,
        calendar_digest: 'd'.repeat(64),
        request_digest: 'e'.repeat(64),
        scope_snapshot: { account_id: '1', unit_id: '10', queue_id: '20' },
      },
    },
  }));
});
describe('actual queue calendar component with native fields and mocked transport, not CSS or persistence proof', () => {
  it('separates actual internal links from candidate selection and preserves an explicit external-impact warning', async () => {
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    expect(
      wrapper
        .get('[data-calendar-link-filter="all"]')
        .attributes('aria-pressed')
    ).toBe('true');
    API.queueCalendars.mockResolvedValueOnce({
      data: {
        account_id: '1',
        unit_id: '10',
        items: [],
        meta: { page: 1, per_page: 20, total: 0, pages: 0 },
      },
    });
    await wrapper.get('[data-calendar-link-filter="linked"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Nenhum vínculo interno de fila');
    expect(wrapper.text()).toContain(
      'Este painel consulta somente vínculos internos de filas autorizadas.'
    );
    expect(wrapper.text()).toContain(
      'Números e URAs não são consultados aqui; o impacto no PABX permanece desconhecido.'
    );
    expect(
      wrapper
        .get('[data-calendar-link-filter="linked"]')
        .attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.findAll('[data-calendar-queue]')).toHaveLength(0);
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });

  it('opens a scoped candidate inventory with a truthful provider-impact warning and no automatic association', async () => {
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain(
      'O uso e o impacto no PABX são desconhecidos'
    );
    expect(wrapper.text()).toContain('Sem vínculo interno');
    expect(
      wrapper.get('[data-save-queue-calendar]').attributes('disabled')
    ).toBeDefined();
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });
  it('requires review before one persisted-receipt confirmation and never reports PABX application', async () => {
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-queue-calendar="20"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.get('[data-save-queue-calendar]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-confirm-queue-calendar]').setValue(true);
    await wrapper.get('[data-save-queue-calendar]').trigger('click');
    await flushPromises();
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    expect(wrapper.get('[data-calendar-queue-review]').text()).not.toContain(
      'Sem vínculo interno de calendário.'
    );
    expect(wrapper.get('[data-queue-calendar-confirmed]').text()).toContain(
      'Aplicação no PABX não confirmada'
    );
    expect(
      wrapper.get('[data-save-queue-calendar]').attributes('disabled')
    ).toBeDefined();
  });
  it('locks the actual own footer during a pending write without permitting a second submit or close', async () => {
    let resolve;
    API.saveQueueCalendar.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-queue-calendar="20"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-confirm-queue-calendar]').setValue(true);
    await wrapper.get('[data-save-queue-calendar]').trigger('click');
    await flushPromises();
    const footer = wrapper.get('[role="dialog"]').findAll('button').slice(-2);
    expect(
      footer.every(button => button.attributes('disabled') !== undefined)
    ).toBe(true);
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    resolve({ data: {} });
    await flushPromises();
    expect(wrapper.text()).toContain('O resultado não pôde ser confirmado');
    expect(wrapper.find('[data-queue-calendar-confirmed]').exists()).toBe(
      false
    );
  });
  it('closes and clears private draft data immediately on a profile change', async () => {
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-queue-calendar="20"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-calendar-queue-review]').exists()).toBe(true);
    await wrapper.setProps({
      contextKey: 'SYNTHETIC changed profile',
      canManage: false,
    });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });
  it('locks the parent dialog and binding submit until separately reviewed removal and fresh current state are finished', async () => {
    const bound = {
      ...row(),
      binding: {
        format: 'jrc-cc-queue-calendar-v1',
        id,
        calendar_snapshot: current().item,
        calendar_digest: 'd'.repeat(64),
        request_digest: 'e'.repeat(64),
        scope_snapshot: { account_id: '1', unit_id: '10', queue_id: '20' },
      },
    };
    API.queueCalendar
      .mockResolvedValueOnce({ data: bound })
      .mockResolvedValue({ data: row() });
    API.removeQueueCalendar.mockImplementation(
      async (_account, _queue, body) => ({
        data: {
          contract_version: 1,
          format: 'jrc-cc-queue-calendar-removal-v1',
          account_id: '1',
          unit_id: '10',
          queue_id: '20',
          idempotency_key: body.idempotency_key,
          removed_binding_id: id,
          removed_calendar_digest: 'd'.repeat(64),
          queue_revision_after: 'c'.repeat(64),
          audit_id: '30',
          historical_receipt: true,
          local_only: true,
          pabx_confirmed: false,
          external_impact: 'unknown',
        },
      })
    );
    const wrapper = fixture();
    await wrapper
      .get(`[data-queue-calendar-bindings="${id}"]`)
      .trigger('click');
    await flushPromises();
    await wrapper.get('[data-review-queue-calendar="20"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-confirm-queue-calendar]').setValue(true);
    await wrapper.get('[data-review-calendar-removal]').trigger('click');
    expect(wrapper.get('[data-confirm-queue-calendar]').element.checked).toBe(
      false
    );
    expect(wrapper.get('[data-save-queue-calendar]').element.disabled).toBe(
      true
    );
    expect(
      wrapper
        .get('[role="dialog"]')
        .findAll('button')
        .slice(-2)
        .every(button => button.element.disabled)
    ).toBe(true);
    await wrapper.get('[data-confirm-calendar-removal]').setValue(true);
    await wrapper.get('[data-submit-calendar-removal]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-calendar-removal-receipt]').text()).toContain(
      'auditoria 30'
    );
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
    await wrapper.get('[data-finish-calendar-removal]').trigger('click');
    expect(wrapper.find('[data-review-calendar-removal]').exists()).toBe(false);
    expect(wrapper.get('[data-save-queue-calendar]').element.disabled).toBe(
      true
    );
    expect(wrapper.get('[data-confirm-queue-calendar]').element.checked).toBe(
      false
    );
  });
});
