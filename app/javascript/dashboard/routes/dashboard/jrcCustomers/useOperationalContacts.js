import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { errorMessage } from './copy';

const fields = ['q', 'status', 'kind', 'days', 'taxonomy_id'];
const scalar = value =>
  String(Array.isArray(value) ? value[0] || '' : value || '');
const valueFor = (query, key) =>
  scalar(query[key]) || (key === 'days' ? '30' : '');

export function useOperationalContacts() {
  const route = useRoute();
  const router = useRouter();
  const { accountId, identity } = useCustomerMaster();
  const rows = ref([]);
  const meta = ref({ total: 0, per_page: 25, days: 30 });
  const error = ref('');
  const busy = ref(false);
  const filters = reactive(
    Object.fromEntries(fields.map(key => [key, valueFor(route.query, key)]))
  );
  const page = computed(() =>
    Math.min(10000, Math.max(1, Math.trunc(Number(route.query.page)) || 1))
  );
  let generation = 0;
  let controller;
  const load = async () => {
    generation += 1;
    const version = generation;
    controller?.abort();
    controller = new AbortController();
    rows.value = [];
    meta.value = { total: 0, per_page: 25, days: 30 };
    error.value = '';
    busy.value = true;
    try {
      const params = Object.fromEntries(
        fields.map(key => [key, valueFor(route.query, key)])
      );
      const result = await API.operationalContacts(
        { ...params, page: page.value },
        { accountId: accountId.value, signal: controller.signal }
      );
      if (version !== generation) return;
      rows.value = result.data.payload;
      meta.value = result.data.meta;
    } catch (failure) {
      if (version === generation) error.value = errorMessage(failure);
    } finally {
      if (version === generation) busy.value = false;
    }
  };
  const search = () => {
    if (
      page.value === 1 &&
      fields.every(key => valueFor(route.query, key) === scalar(filters[key]))
    )
      return load();
    const query = { ...route.query, page: '1' };
    fields.forEach(key => {
      query[key] = scalar(filters[key]) || undefined;
    });
    return router.replace({ query });
  };
  const changePage = value =>
    router.replace({ query: { ...route.query, page: String(value) } });
  watch(
    [identity, () => JSON.stringify(route.query)],
    () => {
      fields.forEach(key => {
        filters[key] = valueFor(route.query, key);
      });
      load();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    generation += 1;
    controller?.abort();
    rows.value = [];
  });
  return {
    identity,
    rows,
    meta,
    error,
    busy,
    filters,
    page,
    search,
    changePage,
    load,
  };
}
