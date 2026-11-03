import { ref, reactive, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { errorMessage } from './copy';

export function useCustomerImports() {
  const { accountId, identity, date } = useCustomerMaster();
  const route = useRoute();
  const router = useRouter();
  const metadata = ref(null);
  const run = ref(null);
  const source = ref(null);
  const file = ref(null);
  const kind = ref('companies');
  const delimiter = ref('');
  const mapping = ref({});
  const options = reactive({
    existing: 'skip',
    confirmations: { reassignment: false, primary_change: false },
  });
  const preview = ref(null);
  const tab = ref('file');
  const busy = ref(false);
  const error = ref('');
  const history = ref({
    payload: [],
    meta: { page: 1, per_page: 20, total: 0 },
  });
  const filters = reactive({ q: '', kind: '', status: '' });
  const records = ref({
    payload: [],
    meta: { page: 1, per_page: 25, total: 0 },
  });
  const resultView = ref('rows');
  const refresh = ref(0);
  const canImport = computed(() =>
    Boolean(metadata.value?.available_kinds.length)
  );
  let epoch = 0;
  let controller;
  let active = true;
  const requestOptions = () => ({
    accountId: accountId.value,
    signal: controller?.signal,
  });

  const perform = async callback => {
    if (busy.value) return;
    const current = epoch;
    busy.value = true;
    error.value = '';
    try {
      await callback(() => active && current === epoch);
    } catch (failure) {
      if (active && current === epoch) error.value = errorMessage(failure);
    } finally {
      if (active && current === epoch) busy.value = false;
    }
  };
  const loadRecords = async (page = 1) => {
    const { data } = await API.importRecords(
      run.value.id,
      resultView.value,
      { page, per_page: 25 },
      requestOptions()
    );
    return data;
  };
  const pageRecords = (page = 1) =>
    perform(async valid => {
      const data = await loadRecords(page);
      if (valid()) records.value = data;
    });
  const showResult = view =>
    perform(async valid => {
      resultView.value = view;
      const data = await loadRecords();
      if (valid()) records.value = data;
    });
  const loadHistory = (page = 1) =>
    perform(async valid => {
      const { data } = await API.importRuns(
        { ...filters, page, per_page: 20 },
        requestOptions()
      );
      if (valid()) {
        history.value = data;
        tab.value = 'history';
      }
    });
  const openRun = id => {
    if (String(route.query.import_id) === String(id)) {
      refresh.value += 1;
      return Promise.resolve();
    }
    return router.push({ query: { ...route.query, import_id: id } });
  };
  const startNew = () => {
    if (busy.value) return;
    if (route.query.import_id) {
      const query = { ...route.query };
      delete query.import_id;
      router.push({ query });
    } else refresh.value += 1;
  };
  watch(
    [identity, () => route.query.import_id, refresh],
    () => {
      epoch += 1;
      controller?.abort();
      controller = new AbortController();
      busy.value = false;
      metadata.value = null;
      run.value = null;
      source.value = null;
      file.value = null;
      mapping.value = {};
      preview.value = null;
      Object.assign(filters, { q: '', kind: '', status: '' });
      history.value = {
        payload: [],
        meta: { page: 1, per_page: 20, total: 0 },
      };
      records.value = {
        payload: [],
        meta: { page: 1, per_page: 25, total: 0 },
      };
      tab.value = 'file';
      perform(async valid => {
        const { data } = await API.importMetadata(requestOptions());
        if (!valid()) return;
        metadata.value = data;
        kind.value = data.available_kinds.includes(route.query.kind)
          ? route.query.kind
          : data.available_kinds[0] || '';
        if (!route.query.import_id || !canImport.value) return;
        const detail = (
          await API.importRun(route.query.import_id, requestOptions())
        ).data;
        if (!valid()) return;
        run.value = detail.payload;
        kind.value = detail.payload.kind;
        if (detail.payload.can_review) {
          source.value = detail.file;
          mapping.value = detail.column_mapping;
          options.existing = detail.import_options.existing;
          Object.assign(
            options.confirmations,
            { reassignment: false, primary_change: false },
            detail.import_options.confirmations
          );
          tab.value = 'mapping';
        } else {
          tab.value = 'result';
          resultView.value = 'rows';
          const values = await loadRecords();
          if (valid()) records.value = values;
        }
      });
    },
    { immediate: true }
  );
  watch(
    [mapping, options],
    () => {
      preview.value = null;
    },
    { deep: true }
  );
  onBeforeUnmount(() => {
    active = false;
    controller?.abort();
  });

  const upload = () =>
    perform(async valid => {
      if (!file.value || !canImport.value) return;
      const { data } = await API.uploadImport(
        file.value,
        kind.value,
        delimiter.value,
        requestOptions()
      );
      if (valid()) await openRun(data.payload.id);
    });
  const inspect = () =>
    perform(async valid => {
      preview.value = null;
      const { data } = await API.previewImport(
        run.value.id,
        { column_mapping: mapping.value, import_options: options },
        requestOptions()
      );
      if (!valid()) return;
      preview.value = data;
      run.value = data.payload;
      tab.value = 'preview';
    });
  const apply = () =>
    perform(async valid => {
      if (!preview.value?.token) return;
      const { data } = await API.applyImport(
        run.value.id,
        preview.value.token,
        requestOptions()
      );
      if (!valid()) return;
      run.value = data.payload;
      preview.value = null;
      source.value = null;
      mapping.value = {};
      tab.value = 'result';
      resultView.value = 'rows';
      const values = await loadRecords();
      if (valid()) records.value = values;
    });
  const download = async (response, filename) => {
    const url = URL.createObjectURL(response.data);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  };
  const template = () =>
    perform(async valid => {
      const response = await API.importTemplate(kind.value, requestOptions());
      if (valid()) await download(response, `jrc-${kind.value}-modelo.csv`);
    });
  const exportErrors = () =>
    perform(async valid => {
      const response = await API.importErrorsFile(
        run.value.id,
        requestOptions()
      );
      if (valid())
        await download(response, `jrc-import-${run.value.id}-erros.csv`);
    });
  return {
    metadata,
    run,
    source,
    file,
    kind,
    delimiter,
    mapping,
    options,
    preview,
    tab,
    busy,
    error,
    history,
    filters,
    records,
    resultView,
    canImport,
    date,
    identity,
    upload,
    inspect,
    apply,
    template,
    exportErrors,
    loadHistory,
    openRun,
    startNew,
    pageRecords,
    showResult,
  };
}
