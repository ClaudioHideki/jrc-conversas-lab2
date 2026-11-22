import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import QueueCalendarRemoval from './QueueCalendarRemoval.vue';
import strings from 'dashboard/i18n/locale/en/jrcContactCenter.json';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { queueCalendar: vi.fn(), removeQueueCalendar: vi.fn() },
}));
const bindingId = '11111111-1111-4111-8111-111111111111';
const row = () => ({
  account_id: '1',
  unit_id: '10',
  queue_id: '20',
  queue_name: 'SYNTHETIC queue',
  queue_revision: 'a'.repeat(64),
  binding: {
    id: bindingId,
    calendar_digest: 'b'.repeat(64),
    calendar_snapshot: { definition: { name: 'SYNTHETIC reviewed calendar' } },
  },
});
const receipt = body => ({
  contract_version: 1,
  format: 'jrc-cc-queue-calendar-removal-v1',
  account_id: '1',
  unit_id: '10',
  queue_id: '20',
  idempotency_key: body.idempotency_key,
  removed_binding_id: bindingId,
  removed_calendar_digest: 'b'.repeat(64),
  queue_revision_after: 'c'.repeat(64),
  audit_id: '30',
  historical_receipt: true,
  local_only: true,
  pabx_confirmed: false,
  external_impact: 'unknown',
});
const fixture = () =>
  mount(QueueCalendarRemoval, {
    props: {
      accountId: '1',
      unitId: '10',
      row: row(),
      contextKey: 'SYNTHETIC profile',
      canManage: true,
      validateCurrent: value =>
        value?.account_id === '1' &&
        value?.unit_id === '10' &&
        value?.queue_id === '20',
    },
    global: {
      stubs: {
        Button: {
          props: { label: String, disabled: Boolean },
          emits: ['click'],
          template:
            '<button type="button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: {
            en: {
              JRC_CONTACT_CENTER: {
                CALENDAR_REMOVAL: strings.JRC_CONTACT_CENTER.CALENDAR_REMOVAL,
                CALENDAR: {
                  LOADING: 'Carregando',
                  RELOAD: 'Carregar estado atual',
                },
                CALENDAR_BINDING: {
                  NONE: 'Sem vínculo interno de calendário.',
                },
              },
            },
          },
        }),
      ],
    },
  });
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  API.queueCalendar.mockResolvedValue({ data: { ...row(), binding: null } });
  API.removeQueueCalendar.mockImplementation(
    async (_account, _queue, body) => ({ data: receipt(body) })
  );
});
describe('reviewed removal controls with mocked transport; not real browser proof', () => {
  it('locks sibling actions, requires review, shows the durable receipt and returns only the separately read current state', async () => {
    const view = fixture();
    await view.get('[data-review-calendar-removal]').trigger('click');
    expect(view.emitted('lock').at(-1)).toEqual([true]);
    expect(view.text()).toContain('SYNTHETIC reviewed calendar');
    expect(view.get('[data-submit-calendar-removal]').element.disabled).toBe(
      true
    );
    await view.get('[data-confirm-calendar-removal]').setValue(true);
    await view.get('[data-submit-calendar-removal]').trigger('click');
    await flushPromises();
    expect(view.get('[data-calendar-removal-receipt]').text()).toContain(
      'auditoria 30'
    );
    expect(view.get('[data-calendar-removal-current]').text()).toContain(
      'Sem vínculo interno'
    );
    expect(view.emitted('current')).toBeUndefined();
    await view.get('[data-finish-calendar-removal]').trigger('click');
    expect(view.emitted('current').at(-1)).toEqual([
      { ...row(), binding: null },
    ]);
    expect(view.emitted('lock').at(-1)).toEqual([false]);
  });
  it('does not enable a second submit or dismissal while a request is pending', async () => {
    let resolve;
    API.removeQueueCalendar.mockReturnValueOnce(
      new Promise(yes => {
        resolve = yes;
      })
    );
    const view = fixture();
    await view.get('[data-review-calendar-removal]').trigger('click');
    await view.get('[data-confirm-calendar-removal]').setValue(true);
    await view.get('[data-submit-calendar-removal]').trigger('click');
    expect(view.get('[data-submit-calendar-removal]').element.disabled).toBe(
      true
    );
    expect(view.find('[data-finish-calendar-removal]').exists()).toBe(false);
    expect(view.emitted('lock').at(-1)).toEqual([true]);
    resolve({ data: receipt(API.removeQueueCalendar.mock.calls[0][2]) });
    await flushPromises();
    expect(API.removeQueueCalendar).toHaveBeenCalledTimes(1);
  });
  it('offers explicit acknowledged abandonment of an unknown result without declaring success', async () => {
    API.removeQueueCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC unavailable response')
    );
    const view = fixture();
    await view.get('[data-review-calendar-removal]').trigger('click');
    await view.get('[data-confirm-calendar-removal]').setValue(true);
    await view.get('[data-submit-calendar-removal]').trigger('click');
    await flushPromises();
    expect(view.get('[data-abandon-calendar-removal]').element.disabled).toBe(
      true
    );
    expect(view.find('[data-calendar-removal-receipt]').exists()).toBe(false);
    await view.get('[data-abandon-calendar-removal-review]').setValue(true);
    await view.get('[data-abandon-calendar-removal]').trigger('click');
    expect(view.emitted('current')).toBeUndefined();
    expect(view.emitted('lock').at(-1)).toEqual([false]);
  });
  it('clears private review and disables access after an actual canManage prop change', async () => {
    const view = fixture();
    await view.get('[data-review-calendar-removal]').trigger('click');
    await view.setProps({ canManage: false });
    expect(view.find('[data-confirm-calendar-removal]').exists()).toBe(false);
    expect(view.get('[data-review-calendar-removal]').element.disabled).toBe(
      true
    );
    expect(view.emitted('lock').at(-1)).toEqual([false]);
    expect(API.removeQueueCalendar).not.toHaveBeenCalled();
  });
});
