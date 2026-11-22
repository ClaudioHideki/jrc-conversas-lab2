import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import {
  calendarDefinitionSignature,
  validCalendarDefinition,
} from '../helpers/calendarForm';

const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const identity = value =>
  typeof value === 'string' && /^[1-9][0-9]{0,18}$/.test(value);
const uuid = value =>
  typeof value === 'string' &&
  /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(
    value
  );
const calendar = value =>
  value &&
  uuid(value.id) &&
  [true, false].includes(value.active) &&
  validCalendarDefinition(value.definition);

export const useQueueCalendarBindings = ({
  accountId,
  unitId,
  calendarId,
  contextKey,
  canManage,
  onDenied,
}) => {
  const dialog = ref(null);
  const active = ref(false);
  const rows = ref([]);
  const page = ref(1);
  const query = ref('');
  const meta = ref({ total: 0, pages: 0 });
  const loading = ref(false);
  const saving = ref(false);
  const error = ref('');
  const selected = ref(null);
  const proposed = ref(null);
  const reviewed = ref(false);
  const payload = ref(null);
  const confirmed = ref(null);
  const selectionLocked = ref(false);
  let generation = 0;
  const busy = computed(() => loading.value || saving.value);
  const canSave = computed(
    () =>
      active.value &&
      canManage.value &&
      !busy.value &&
      !selectionLocked.value &&
      selected.value &&
      proposed.value &&
      reviewed.value &&
      !confirmed.value &&
      error.value !== 'CONFLICT'
  );
  const resetSelection = () => {
    selectionLocked.value = false;
    selected.value = null;
    proposed.value = null;
    reviewed.value = false;
    payload.value = null;
    confirmed.value = null;
  };
  const clear = () => {
    generation += 1;
    active.value = false;
    rows.value = [];
    meta.value = { total: 0, pages: 0 };
    loading.value = false;
    saving.value = false;
    error.value = '';
    resetSelection();
  };
  const forget = () => {
    clear();
    dialog.value?.close();
  };
  const failure = problem => {
    if ([401, 403, 404].includes(problem?.response?.status)) {
      forget();
      onDenied();
    } else error.value = 'LOAD_ERROR';
  };
  const validRow = row => {
    if (
      !row ||
      row.unit_id !== unitId.value ||
      !identity(row.queue_id) ||
      typeof row.queue_name !== 'string' ||
      !digest(row.queue_revision) ||
      row.local_only !== true ||
      row.pabx_confirmed !== false ||
      row.external_impact !== 'unknown' ||
      ![true, false].includes(row.calendar_changed)
    )
      return false;
    const binding = row.binding;
    if (binding === null) return true;
    return (
      binding?.format === 'jrc-cc-queue-calendar-v1' &&
      uuid(binding.id) &&
      calendar(binding.calendar_snapshot) &&
      digest(binding.calendar_digest) &&
      digest(binding.request_digest) &&
      binding.scope_snapshot?.account_id === String(accountId.value) &&
      binding.scope_snapshot.unit_id === unitId.value &&
      binding.scope_snapshot.queue_id === row.queue_id
    );
  };
  const load = async (nextPage = 1) => {
    if (
      !active.value ||
      !canManage.value ||
      busy.value ||
      payload.value ||
      selectionLocked.value
    )
      return;
    generation += 1;
    const current = generation;
    loading.value = true;
    rows.value = [];
    resetSelection();
    error.value = '';
    try {
      const { data } = await API.queueCalendars(
        accountId.value,
        unitId.value,
        calendarId.value,
        { page: nextPage, per_page: 20, q: query.value }
      );
      if (current !== generation) return;
      if (
        data.account_id !== String(accountId.value) ||
        data.unit_id !== unitId.value ||
        !Array.isArray(data.items) ||
        data.items.length > 20 ||
        !data.items.every(validRow) ||
        new Set(data.items.map(row => row.queue_id)).size !==
          data.items.length ||
        data.meta?.page !== nextPage ||
        data.meta.per_page !== 20 ||
        !Number.isInteger(data.meta.total) ||
        data.meta.total < data.items.length ||
        !Number.isInteger(data.meta.pages) ||
        data.meta.pages < 0
      )
        throw new Error('Invalid native queue calendar list');
      rows.value = data.items;
      meta.value = data.meta;
      page.value = nextPage;
    } catch (problem) {
      if (current === generation) failure(problem);
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  const open = async () => {
    if (!canManage.value || active.value) return;
    clear();
    active.value = true;
    query.value = '';
    page.value = 1;
    dialog.value?.open();
    await load();
  };
  const choose = async id => {
    if (
      !active.value ||
      !canManage.value ||
      busy.value ||
      selectionLocked.value ||
      (payload.value && error.value !== 'CONFLICT')
    )
      return;
    generation += 1;
    const current = generation;
    resetSelection();
    loading.value = true;
    error.value = '';
    try {
      const [queue, source] = await Promise.all([
        API.queueCalendar(accountId.value, unitId.value, id),
        API.unitCalendar(accountId.value, unitId.value, calendarId.value),
      ]);
      if (current !== generation) return;
      const data = source.data;
      if (
        queue.data.account_id !== String(accountId.value) ||
        queue.data.queue_id !== id ||
        !validRow(queue.data) ||
        data.account_id !== String(accountId.value) ||
        data.unit_id !== unitId.value ||
        data.local_only !== true ||
        data.pabx_confirmed !== false ||
        !digest(data.revision) ||
        !calendar(data.item) ||
        data.item.id !== calendarId.value
      )
        throw new Error('Invalid current queue calendar context');
      selected.value = queue.data;
      proposed.value = data;
    } catch (problem) {
      if (current === generation) failure(problem);
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  const lockSelection = value => {
    selectionLocked.value = value === true;
    reviewed.value = false;
  };
  const acceptCurrent = row => {
    if (
      !active.value ||
      !canManage.value ||
      row.queue_id !== selected.value?.queue_id ||
      !validRow(row)
    ) {
      forget();
      onDenied();
      return;
    }
    selected.value = row;
    rows.value = rows.value.map(item =>
      item.queue_id === row.queue_id ? row : item
    );
    reviewed.value = false;
  };
  const save = async () => {
    if (!canSave.value) return;
    const current = generation;
    if (!payload.value)
      payload.value = Object.freeze({
        unit_id: unitId.value,
        queue_id: selected.value.queue_id,
        calendar_id: calendarId.value,
        calendar_revision: proposed.value.revision,
        queue_revision: selected.value.queue_revision,
        idempotency_key: crypto.randomUUID(),
        reviewed: true,
      });
    saving.value = true;
    error.value = '';
    try {
      const { data } = await API.saveQueueCalendar(
        accountId.value,
        selected.value.queue_id,
        payload.value
      );
      if (current !== generation) return;
      const snapshot = data.binding?.calendar_snapshot;
      if (
        data.account_id !== String(accountId.value) ||
        data.queue_id !== selected.value.queue_id ||
        !validRow(data) ||
        data.binding?.id !== payload.value.idempotency_key ||
        snapshot?.id !== calendarId.value ||
        snapshot.active !== proposed.value.item.active ||
        calendarDefinitionSignature(snapshot.definition) !==
          calendarDefinitionSignature(proposed.value.item.definition)
      )
        throw new Error('Unverified queue calendar receipt');
      confirmed.value = data;
      selected.value = data;
      rows.value = rows.value.map(row =>
        row.queue_id === data.queue_id ? data : row
      );
    } catch (problem) {
      if (current === generation) {
        if ([401, 403, 404].includes(problem?.response?.status))
          failure(problem);
        else {
          reviewed.value = false;
          error.value =
            problem?.response?.status === 409 ? 'CONFLICT' : 'UNCERTAIN';
        }
      }
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch([accountId, unitId, calendarId, contextKey, canManage], forget, {
    flush: 'sync',
  });
  onBeforeUnmount(clear);
  return {
    dialog,
    active,
    rows,
    page,
    query,
    meta,
    busy,
    error,
    selected,
    proposed,
    reviewed,
    payload,
    confirmed,
    selectionLocked,
    lockSelection,
    validRow,
    acceptCurrent,
    canSave,
    clear,
    open,
    load,
    choose,
    save,
  };
};
