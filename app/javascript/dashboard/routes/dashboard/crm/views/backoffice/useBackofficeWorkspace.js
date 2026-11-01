import { onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';

export function useBackofficeWorkspace(view, initial = {}) {
  const route = useRoute();
  const filters = reactive({
    q: '',
    status: 'active',
    stage: '',
    priority: '',
    kind: '',
    owner_id: '',
    operations_queue_id: '',
    business_unit_id: '',
    overdue: '',
    sort: 'recent',
    page: 1,
    per_page: 20,
    ...initial,
  });
  const result = ref(null);
  const options = ref({ queues: [], owners: [], business_units: [] });
  const loading = ref(false);
  const error = ref(false);
  let sequence = 0;
  const load = async (page = filters.page) => {
    filters.page = page;
    sequence += 1;
    const request = sequence;
    result.value = null;
    loading.value = true;
    error.value = false;
    try {
      const { data } = await backofficeAPI.workspace({ ...filters, view });
      if (request !== sequence) return;
      result.value = data;
      options.value = data.options;
      filters.page = data.meta.page;
    } catch {
      if (request === sequence) {
        error.value = true;
        options.value = { queues: [], owners: [], business_units: [] };
      }
    } finally {
      if (request === sequence) loading.value = false;
    }
  };
  watch(
    () => route.params.accountId,
    () => {
      options.value = { queues: [], owners: [], business_units: [] };
      load(1);
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    sequence += 1;
  });
  return { filters, result, options, loading, error, load };
}
