import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const identity = value =>
  typeof value === 'string' && /^[1-9][0-9]{0,18}$/.test(value);
const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const sourceMatches = (source, selected, unitId) => {
  const version = source?.latest_version;
  return (
    source?.id === selected.assetId &&
    source.unit_id === unitId &&
    source.revision === selected.revision &&
    version?.id === selected.versionId &&
    version.sha256 === selected.sha256 &&
    version.byte_size === selected.byteSize &&
    version.technical_verification?.id === selected.inspectionId &&
    version.technical_verification.ready === true &&
    ['user_upload', 'browser_capture'].includes(version.source_kind)
  );
};

// Sequential native per-item copies, not a second upload store or an all-or-nothing batch promise.
export const useSelectedAudioCopies = ({
  accountId,
  unitId,
  contextKey,
  canManage,
  admitted,
  selection,
  initialFolderId = ref(''),
  onDenied,
  onSettled,
}) => {
  const dialog = ref(null);
  const active = ref(false);
  const items = ref([]);
  const folderId = ref('');
  const folderLoading = ref(true);
  const opening = ref(false);
  const saving = ref(false);
  const locked = ref(false);
  const verified = ref(false);
  const reviewed = ref(false);
  const error = ref('');
  let generation = 0;
  const busy = computed(() => opening.value || saving.value);
  const allowed = computed(
    () =>
      canManage.value &&
      admitted.value &&
      selection.value.length > 0 &&
      selection.value.length <= 20
  );
  const confirmed = computed(() =>
    items.value.filter(row => row.status === 'confirmed')
  );
  const uncertain = computed(() =>
    items.value.filter(row => row.status === 'uncertain')
  );
  const complete = computed(
    () =>
      items.value.length > 0 && confirmed.value.length === items.value.length
  );
  const fingerprint = computed(() =>
    JSON.stringify([
      folderId.value,
      items.value.map(row => [row.assetId, row.versionId, row.name]),
    ])
  );
  const canSave = computed(
    () =>
      active.value &&
      allowed.value &&
      verified.value &&
      reviewed.value &&
      !busy.value &&
      !folderLoading.value &&
      !complete.value &&
      !items.value.some(row => row.status === 'blocked') &&
      items.value.every(
        row =>
          typeof row.name === 'string' &&
          row.name.trim().length > 0 &&
          row.name.trim().length <= 120 &&
          (!row.payload ||
            (row.payload.asset.name === row.name.trim() &&
              row.payload.asset.folder_id === (folderId.value || '')))
      )
  );
  const clear = () => {
    generation += 1;
    active.value = false;
    items.value = [];
    folderId.value = initialFolderId.value || '';
    folderLoading.value = true;
    opening.value = false;
    saving.value = false;
    locked.value = false;
    reviewed.value = false;
    verified.value = false;
    error.value = '';
  };
  const forget = () => {
    clear();
    dialog.value?.close();
  };
  const dismiss = () => {
    if (busy.value) return;
    const outcome = {
      confirmed: confirmed.value.map(row => ({ ...row.receipt })),
      uncertain: uncertain.value.length,
      blocked: items.value.filter(row => row.status === 'blocked').length,
      pending: items.value.filter(row => row.status === 'pending').length,
    };
    const disclose =
      active.value &&
      canManage.value &&
      (outcome.confirmed.length > 0 ||
        outcome.uncertain > 0 ||
        outcome.blocked > 0);
    clear();
    if (disclose) onSettled(outcome);
  };
  const denied = problem => [401, 403, 404].includes(problem?.response?.status);
  const sourceProblem = () => {
    const problem = new Error('Selected institutional source changed');
    problem.code = 'SOURCE_CHANGED';
    return problem;
  };
  const open = async () => {
    if (!allowed.value || active.value || busy.value) return;
    clear();
    const current = generation;
    active.value = true;
    items.value = selection.value.map(row => ({
      ...row,
      status: 'pending',
      name: row.name,
      origin: null,
      payload: null,
      receipt: null,
    }));
    opening.value = true;
    dialog.value?.open();
    try {
      if (
        new Set(items.value.map(row => row.assetId)).size !== items.value.length
      )
        throw sourceProblem();
      await items.value.reduce(
        (chain, row) =>
          chain.then(async () => {
            if (current !== generation) return;
            const response = await API.audioAsset(accountId.value, row.assetId);
            if (current !== generation) return;
            const source = response.data.item;
            if (
              String(response.data.account_id) !== String(accountId.value) ||
              !sourceMatches(source, row, unitId.value)
            )
              throw sourceProblem();
            row.name = source.name;
            row.origin = Object.freeze({
              kind: source.latest_version.source_kind,
              description: source.description || '',
              purpose: source.purpose || '',
            });
          }),
        Promise.resolve()
      );
      if (current === generation) verified.value = true;
    } catch (problem) {
      if (current === generation) {
        if (denied(problem)) {
          forget();
          onDenied();
        } else
          error.value =
            problem.code === 'SOURCE_CHANGED' ? 'SOURCE_CHANGED' : 'ERROR';
      }
    } finally {
      if (current === generation) opening.value = false;
    }
  };
  const body = row => {
    if (!row.payload)
      row.payload = Object.freeze({
        asset: Object.freeze({
          name: row.name.trim(),
          description: row.origin.description,
          purpose: row.origin.purpose,
          folder_id: folderId.value || '',
        }),
        source_version_id: row.versionId,
        expected_revision: row.revision,
        idempotency_key: crypto.randomUUID(),
      });
    return row.payload;
  };
  const receipt = (response, row) => {
    const item = response.data?.item;
    const version = response.data?.received_version;
    const valid =
      String(response.data?.account_id) === String(accountId.value) &&
      identity(item?.id) &&
      identity(version?.id) &&
      !items.value.some(
        source => source.assetId === item.id || source.versionId === version.id
      ) &&
      !confirmed.value.some(
        source =>
          source.receipt.item.id === item.id ||
          source.receipt.received_version.id === version.id
      ) &&
      item.unit_id === unitId.value &&
      digest(item.revision) &&
      version.audio_asset_id === item.id &&
      version.unit_id === unitId.value &&
      version.number === 1 &&
      version.source_kind === row.origin.kind &&
      version.byte_size === row.byteSize &&
      version.sha256 === row.sha256;
    if (!valid) throw new Error('Invalid institutional copy receipt');
    return {
      account_id: String(response.data.account_id),
      item,
      received_version: version,
    };
  };
  const save = async () => {
    if (!canSave.value) return;
    const current = generation;
    saving.value = true;
    locked.value = true;
    error.value = '';
    try {
      await items.value.reduce(
        (chain, row) =>
          chain.then(async () => {
            if (current !== generation || row.status === 'confirmed') return;
            row.status = 'sending';
            try {
              const response = await API.duplicateAudioAsset(
                accountId.value,
                row.assetId,
                body(row)
              );
              if (current !== generation) return;
              row.receipt = receipt(response, row);
              row.status = 'confirmed';
            } catch (problem) {
              if (current === generation)
                row.status = [409, 422].includes(problem?.response?.status)
                  ? 'blocked'
                  : 'uncertain';
              throw problem;
            }
          }),
        Promise.resolve()
      );
    } catch (problem) {
      if (current === generation) {
        if (denied(problem)) {
          forget();
          onDenied();
        } else {
          reviewed.value = false;
          error.value =
            problem?.response?.status === 409 ? 'SOURCE_CHANGED' : 'ERROR';
        }
      }
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch(
    fingerprint,
    () => {
      reviewed.value = false;
    },
    { flush: 'sync' }
  );
  watch(
    [accountId, unitId, contextKey, canManage, admitted, selection],
    forget,
    { flush: 'sync' }
  );
  onBeforeUnmount(clear);
  return {
    dialog,
    active,
    items,
    folderId,
    folderLoading,
    opening,
    saving,
    busy,
    locked,
    reviewed,
    verified,
    error,
    confirmed,
    uncertain,
    complete,
    canSave,
    allowed,
    open,
    save,
    dismiss,
    clear,
    forget,
  };
};
