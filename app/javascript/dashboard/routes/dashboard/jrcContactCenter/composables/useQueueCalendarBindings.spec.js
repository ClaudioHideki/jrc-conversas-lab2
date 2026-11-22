import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { newCalendarDefinition } from '../helpers/calendarForm';
import { useQueueCalendarBindings } from './useQueueCalendarBindings';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    queueCalendars: vi.fn(),
    queueCalendar: vi.fn(),
    unitCalendar: vi.fn(),
    saveQueueCalendar: vi.fn(),
  },
}));
const calendarId = '11111111-1111-4111-8111-111111111111';
const snapshot = () => {
  const definition = {
    ...newCalendarDefinition('America/Sao_Paulo'),
    name: 'SYNTHETIC calendar',
  };
  definition.weekly['1'] = [['08:00', '12:00']];
  return { id: calendarId, active: false, definition };
};
const current = () => ({
  account_id: '1',
  unit_id: '10',
  revision: 'a'.repeat(64),
  item: snapshot(),
  local_only: true,
  pabx_confirmed: false,
});
const queue = () => ({
  account_id: '1',
  queue_id: '20',
  queue_name: 'SYNTHETIC queue',
  unit_id: '10',
  queue_revision: 'b'.repeat(64),
  binding: null,
  calendar_changed: false,
  local_only: true,
  pabx_confirmed: false,
  external_impact: 'unknown',
});
const accepted = body => ({
  ...queue(),
  queue_revision: 'c'.repeat(64),
  binding: {
    format: 'jrc-cc-queue-calendar-v1',
    id: body.idempotency_key,
    calendar_snapshot: snapshot(),
    calendar_digest: 'd'.repeat(64),
    request_digest: 'e'.repeat(64),
    scope_snapshot: { account_id: '1', unit_id: '10', queue_id: '20' },
  },
});
const deferred = () => {
  let resolve;
  const promise = new Promise(yes => {
    resolve = yes;
  });
  return { promise, resolve };
};
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const contextKey = ref('SYNTHETIC current profile');
  const canManage = ref(true);
  const onDenied = vi.fn();
  let state;
  mount(
    defineComponent({
      setup() {
        state = useQueueCalendarBindings({
          accountId,
          unitId,
          calendarId: ref(calendarId),
          contextKey,
          canManage,
          onDenied,
        });
        return () => null;
      },
    })
  );
  state.dialog.value = { open: vi.fn(), close: vi.fn() };
  return { state, accountId, unitId, contextKey, canManage, onDenied };
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  API.queueCalendars.mockImplementation(
    async (_account, _unit, _calendar, params) => ({
      data: {
        account_id: '1',
        unit_id: '10',
        items: [queue()],
        meta: { page: params.page, per_page: 20, total: 21, pages: 2 },
      },
    })
  );
  API.queueCalendar.mockImplementation(async () => ({ data: queue() }));
  API.unitCalendar.mockImplementation(async () => ({ data: current() }));
  API.saveQueueCalendar.mockImplementation(async (_account, _queue, body) => ({
    data: accepted(body),
  }));
});

describe('queue calendar reviewed lifecycle with mocked transport; not native or PABX proof', () => {
  it('does not load data before explicit opening or without current configuration permission', async () => {
    const { state, canManage } = fixture();
    expect(API.queueCalendars).not.toHaveBeenCalled();
    canManage.value = false;
    await state.open();
    expect(API.queueCalendars).not.toHaveBeenCalled();
    expect(state.active.value).toBe(false);
  });

  it('shows current authorized native queues as candidates without treating them as applied calendar links', async () => {
    const { state } = fixture();
    await state.open();
    expect(state.rows.value).toEqual([queue()]);
    expect(state.rows.value[0].binding).toBeNull();
    expect(state.canSave.value).toBeFalsy();
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });

  it('loads fresh queue and catalog revisions and requires explicit review before saving the exact snapshot', async () => {
    const { state } = fixture();
    await state.open();
    await state.choose('20');
    expect(API.queueCalendar).toHaveBeenCalledWith('1', '10', '20');
    expect(API.unitCalendar).toHaveBeenCalledWith('1', '10', calendarId);
    await state.save();
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
    state.reviewed.value = true;
    await state.save();
    const body = API.saveQueueCalendar.mock.calls[0][2];
    expect(body).toMatchObject({
      unit_id: '10',
      queue_id: '20',
      calendar_id: calendarId,
      calendar_revision: 'a'.repeat(64),
      queue_revision: 'b'.repeat(64),
      reviewed: true,
    });
    expect(state.confirmed.value.binding.calendar_snapshot).toEqual(snapshot());
  });

  it('ignores repeated submit while the same native request is pending and cannot submit a confirmed operation again', async () => {
    const gate = deferred();
    API.saveQueueCalendar.mockImplementationOnce(() => gate.promise);
    const { state } = fixture();
    await state.open();
    await state.choose('20');
    state.reviewed.value = true;
    const saving = state.save();
    await flushPromises();
    await state.save();
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    gate.resolve({ data: accepted(API.saveQueueCalendar.mock.calls[0][2]) });
    await saving;
    await state.save();
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    expect(state.confirmed.value).not.toBeNull();
  });

  it('preserves the same immutable request after uncertain delivery and requires review before explicit recovery', async () => {
    API.saveQueueCalendar.mockRejectedValueOnce(new Error('SYNTHETIC timeout'));
    const { state } = fixture();
    await state.open();
    await state.choose('20');
    state.reviewed.value = true;
    await state.save();
    const body = API.saveQueueCalendar.mock.calls[0][2];
    expect(Object.isFrozen(body)).toBe(true);
    expect(state.error.value).toBe('UNCERTAIN');
    expect(state.reviewed.value).toBe(false);
    await state.save();
    await state.choose('21');
    await state.load(2);
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    state.reviewed.value = true;
    await state.save();
    expect(API.saveQueueCalendar.mock.calls[1][2]).toBe(body);
    expect(state.confirmed.value).not.toBeNull();
  });

  it('blocks a stale conflict until the current queue and calendar are reloaded and reviewed again', async () => {
    API.saveQueueCalendar.mockRejectedValueOnce({ response: { status: 409 } });
    const { state } = fixture();
    await state.open();
    await state.choose('20');
    state.reviewed.value = true;
    await state.save();
    const original = API.saveQueueCalendar.mock.calls[0][2];
    expect(state.error.value).toBe('CONFLICT');
    state.reviewed.value = true;
    await state.save();
    expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    await state.choose('20');
    expect(state.reviewed.value).toBe(false);
    state.reviewed.value = true;
    await state.save();
    expect(API.saveQueueCalendar.mock.calls[1][2].idempotency_key).not.toBe(
      original.idempotency_key
    );
  });

  it.each(['accountId', 'unitId', 'contextKey', 'canManage'])(
    'clears private snapshots immediately when %s changes and ignores a late response',
    async field => {
      const gate = deferred();
      API.unitCalendar.mockImplementationOnce(() => gate.promise);
      const f = fixture();
      await f.state.open();
      const choosing = f.state.choose('20');
      f[field].value =
        field === 'canManage' ? false : 'SYNTHETIC changed context';
      gate.resolve({ data: current() });
      await choosing;
      expect(f.state.active.value).toBe(false);
      expect(f.state.rows.value).toEqual([]);
      expect(f.state.selected.value).toBeNull();
      expect(f.state.proposed.value).toBeNull();
      expect(API.saveQueueCalendar).not.toHaveBeenCalled();
    }
  );

  it.each([401, 403, 404])(
    'forgets private data after a native %s write denial',
    async status => {
      API.saveQueueCalendar.mockRejectedValueOnce({ response: { status } });
      const { state, onDenied } = fixture();
      await state.open();
      await state.choose('20');
      state.reviewed.value = true;
      await state.save();
      expect(onDenied).toHaveBeenCalledOnce();
      expect(state.active.value).toBe(false);
      expect(state.rows.value).toEqual([]);
      expect(state.payload.value).toBeNull();
    }
  );

  it.each([
    'account',
    'unit',
    'queue',
    'calendar',
    'definition',
    'scope',
    'applied',
  ])(
    'does not confirm a mismatched %s receipt or proceed automatically',
    async kind => {
      API.saveQueueCalendar.mockImplementationOnce(
        async (_account, _queue, body) => {
          const data = accepted(body);
          if (kind === 'account') data.account_id = '2';
          if (kind === 'unit') data.unit_id = '11';
          if (kind === 'queue') data.queue_id = '21';
          if (kind === 'calendar')
            data.binding.calendar_snapshot.id =
              '22222222-2222-4222-8222-222222222222';
          if (kind === 'definition')
            data.binding.calendar_snapshot.definition.weekly['1'] = [
              ['10:00', '12:00'],
            ];
          if (kind === 'scope') data.binding.scope_snapshot.queue_id = '21';
          if (kind === 'applied') data.pabx_confirmed = true;
          return { data };
        }
      );
      const { state } = fixture();
      await state.open();
      await state.choose('20');
      state.reviewed.value = true;
      await state.save();
      expect(state.confirmed.value).toBeNull();
      expect(state.error.value).toBe('UNCERTAIN');
      expect(state.reviewed.value).toBe(false);
      expect(API.saveQueueCalendar).toHaveBeenCalledOnce();
    }
  );

  it('preserves pagination and search parameters without silently binding any listed resource', async () => {
    const { state } = fixture();
    await state.open();
    state.query.value = 'SYNTHETIC filter';
    await state.load(2);
    expect(API.queueCalendars).toHaveBeenLastCalledWith('1', '10', calendarId, {
      page: 2,
      per_page: 20,
      q: 'SYNTHETIC filter',
    });
    expect(state.page.value).toBe(2);
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });

  it('rejects a list that repeats a logical queue identity rather than hiding the duplicate', async () => {
    API.queueCalendars.mockResolvedValueOnce({
      data: {
        account_id: '1',
        unit_id: '10',
        items: [queue(), queue()],
        meta: { page: 1, per_page: 20, total: 2, pages: 1 },
      },
    });
    const { state } = fixture();
    await state.open();
    expect(state.error.value).toBe('LOAD_ERROR');
    expect(state.rows.value).toEqual([]);
    expect(API.saveQueueCalendar).not.toHaveBeenCalled();
  });
});
