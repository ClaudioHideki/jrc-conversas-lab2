import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

// Receipts are server observations of this exact version; they grant no byte access or PABX publication.
export const useAudioInspections = ({
  accountId,
  assetId,
  version,
  canManage,
  onDenied,
}) => {
  const opened = ref(false);
  const items = ref([]);
  const meta = ref({ total: 0, pages: 0 });
  const page = ref(1);
  const loading = ref(false);
  const saving = ref(false);
  const error = ref('');
  let generation = 0;
  let key = '';
  const clear = () => {
    generation += 1;
    opened.value = false;
    items.value = [];
    meta.value = { total: 0, pages: 0 };
    page.value = 1;
    loading.value = false;
    saving.value = false;
    error.value = '';
    key = '';
  };
  const failure = problem => {
    if ([401, 403, 404].includes(problem?.response?.status)) {
      clear();
      onDenied();
    } else error.value = key ? 'UNCERTAIN' : 'ERROR';
  };
  const load = async () => {
    if (!opened.value || !canManage.value || saving.value) return;
    generation += 1;
    const current = generation;
    items.value = [];
    loading.value = true;
    error.value = '';
    try {
      const response = await API.audioInspections(
        accountId.value,
        assetId.value,
        version.value.id,
        { page: page.value, per_page: 5 }
      );
      if (current !== generation) return;
      items.value = response.data.items;
      meta.value = response.data.meta;
    } catch (problem) {
      if (current === generation) failure(problem);
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  const open = () => {
    if (!canManage.value || loading.value || saving.value) return;
    opened.value = !opened.value;
    if (opened.value) load();
  };
  const validReceipt = data => {
    const record = data?.item;
    return (
      String(data?.account_id) === String(accountId.value) &&
      typeof record?.id === 'string' &&
      /^[1-9]\d{0,18}$/.test(record.id) &&
      record.audio_version_id === version.value.id &&
      record.unit_id === version.value.unit_id &&
      record.expected_sha256 === version.value.sha256 &&
      Number.isInteger(record.attempt) &&
      record.attempt > 0
    );
  };
  const inspect = async () => {
    if (!canManage.value || saving.value || loading.value) return;
    const current = generation;
    saving.value = true;
    error.value = '';
    if (!key) key = crypto.randomUUID();
    try {
      const response = await API.inspectAudioVersion(
        accountId.value,
        assetId.value,
        version.value.id,
        key
      );
      if (current !== generation) return;
      if (!validReceipt(response.data))
        throw new Error('Invalid exact-version technical receipt');
      key = '';
      saving.value = false;
      if (page.value !== 1) page.value = 1;
      else await load();
    } catch (problem) {
      if (current === generation) failure(problem);
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch([accountId, assetId, version, canManage], clear);
  watch(page, load);
  onBeforeUnmount(clear);
  return { opened, items, meta, page, loading, saving, error, open, inspect };
};
