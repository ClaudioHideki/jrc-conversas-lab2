import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const sha256 = async bytes => {
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash), value =>
    value.toString(16).padStart(2, '0')
  ).join('');
};
const descriptor = row => ({
  audio_asset_id: row.assetId,
  audio_version_id: row.versionId,
  inspection_id: row.inspectionId,
  sha256: row.sha256,
});
const selectionBytes = rows =>
  new TextEncoder().encode(
    JSON.stringify(
      rows
        .map(descriptor)
        .map(row =>
          Object.fromEntries(
            Object.entries(row).sort(([a], [b]) => a.localeCompare(b))
          )
        )
    )
  );

// A bounded download in the existing private library; every source is reauthorized server-side.
export const useAudioArchive = ({
  accountId,
  unitId,
  canManage,
  contextKey,
  limits,
  onDenied,
}) => {
  const dialog = ref(null);
  const items = ref([]);
  const opening = ref(false);
  const downloading = ref(false);
  const error = ref('');
  const reviewed = ref(false);
  const verified = ref(false);
  const delivered = ref(false);
  const usages = ref({});
  let generation = 0;
  let url = '';
  const total = computed(() =>
    items.value.reduce((sum, row) => sum + row.byteSize, 0)
  );
  const admitted = computed(
    () =>
      canManage.value &&
      items.value.length > 0 &&
      items.value.length <= limits.value.max_entries &&
      total.value <= limits.value.max_bytes
  );
  const busy = computed(() => opening.value || downloading.value);
  const canDownload = computed(
    () => admitted.value && verified.value && reviewed.value && !busy.value
  );
  const revoke = () => {
    if (url) URL.revokeObjectURL(url);
    url = '';
  };
  const clear = () => {
    generation += 1;
    revoke();
    items.value = [];
    opening.value = false;
    downloading.value = false;
    reviewed.value = false;
    verified.value = false;
    delivered.value = false;
    usages.value = {};
    error.value = '';
  };
  const close = () => {
    clear();
    dialog.value?.close();
  };
  const ready = row => {
    const version = row.latest_version;
    const proof = version?.technical_verification;
    return (
      row.unit_id === unitId.value &&
      proof?.ready === true &&
      typeof proof.id === 'string' &&
      /^[a-f0-9]{64}$/.test(version.sha256) &&
      Number.isSafeInteger(version.byte_size) &&
      version.byte_size > 0
    );
  };
  const selected = row => items.value.some(item => item.assetId === row.id);
  const selectable = row => {
    if (!canManage.value || busy.value || !ready(row)) return false;
    return (
      selected(row) ||
      (items.value.length < limits.value.max_entries &&
        total.value + row.latest_version.byte_size <= limits.value.max_bytes)
    );
  };
  const toggle = row => {
    if (!selectable(row)) return;
    generation += 1;
    revoke();
    reviewed.value = false;
    verified.value = false;
    delivered.value = false;
    usages.value = {};
    error.value = '';
    if (selected(row))
      items.value = items.value.filter(item => item.assetId !== row.id);
    else
      items.value = [
        ...items.value,
        Object.freeze({
          assetId: row.id,
          versionId: row.latest_version.id,
          inspectionId: row.latest_version.technical_verification.id,
          sha256: row.latest_version.sha256,
          byteSize: row.latest_version.byte_size,
          number: row.latest_version.number,
          name: row.name,
        }),
      ];
  };
  const failed = problem => {
    if ([401, 403, 404].includes(problem?.response?.status)) {
      clear();
      onDenied();
    } else
      error.value =
        problem?.response?.status === 409 || problem?.code === 'SOURCE_CHANGED'
          ? 'SOURCE_CHANGED'
          : 'ERROR';
  };
  const open = async () => {
    if (!admitted.value || busy.value) return;
    generation += 1;
    const current = generation;
    reviewed.value = false;
    verified.value = false;
    delivered.value = false;
    error.value = '';
    revoke();
    dialog.value?.open();
    opening.value = true;
    try {
      await items.value.reduce(
        (chain, item) =>
          chain.then(async () => {
            if (current !== generation) return;
            const response = await API.audioAsset(
              accountId.value,
              item.assetId
            );
            if (current !== generation) return;
            const row = response.data.item;
            const valid =
              String(response.data.account_id) === String(accountId.value) &&
              row?.id === item.assetId &&
              ready(row) &&
              row.latest_version.id === item.versionId &&
              row.latest_version.technical_verification.id ===
                item.inspectionId &&
              row.latest_version.sha256 === item.sha256 &&
              row.latest_version.byte_size === item.byteSize;
            if (!valid) {
              const problem = new Error(
                'Selected institutional source changed'
              );
              problem.code = 'SOURCE_CHANGED';
              throw problem;
            }
            const usage = await API.audioUsages(accountId.value, item.assetId, {
              page: 1,
              per_page: 1,
            });
            if (current !== generation) return;
            const data = usage.data;
            const validUsage =
              String(data.account_id) === String(accountId.value) &&
              data.audio_asset_id === item.assetId &&
              data.unit_id === unitId.value &&
              data.coverage === 'current_local_ivr_drafts_only' &&
              data.provider_configuration_verified === false &&
              Number.isSafeInteger(data.meta?.total) &&
              data.meta.total >= 0;
            if (!validUsage)
              throw new Error('Invalid authorized local reference check');
            usages.value = { ...usages.value, [item.assetId]: data.meta.total };
          }),
        Promise.resolve()
      );
      if (current === generation) verified.value = true;
    } catch (problem) {
      if (current === generation) failed(problem);
    } finally {
      if (current === generation) opening.value = false;
    }
  };
  const download = async () => {
    if (!canDownload.value) return;
    const current = generation;
    downloading.value = true;
    error.value = '';
    delivered.value = false;
    revoke();
    try {
      const selection = await sha256(selectionBytes(items.value));
      if (current !== generation) return;
      const response = await API.audioArchive(
        accountId.value,
        items.value.map(descriptor)
      );
      if (current !== generation) return;
      const headers = response.headers;
      const data = response.data;
      const valid =
        headers['x-jrc-audio-account'] === String(accountId.value) &&
        headers['x-jrc-audio-unit'] === unitId.value &&
        headers['x-jrc-audio-selection'] === selection &&
        headers['x-jrc-audio-count'] === String(items.value.length) &&
        data instanceof Blob &&
        data.size > 0 &&
        headers['x-jrc-audio-bytes'] === String(data.size) &&
        data.type.split(';', 1)[0].trim() === 'application/zip' &&
        data.size <= total.value + 131072;
      if (!valid) throw new Error('Invalid private archive identity');
      const hash = await sha256(await data.arrayBuffer());
      if (current !== generation) return;
      if (hash !== headers['x-jrc-audio-sha256'])
        throw new Error('Invalid private archive integrity');
      url = URL.createObjectURL(data);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'audios-institucionais.zip';
      link.click();
      delivered.value = true;
    } catch (problem) {
      if (current === generation) {
        failed(problem);
        reviewed.value = false;
        verified.value = false;
      }
    } finally {
      if (current === generation) downloading.value = false;
    }
  };
  watch([accountId, unitId, canManage, contextKey], close, { flush: 'sync' });
  onBeforeUnmount(clear);
  return {
    dialog,
    items,
    total,
    error,
    reviewed,
    verified,
    delivered,
    usages,
    busy,
    opening,
    downloading,
    admitted,
    canDownload,
    selected,
    selectable,
    toggle,
    open,
    download,
    clear,
    close,
  };
};
