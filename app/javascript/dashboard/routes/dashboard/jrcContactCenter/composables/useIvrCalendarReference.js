import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { calendarDefinitionSignature } from '../helpers/calendarForm';
import {
  validIvrCalendarReference,
  validIvrCalendarSnapshot,
} from '../helpers/ivrCalendar';

export const useIvrCalendarReference = ({
  accountId,
  unitId,
  disabled,
  onConfirm,
  onDenied,
}) => {
  const choosing = ref(false);
  const rows = ref([]);
  const query = ref('');
  const page = ref(1);
  const meta = ref({ total: 0, pages: 0 });
  const candidate = ref(null);
  const reviewed = ref(false);
  const loading = ref(false);
  const error = ref('');
  let generation = 0;
  const digest = value =>
    typeof value === 'string' &&
    value.length === 64 &&
    /^[a-f0-9]{64}$/.test(value);
  const context = data =>
    data.account_id === String(accountId.value) &&
    data.unit_id === String(unitId.value) &&
    data.local_only === true &&
    data.pabx_confirmed === false;
  const canConfirm = computed(
    () =>
      choosing.value &&
      !disabled.value &&
      !loading.value &&
      reviewed.value &&
      validIvrCalendarReference(candidate.value)
  );
  const clear = () => {
    generation += 1;
    choosing.value = false;
    rows.value = [];
    meta.value = { total: 0, pages: 0 };
    candidate.value = null;
    reviewed.value = false;
    loading.value = false;
    error.value = '';
  };
  const failure = problem => {
    if ([401, 403, 404].includes(problem?.response?.status)) {
      clear();
      error.value = 'DENIED';
      onDenied();
    } else error.value = 'LOAD_ERROR';
  };
  const load = async (nextPage = 1) => {
    if (!choosing.value || disabled.value || loading.value || !unitId.value)
      return;
    generation += 1;
    const sequence = generation;
    loading.value = true;
    rows.value = [];
    meta.value = { total: 0, pages: 0 };
    candidate.value = null;
    reviewed.value = false;
    error.value = '';
    try {
      const { data } = await API.unitCalendars(accountId.value, unitId.value, {
        page: nextPage,
        per_page: 20,
        q: query.value,
        status: 'all',
      });
      if (sequence !== generation) return;
      if (
        !context(data) ||
        !digest(data.revision) ||
        !Array.isArray(data.items) ||
        data.items.length > 20 ||
        !data.items.every(validIvrCalendarSnapshot) ||
        new Set(data.items.map(row => row.id)).size !== data.items.length ||
        data.meta?.page !== nextPage ||
        data.meta.per_page !== 20 ||
        !Number.isInteger(data.meta.total) ||
        data.meta.total < data.items.length ||
        !Number.isInteger(data.meta.pages) ||
        data.meta.pages < 0
      )
        throw new Error('Invalid native unit calendar list');
      rows.value = data.items;
      meta.value = data.meta;
      page.value = nextPage;
    } catch (problem) {
      if (sequence === generation) failure(problem);
    } finally {
      if (sequence === generation) loading.value = false;
    }
  };
  const begin = async () => {
    if (disabled.value || !unitId.value || choosing.value) return;
    clear();
    query.value = '';
    choosing.value = true;
    await load(1);
  };
  const choose = async id => {
    if (
      !choosing.value ||
      disabled.value ||
      loading.value ||
      !rows.value.some(row => row.id === id)
    )
      return;
    generation += 1;
    const sequence = generation;
    loading.value = true;
    candidate.value = null;
    reviewed.value = false;
    error.value = '';
    try {
      const { data } = await API.unitCalendar(
        accountId.value,
        unitId.value,
        id
      );
      if (sequence !== generation) return;
      const selected = data.ivr_reference;
      if (
        !context(data) ||
        !validIvrCalendarSnapshot(data.item) ||
        !validIvrCalendarReference(selected) ||
        data.item.id !== id ||
        selected.calendar_id !== id ||
        selected.unit_revision !== data.revision ||
        selected.snapshot.active !== data.item.active ||
        calendarDefinitionSignature(selected.snapshot.definition) !==
          calendarDefinitionSignature(data.item.definition)
      )
        throw new Error('Invalid native URA calendar reference');
      candidate.value = JSON.parse(JSON.stringify(selected));
    } catch (problem) {
      if (sequence === generation) failure(problem);
    } finally {
      if (sequence === generation) loading.value = false;
    }
  };
  const confirm = () => {
    if (!canConfirm.value) return;
    const value = JSON.parse(JSON.stringify(candidate.value));
    clear();
    onConfirm(value);
  };
  watch([accountId, unitId, disabled], clear, { flush: 'sync' });
  onBeforeUnmount(clear);
  return {
    choosing,
    rows,
    query,
    page,
    meta,
    candidate,
    reviewed,
    loading,
    error,
    canConfirm,
    begin,
    load,
    choose,
    confirm,
    clear,
  };
};
