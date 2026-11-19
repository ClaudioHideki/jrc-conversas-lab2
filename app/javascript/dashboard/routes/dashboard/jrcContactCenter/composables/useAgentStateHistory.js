import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

export const emptyStateHistoryFilters = () => ({
  from: '',
  to: '',
  state: '',
  queue_id: '',
  q: '',
});

export const useAgentStateHistory = ({ accountId, enabled }) => {
  const items = ref([]);
  const meta = ref(null);
  const window = ref(null);
  const loading = ref(false);
  const failed = ref(false);
  const filters = ref(emptyStateHistoryFilters());
  let applied = {};
  let generation = 0;
  let active = true;
  const reset = () => {
    generation += 1;
    items.value = [];
    meta.value = null;
    window.value = null;
    loading.value = false;
    failed.value = false;
    filters.value = emptyStateHistoryFilters();
    applied = {};
  };
  const load = async (page = 1) => {
    if (!active || !enabled.value) return;
    generation += 1;
    const version = generation;
    const account = String(accountId.value);
    items.value = [];
    meta.value = null;
    failed.value = false;
    loading.value = true;
    try {
      const response = await API.agentStateHistory(accountId.value, {
        ...applied,
        page,
        per_page: 20,
      });
      if (!active || version !== generation || !enabled.value) return;
      const data = response.data;
      if (
        String(data.account_id) !== account ||
        !Array.isArray(data.items) ||
        data.meta?.page !== page ||
        data.meta?.per_page !== 20 ||
        !data.window?.timezone
      )
        throw new Error('Invalid operational history identity');
      items.value = data.items;
      meta.value = data.meta;
      window.value = data.window;
    } catch {
      if (active && version === generation) failed.value = true;
    } finally {
      if (active && version === generation) loading.value = false;
    }
  };
  const apply = () => {
    if (loading.value) return undefined;
    applied = Object.fromEntries(
      Object.entries(filters.value).filter(([, value]) => value !== '')
    );
    return load(1);
  };
  const clear = () => {
    filters.value = emptyStateHistoryFilters();
    applied = {};
    return load(1);
  };
  watch(
    () => [String(accountId.value), enabled.value],
    () => {
      reset();
      if (enabled.value) load();
    },
    { immediate: true, flush: 'sync' }
  );
  onBeforeUnmount(() => {
    active = false;
    reset();
  });
  return { items, meta, window, filters, loading, failed, load, apply, clear };
};
