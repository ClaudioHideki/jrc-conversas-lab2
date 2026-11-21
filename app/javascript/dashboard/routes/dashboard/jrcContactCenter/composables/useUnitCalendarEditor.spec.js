import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useUnitCalendarEditor } from './useUnitCalendarEditor';
import { newCalendarDefinition } from '../helpers/calendarForm';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    unitCalendars: vi.fn(),
    unitCalendar: vi.fn(),
    saveUnitCalendar: vi.fn(),
    configurationRecord: vi.fn(),
  },
}));
const id = '11111111-1111-4111-8111-111111111111';
const original = 'a'.repeat(64);
const refreshed = 'b'.repeat(64);
const definition = () => ({
  ...newCalendarDefinition('America/Sao_Paulo'),
  name: 'SYNTHETIC named calendar',
  weekly: Object.fromEntries(
    [1, 2, 3, 4, 5, 6, 7].map(day => [
      String(day),
      day < 6 ? [['08:00', '12:00']] : [],
    ])
  ),
});
const row = () => ({ id, active: false, definition: definition() });
const scope = (overrides = {}) => ({
  account_id: '1',
  unit_id: '10',
  unit_timezone: 'America/Sao_Paulo',
  revision: original,
  local_only: true,
  pabx_confirmed: false,
  ...overrides,
});
const catalog = items => ({
  data: scope({ items, meta: { total: items.length } }),
});
const receipt = item => ({ data: scope({ item, revision: refreshed }) });
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const timezone = ref('America/Sao_Paulo');
  const contextKey = ref('SYNTHETIC profile');
  const canManage = ref(true);
  const onDenied = vi.fn();
  const onSaved = vi.fn();
  let state;
  mount(
    defineComponent({
      setup() {
        state = useUnitCalendarEditor({
          accountId,
          unitId,
          timezone,
          contextKey,
          canManage,
          onDenied,
          onSaved,
        });
        return () => h('div');
      },
    })
  );
  state.dialog.value = { open: vi.fn(), close: vi.fn() };
  return { state, accountId, unitId, contextKey, canManage, onDenied, onSaved };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.unitCalendars.mockResolvedValue(catalog([]));
  API.unitCalendar.mockResolvedValue({ data: scope({ item: row() }) });
  API.saveUnitCalendar.mockImplementation(async (_account, _unit, item) =>
    receipt(item)
  );
});

describe('native calendar editor lifecycle with the real optional revision hook; mocked API, no persistence proof', () => {
  it('does not silently reuse an old unit timezone after a concurrent change of the native unit default', async () => {
    API.unitCalendars.mockResolvedValueOnce({
      data: scope({ unit_timezone: 'UTC', items: [], meta: { total: 0 } }),
    });
    const { state } = fixture();
    await state.open();
    expect(state.error.value).toBe('LOAD_ERROR');
    expect(state.draft.value).toBeNull();
    expect(state.active.value).toBe(false);
    expect(API.saveUnitCalendar).not.toHaveBeenCalled();
  });

  it('normalizes every explicitly named field before sending without changing dates, categories or hours', async () => {
    const { state, onSaved } = fixture();
    await state.open(id);
    state.draft.value.definition.name = '  SYNTHETIC named calendar  ';
    state.draft.value.definition.holidays = [
      {
        date: '2026-11-23',
        name: '  SYNTHETIC holiday  ',
        kind: 'internal',
        type: 'movable',
      },
    ];
    state.draft.value.definition.exceptions = [
      {
        date: '2026-11-23',
        name: '  SYNTHETIC duty  ',
        intervals: [['10:00', '11:00']],
      },
    ];
    state.reviewed.value = true;
    await state.save();
    expect(API.saveUnitCalendar.mock.calls[0][2].definition).toMatchObject({
      name: 'SYNTHETIC named calendar',
      holidays: [
        {
          date: '2026-11-23',
          name: 'SYNTHETIC holiday',
          kind: 'internal',
          type: 'movable',
        },
      ],
      exceptions: [
        {
          date: '2026-11-23',
          name: 'SYNTHETIC duty',
          intervals: [['10:00', '11:00']],
        },
      ],
    });
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it('does not accept valid-looking returned hours that differ from what the human reviewed', async () => {
    const { state, onSaved } = fixture();
    await state.open(id);
    API.saveUnitCalendar.mockImplementationOnce(
      async (_account, _unit, item) => {
        const changed = structuredClone(item);
        changed.definition.weekly['1'] = [['09:00', '12:00']];
        return receipt(changed);
      }
    );
    state.reviewed.value = true;
    await state.save();
    expect(onSaved).not.toHaveBeenCalled();
    expect(state.uncertain.value).toBe(true);
    expect(state.active.value).toBe(true);
    expect(state.draft.value.definition.weekly['1']).toEqual([
      ['08:00', '12:00'],
    ]);
  });

  it('starts an inactive private draft with explicit native unit timezone and requires valid hours and review', async () => {
    const { state } = fixture();
    await state.open();
    expect(state.active.value).toBe(true);
    expect(state.draft.value).toMatchObject({
      active: false,
      definition: { name: '', timezone: 'America/Sao_Paulo' },
    });
    expect(state.canSave.value).toBe(false);
    state.draft.value.definition = definition();
    await flushPromises();
    state.reviewed.value = true;
    expect(state.canSave.value).toBe(true);
    await state.save();
    expect(API.saveUnitCalendar).toHaveBeenCalledWith(
      '1',
      '10',
      expect.objectContaining({ active: false }),
      original,
      false
    );
    expect(state.active.value).toBe(false);
  });

  it('accepts the identical native JSONB content despite object key order and requires normalized metadata', async () => {
    const { state, onSaved } = fixture();
    await state.open(id);
    API.saveUnitCalendar.mockImplementationOnce(async (_account, _unit, item) =>
      receipt({
        ...item,
        definition: Object.fromEntries(
          Object.entries(item.definition).reverse()
        ),
      })
    );
    state.reviewed.value = true;
    await state.save();
    expect(onSaved).toHaveBeenCalledOnce();
    expect(state.error.value).toBe('');
    expect(state.active.value).toBe(false);
  });

  it('preserves the reviewed draft on a stale native revision and reloads through the scoped optional loader', async () => {
    const { state } = fixture();
    await state.open(id);
    state.draft.value.definition.name = 'SYNTHETIC local preserved';
    state.reviewed.value = true;
    API.saveUnitCalendar.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    await state.save();
    expect(state.draft.value.definition.name).toBe('SYNTHETIC local preserved');
    expect(state.revision.state.conflict).toBe(true);
    expect(state.canSave.value).toBe(false);
    API.unitCalendars.mockResolvedValueOnce({
      data: { ...catalog([row()]).data, revision: refreshed },
    });
    await state.revision.reload();
    expect(API.configurationRecord).not.toHaveBeenCalled();
    expect(API.unitCalendars).toHaveBeenLastCalledWith('1', '10', {
      page: 1,
      per_page: 100,
    });
    expect(state.revision.state.latest).toMatchObject({
      id,
      present: true,
      definition: { name: 'SYNTHETIC named calendar' },
    });
    state.revision.review(true);
    state.reviewed.value = true;
    expect(state.canSave.value).toBe(true);
    state.draft.value.definition.description = 'SYNTHETIC changed after review';
    expect(state.reviewed.value).toBe(false);
    expect(state.canSave.value).toBe(false);
  });

  it('keeps one identity after an unknown response and blocks retry until a current explicit review', async () => {
    const { state, onSaved } = fixture();
    await state.open();
    state.draft.value.definition = definition();
    state.reviewed.value = true;
    const identity = state.draft.value.id;
    API.saveUnitCalendar.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    await state.save();
    expect(state.uncertain.value).toBe(true);
    expect(state.draft.value.id).toBe(identity);
    expect(state.canSave.value).toBe(false);
    await state.save();
    expect(API.saveUnitCalendar).toHaveBeenCalledOnce();
    await state.revision.reload();
    expect(state.revision.state.latest).toMatchObject({
      id: identity,
      present: false,
    });
    state.revision.review(true);
    state.reviewed.value = true;
    await state.save();
    expect(API.saveUnitCalendar.mock.calls.map(call => call[2].id)).toEqual([
      identity,
      identity,
    ]);
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it('discards a delayed source when unit or profile changes without disclosing or saving it', async () => {
    let resolve;
    API.unitCalendar.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const { state, unitId, onSaved } = fixture();
    const pending = state.open(id);
    unitId.value = '11';
    resolve({ data: scope({ item: row() }) });
    await pending;
    expect(state.active.value).toBe(false);
    expect(state.draft.value).toBeNull();
    expect(API.saveUnitCalendar).not.toHaveBeenCalled();
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('clears private state when native configuration permission is withdrawn', async () => {
    const { state, canManage, onSaved } = fixture();
    await state.open(id);
    canManage.value = false;
    expect(state.draft.value).toBeNull();
    expect(state.active.value).toBe(false);
    expect(state.canSave.value).toBe(false);
    await state.save();
    expect(API.saveUnitCalendar).not.toHaveBeenCalled();
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('rejects another-account detail response and a native denial without an administrator fallback', async () => {
    const { state, onDenied } = fixture();
    API.unitCalendar.mockResolvedValueOnce({
      data: scope({ account_id: '999', item: row() }),
    });
    await state.open(id);
    expect(state.active.value).toBe(false);
    expect(state.error.value).toBe('LOAD_ERROR');
    API.unitCalendar.mockRejectedValueOnce({ response: { status: 401 } });
    await state.open(id);
    expect(onDenied).toHaveBeenCalledOnce();
    expect(state.draft.value).toBeNull();
  });
});
