import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useIvrCalendarReference } from 'dashboard/routes/dashboard/jrcContactCenter/composables/useIvrCalendarReference';
import { newCalendarDefinition } from 'dashboard/routes/dashboard/jrcContactCenter/helpers/calendarForm';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { unitCalendars: vi.fn(), unitCalendar: vi.fn() },
}));
const item = () => ({
  id: '11111111-1111-4111-8111-111111111111',
  active: true,
  definition: {
    ...newCalendarDefinition('America/Sao_Paulo'),
    weekly: {
      ...newCalendarDefinition('America/Sao_Paulo').weekly,
      1: [['08:00', '12:00']],
    },
    name: 'SYNTHETIC native calendar',
  },
});
const list = () => ({
  data: {
    account_id: '1',
    unit_id: '7',
    local_only: true,
    pabx_confirmed: false,
    revision: 'a'.repeat(64),
    items: [item()],
    meta: { page: 1, per_page: 20, total: 1, pages: 1 },
  },
});
const detail = () => ({
  data: {
    ...list().data,
    item: item(),
    ivr_reference: {
      calendar_id: item().id,
      unit_revision: 'a'.repeat(64),
      sha256: 'b'.repeat(64),
      snapshot: item(),
    },
  },
});
const mountPicker = () => {
  const accountId = ref('1');
  const unitId = ref('7');
  const disabled = ref(false);
  const onConfirm = vi.fn();
  const onDenied = vi.fn();
  let picker;
  const wrapper = mount(
    defineComponent({
      setup() {
        picker = useIvrCalendarReference({
          accountId,
          unitId,
          disabled,
          onConfirm,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  return { picker, wrapper, accountId, unitId, disabled, onConfirm, onDenied };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.unitCalendars.mockResolvedValue(list());
  API.unitCalendar.mockResolvedValue(detail());
});

describe('native-calendar selector client guards; HTTP mocked, not server authorization proof', () => {
  it('requires fresh native detail and explicit review before changing the graph, without saving or publishing', async () => {
    const { picker, onConfirm } = mountPicker();
    await picker.begin();
    expect(API.unitCalendars).toHaveBeenCalledWith('1', '7', {
      page: 1,
      per_page: 20,
      q: '',
      status: 'all',
    });
    await picker.choose(item().id);
    picker.confirm();
    expect(onConfirm).not.toHaveBeenCalled();
    picker.reviewed.value = true;
    picker.confirm();
    expect(onConfirm).toHaveBeenCalledExactlyOnceWith(
      detail().data.ivr_reference
    );
    expect(picker.candidate.value).toBe(null);
    expect(picker.choosing.value).toBe(false);
    expect(API.unitCalendar).toHaveBeenCalledExactlyOnceWith(
      '1',
      '7',
      item().id
    );
  });

  it('uses native totals and bounded page/search parameters and clears an older proposal', async () => {
    const { picker } = mountPicker();
    await picker.begin();
    await picker.choose(item().id);
    picker.reviewed.value = true;
    picker.query.value = 'SYNTHETIC second page';
    const response = list();
    response.data.meta = { page: 2, per_page: 20, total: 21, pages: 2 };
    API.unitCalendars.mockResolvedValueOnce(response);
    await picker.load(2);
    expect(API.unitCalendars.mock.calls.at(-1)[2]).toEqual({
      page: 2,
      per_page: 20,
      q: 'SYNTHETIC second page',
      status: 'all',
    });
    expect(picker.meta.value).toEqual(response.data.meta);
    expect(picker.candidate.value).toBe(null);
    expect(picker.reviewed.value).toBe(false);
  });

  it.each(['account', 'unit', 'disabled', 'unmount'])(
    'discards a late %s response without leaking its proposal',
    async change => {
      const state = mountPicker();
      await state.picker.begin();
      let resolve;
      API.unitCalendar.mockReturnValueOnce(
        new Promise(done => {
          resolve = done;
        })
      );
      const pending = state.picker.choose(item().id);
      if (change === 'account') state.accountId.value = '2';
      if (change === 'unit') state.unitId.value = '8';
      if (change === 'disabled') state.disabled.value = true;
      if (change === 'unmount') state.wrapper.unmount();
      resolve(detail());
      await pending;
      await flushPromises();
      expect(state.picker.candidate.value).toBe(null);
      expect(state.picker.rows.value).toEqual([]);
      expect(state.onConfirm).not.toHaveBeenCalled();
    }
  );

  it.each([401, 403, 404])(
    'clears exposed choices and notifies the editor after native denial %i',
    async status => {
      const { picker, onDenied } = mountPicker();
      await picker.begin();
      API.unitCalendar.mockRejectedValueOnce({ response: { status } });
      await picker.choose(item().id);
      expect(picker.rows.value).toEqual([]);
      expect(picker.candidate.value).toBe(null);
      expect(picker.error.value).toBe('DENIED');
      expect(onDenied).toHaveBeenCalledOnce();
    }
  );

  it.each(['account', 'unit', 'provider', 'snapshot', 'revision'])(
    'rejects contradictory %s native detail rather than installing it',
    async kind => {
      const { picker, onConfirm } = mountPicker();
      await picker.begin();
      const response = detail();
      if (kind === 'account') response.data.account_id = '2';
      if (kind === 'unit') response.data.unit_id = '8';
      if (kind === 'provider') response.data.pabx_confirmed = true;
      if (kind === 'snapshot')
        response.data.ivr_reference.snapshot.definition.name =
          'SYNTHETIC contradictory snapshot';
      if (kind === 'revision')
        response.data.ivr_reference.unit_revision = 'c'.repeat(64);
      API.unitCalendar.mockResolvedValueOnce(response);
      await picker.choose(item().id);
      expect(picker.error.value).toBe('LOAD_ERROR');
      expect(picker.candidate.value).toBe(null);
      expect(onConfirm).not.toHaveBeenCalled();
    }
  );

  it.each([
    'duplicates',
    'wrong-page',
    'wrong-size',
    'invalid-definition',
    'foreign-unit',
  ])('rejects an invalid %s list before exposing rows', async kind => {
    const { picker } = mountPicker();
    const response = list();
    if (kind === 'duplicates') response.data.items.push(item());
    if (kind === 'wrong-page') response.data.meta.page = 2;
    if (kind === 'wrong-size') response.data.meta.per_page = 50;
    if (kind === 'invalid-definition')
      response.data.items[0].definition.weekly['1'] = [['12:00', '08:00']];
    if (kind === 'foreign-unit') response.data.unit_id = '8';
    API.unitCalendars.mockResolvedValueOnce(response);
    await picker.begin();
    expect(picker.error.value).toBe('LOAD_ERROR');
    expect(picker.rows.value).toEqual([]);
  });

  it('does not request an arbitrary calendar id absent from the authorized page', async () => {
    const { picker } = mountPicker();
    await picker.begin();
    await picker.choose('22222222-2222-4222-8222-222222222222');
    expect(API.unitCalendar).not.toHaveBeenCalled();
  });

  it('keeps failure visible and permits an explicit retry without automatically repeating the read', async () => {
    const { picker } = mountPicker();
    API.unitCalendars.mockRejectedValueOnce(
      new Error('SYNTHETIC network interruption')
    );
    await picker.begin();
    expect(picker.error.value).toBe('LOAD_ERROR');
    expect(API.unitCalendars).toHaveBeenCalledOnce();
    await picker.load(1);
    expect(picker.error.value).toBe('');
    expect(picker.rows.value).toHaveLength(1);
  });
});
