import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

// Folder metadata only. An uncertain response requires fresh review, never automatic replay.
export const useSelectedAudioMove = ({
  accountId,
  unitId,
  canManage,
  contextKey,
  selection,
  onDenied,
  onSaved,
}) => {
  const dialog = ref(null);
  const items = ref([]);
  const folderId = ref('');
  const folderLoading = ref(false);
  const reviewed = ref(false);
  const verified = ref(false);
  const opening = ref(false);
  const saving = ref(false);
  const error = ref('');
  const usages = ref({});
  let generation = 0;
  const busy = computed(() => opening.value || saving.value);
  const canOpen = computed(
    () =>
      canManage.value &&
      selection.value.length > 0 &&
      selection.value.length <= 20 &&
      selection.value.every(
        row =>
          typeof row.revision === 'string' &&
          /^[a-f0-9]{64}$/.test(row.revision)
      )
  );
  const canSave = computed(
    () =>
      canManage.value &&
      items.value.length > 0 &&
      verified.value &&
      reviewed.value &&
      !folderLoading.value &&
      !busy.value
  );
  const clear = () => {
    generation += 1;
    items.value = [];
    folderId.value = '';
    folderLoading.value = false;
    reviewed.value = false;
    verified.value = false;
    opening.value = false;
    saving.value = false;
    error.value = '';
    usages.value = {};
  };
  const close = () => {
    clear();
    dialog.value?.close();
  };
  const failed = problem => {
    if ([401, 403, 404].includes(problem?.response?.status)) {
      close();
      onDenied();
    } else
      error.value =
        problem?.response?.status === 409 || problem?.code === 'SOURCE_CHANGED'
          ? 'SOURCE_CHANGED'
          : 'ERROR';
  };
  const versionMatches = (row, item) =>
    item.versionId === undefined
      ? row.latest_version === null
      : row.latest_version?.id === item.versionId &&
        row.latest_version?.sha256 === item.sha256;
  const open = async () => {
    if (!canOpen.value || busy.value) return;
    clear();
    const current = generation;
    items.value = selection.value.map(row => Object.freeze({ ...row }));
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
              row.unit_id === unitId.value &&
              row.revision === item.revision &&
              versionMatches(row, item);
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
  const save = async () => {
    if (!canSave.value) return;
    const current = generation;
    const destination = folderId.value || null;
    saving.value = true;
    error.value = '';
    try {
      const response = await API.moveAudioAssets(accountId.value, {
        unit_id: unitId.value,
        folder_id: destination,
        items: items.value.map(item => ({
          audio_asset_id: item.assetId,
          expected_revision: item.revision,
        })),
      });
      if (current !== generation) return;
      const rows = response.data.items;
      const valid =
        String(response.data.account_id) === String(accountId.value) &&
        Array.isArray(rows) &&
        rows.length === items.value.length &&
        new Set(rows.map(row => row.id)).size === rows.length &&
        items.value.every(item =>
          rows.some(
            row =>
              row.id === item.assetId &&
              row.unit_id === unitId.value &&
              row.folder_id === destination &&
              /^[a-f0-9]{64}$/.test(row.revision) &&
              versionMatches(row, item)
          )
        );
      if (!valid)
        throw new Error('Invalid institutional metadata move receipt');
      close();
      onSaved(rows);
    } catch (problem) {
      if (current === generation) {
        failed(problem);
        verified.value = false;
        reviewed.value = false;
      }
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch(
    folderId,
    () => {
      reviewed.value = false;
    },
    { flush: 'sync' }
  );
  watch([accountId, unitId, canManage, contextKey, selection], close, {
    flush: 'sync',
  });
  onBeforeUnmount(clear);
  return {
    dialog,
    items,
    folderId,
    folderLoading,
    reviewed,
    verified,
    opening,
    saving,
    error,
    usages,
    busy,
    canOpen,
    canSave,
    open,
    save,
    clear,
    close,
  };
};
