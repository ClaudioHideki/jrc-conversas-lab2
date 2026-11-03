import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { errorMessage } from './copy';

const fields = [
  'q',
  'relationship_type',
  'segment',
  'owner_id',
  'city',
  'active',
  'economic_group',
  'parent_company_id',
];
const scalar = value =>
  String(Array.isArray(value) ? value[0] || '' : value || '');

export function useCompanyDirectory() {
  const route = useRoute();
  const router = useRouter();
  const { accountId, identity } = useCustomerMaster();
  const rows = ref([]);
  const metadata = ref({ owners: [] });
  const meta = ref({ total: 0 });
  const error = ref('');
  const busy = ref(false);
  const creating = ref(false);
  const selection = ref(null);
  const filters = reactive(Object.fromEntries(fields.map(name => [name, ''])));
  const page = computed(() =>
    Math.min(10000, Math.max(1, Math.trunc(Number(route.query.page)) || 1))
  );
  let generation = 0;
  let controller;
  const load = async () => {
    generation += 1;
    const token = generation;
    controller?.abort();
    controller = new AbortController();
    rows.value = [];
    metadata.value = { owners: [] };
    meta.value = { total: 0 };
    error.value = '';
    busy.value = true;
    const options = { accountId: accountId.value, signal: controller.signal };
    const applied = Object.fromEntries(
      fields.map(name => [name, scalar(route.query[name])])
    );
    try {
      const [result, directory] = await Promise.all([
        API.companies({ ...applied, page: page.value }, options),
        API.metadata(options),
      ]);
      if (token !== generation) return false;
      rows.value = result.data.payload;
      meta.value = result.data.meta;
      metadata.value = directory.data;
      return true;
    } catch (failure) {
      if (token !== generation) return false;
      selection.value = null;
      creating.value = false;
      error.value = errorMessage(failure);
      return false;
    } finally {
      if (token === generation) busy.value = false;
    }
  };
  const search = () => {
    const unchanged =
      page.value === 1 &&
      fields.every(name => scalar(route.query[name]) === scalar(filters[name]));
    if (unchanged) return load();
    const query = { ...route.query, page: '1' };
    fields.forEach(name => {
      query[name] = scalar(filters[name]) || undefined;
    });
    return router.replace({ query });
  };
  const changePage = value =>
    router.replace({ query: { ...route.query, page: String(value) } });
  const closeEditor = () => {
    creating.value = false;
    if (route.query.create === '1')
      router.replace({ query: { ...route.query, create: undefined } });
  };
  const saved = async company => {
    closeEditor();
    selection.value = company.id;
    await load();
  };
  watch(identity, () => {
    selection.value = null;
    creating.value = false;
  });
  watch(
    [identity, () => JSON.stringify(route.query)],
    () => {
      fields.forEach(name => {
        filters[name] = scalar(route.query[name]);
      });
      if (route.query.create === '1') creating.value = true;
      load();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    generation += 1;
    controller?.abort();
    rows.value = [];
    metadata.value = { owners: [] };
    selection.value = null;
  });
  return {
    identity,
    rows,
    metadata,
    meta,
    page,
    error,
    busy,
    creating,
    selection,
    filters,
    search,
    changePage,
    closeEditor,
    saved,
    load,
  };
}
