import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const identity = value => typeof value === 'string' && /^[1-9]\d*$/.test(value);
const referenceValid = row =>
  row &&
  typeof row.node_id === 'string' &&
  row.node_id.length > 0 &&
  digest(row.sha256) &&
  digest(row.unit_revision) &&
  [true, false].includes(row.calendar_changed);
const rowValid = (row, unitId) =>
  row &&
  identity(row.draft_id) &&
  identity(row.version_id) &&
  Number.isSafeInteger(row.draft_revision) &&
  row.draft_revision > 0 &&
  typeof row.name === 'string' &&
  ['draft', 'archived'].includes(row.status) &&
  row.unit_id === unitId &&
  row.local_only === true &&
  row.provider_applied === false &&
  Array.isArray(row.references) &&
  row.references.length > 0 &&
  row.references.every(referenceValid) &&
  new Set(row.references.map(item => item.node_id)).size ===
    row.references.length;

export function useCalendarIvrUsages(props, { close, denied }) {
  const opened = ref(false);
  const items = ref([]);
  const meta = ref({ page: 1, pages: 0, total: 0 });
  const page = ref(1);
  const query = ref('');
  const status = ref('all');
  const applied = ref({ q: '', status: 'all' });
  const loading = ref(false);
  const error = ref(false);
  const allowed = computed(() => props.canManage === true);
  let generation = 0;
  const clear = () => {
    generation += 1;
    opened.value = false;
    items.value = [];
    meta.value = { page: 1, pages: 0, total: 0 };
    page.value = 1;
    query.value = '';
    status.value = 'all';
    applied.value = { q: '', status: 'all' };
    loading.value = false;
    error.value = false;
  };
  const load = async target => {
    if (!opened.value || !allowed.value || loading.value) return;
    generation += 1;
    const current = generation;
    page.value = target;
    items.value = [];
    meta.value = { page: target, pages: 0, total: 0 };
    error.value = false;
    loading.value = true;
    try {
      const { data } = await API.calendarIvrUsages(
        props.accountId,
        props.unitId,
        props.calendarId,
        { ...applied.value, page: target, per_page: 10 }
      );
      if (current !== generation || !allowed.value) return;
      if (
        data.account_id !== String(props.accountId) ||
        data.calendar_id !== props.calendarId ||
        data.unit_id !== props.unitId ||
        data.local_only !== true ||
        data.pabx_confirmed !== false ||
        data.coverage !== 'current_local_ivr_drafts_only' ||
        data.provider_configuration_verified !== false ||
        !digest(data.calendar_digest) ||
        !Array.isArray(data.items) ||
        data.items.length > 10 ||
        !data.items.every(item => rowValid(item, props.unitId)) ||
        new Set(data.items.map(item => item.draft_id)).size !==
          data.items.length ||
        data.meta?.page !== target ||
        data.meta?.per_page !== 10 ||
        !Number.isSafeInteger(data.meta?.total) ||
        data.meta.total < data.items.length ||
        data.meta.pages !== Math.ceil(data.meta.total / 10)
      )
        throw new Error('Invalid authorized native calendar usage context');
      items.value = data.items;
      meta.value = data.meta;
    } catch (failure) {
      if (current !== generation) return;
      if ([401, 403, 404].includes(failure?.response?.status)) {
        close();
        clear();
        denied();
      } else error.value = true;
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  const open = () => {
    if (!allowed.value) return false;
    clear();
    opened.value = true;
    load(1);
    return true;
  };
  const filter = () => {
    if (loading.value) return;
    applied.value = { q: query.value, status: status.value };
    load(1);
  };
  const resetFilters = () => {
    query.value = '';
    status.value = 'all';
    filter();
  };
  watch(
    [
      () => props.accountId,
      () => props.unitId,
      () => props.calendarId,
      () => props.contextKey,
      () => props.canManage,
    ],
    () => {
      close();
      clear();
    },
    { flush: 'sync' }
  );
  onBeforeUnmount(clear);
  return {
    opened,
    items,
    meta,
    page,
    query,
    status,
    loading,
    error,
    open,
    clear,
    load,
    filter,
    resetFilters,
  };
}
